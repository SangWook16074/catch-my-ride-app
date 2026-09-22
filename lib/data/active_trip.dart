/// 진행 중 트립(하차 알림) 전역 상태 — 메인 탭 요약 카드·하차 알림 탭·트립 화면이
/// **같은 값 하나**를 본다 (오너 피드백 2026-09-22: 화면마다 따로 조회해서, 서버가 열차를
/// 특정한 뒤에도 탭 카드는 "위치 확인 중"에 묶여 있었다).
///
/// 서버에 "내 활성 트립 조회"가 없으므로(API.md §9) 로컬 보관 tripId(`TripStore`)를 원본으로
/// 삼아 폴링하고, 잠금화면 표면(FR-705)도 여기서 갱신한다 — 트립 화면을 닫아도 폴링·표면이
/// 같이 살아 있어야 탭 카드가 낡지 않는다. 판정은 여전히 서버 몫, 여기는 표시용 상태다(NFR-03).
///
/// `push_registrar.dart`와 같은 data 레이어 오케스트레이터다 — api·로컬 저장소·platform
/// 브리지를 묶되 비즈니스 규칙은 두지 않는다 (CLAUDE.md 레이어 규칙).
library;

import 'dart:async';

import 'package:flutter/widgets.dart';

import '../domain/journey.dart';
import '../domain/models.dart';
import '../platform/live_activity.dart';
import 'api.dart';
import 'trip_store.dart';

/// 트립 폴링 주기 — FR-204 준용(15~30초). 하차 판정·푸시는 서버 몫, 화면은 표시만
const Duration tripPollInterval = Duration(seconds: 20);

/// 여정 라벨을 모르는 진입(푸시 딥링크 등)의 기본 라벨 — 기능명으로 대체
const String defaultTripLabel = '하차 알림';

class ActiveTripController extends ChangeNotifier {
  ActiveTripController();

  final TripStore _store = TripStore();
  final LiveActivityBridge _liveActivity = LiveActivityBridge();

  String? _tripId;
  TripStatus? _status;
  String? _journeyId;
  List<JourneyLeg>? _legs;
  String _label = defaultTripLabel;
  bool _stale = false;
  bool _gone = false;

  Timer? _timer;
  AppLifecycleListener? _lifecycle;
  bool _refreshing = false;

  /// 추적 대상이 바뀐 횟수 — 느린 복원이 방금 시작한 트립을 덮어쓰지 않게 하는 표식
  int _generation = 0;

  /// 추적 중인 트립 id — 없으면 null
  String? get tripId => _tripId;

  /// 마지막으로 받은 서버 상태 — 아직 못 받았으면 null
  TripStatus? get status => _status;

  String? get journeyId => _journeyId;

  /// 이 트립의 구간 — 저장 여정은 여정 조회로, 1회성은 스냅숏으로 채운다. 모르면 null
  List<JourneyLeg>? get legs => _legs;

  String get label => _label;

  /// 갱신이 늦어져 마지막 정보를 보여주는 중
  bool get stale => _stale;

  /// 서버에서 정리된 트립(404) — 화면은 종료 안내로 강등한다
  bool get gone => _gone;

  /// 카드·배너를 띄울 수 있는 상태인가 — id와 상태가 둘 다 있고 살아 있을 때
  bool get hasTrip => _tripId != null && _status != null && !_gone;

  /// 같은 구간으로 재시작할 수 있는가 — 저장 여정이거나 1회성 스냅숏이 있으면
  bool get canRestart => _journeyId != null || _legs != null;

  /// 1회성 트립인가 — 여정 없이 스냅숏으로 시작한 트립 (완료 후 저장 제안 대상)
  bool get isOneOff => _journeyId == null && _legs != null;

  /// 이동 중 구간(탑승역→하차역) — 카드의 구간 스트립용. 이동 중이고 구간을 알 때만
  JourneyLeg? get currentLeg {
    final status = _status;
    final legs = _legs;
    if (status == null || legs == null) {
      return null;
    }
    if (status.phase != TripPhase.tracking &&
        status.phase != TripPhase.arriving) {
      return null;
    }
    if (status.legIndex < 0 || status.legIndex >= legs.length) {
      return null;
    }
    return legs[status.legIndex];
  }

  /// 앱 시작·탭 복귀 시 로컬 보관에서 복원한다. 보관이 없으면 상태를 비운다.
  /// 이미 같은 트립을 추적 중이면 폴링만 이어가고 잠금화면 표면은 건드리지 않는다
  /// (표면 재시작은 활동을 껐다 켜므로 새 트립일 때만 — LiveActivityBridge.start 계약)
  Future<void> restore() async {
    final generation = _generation;
    final storedId = await _store.read();
    if (generation != _generation) {
      return; // 복원 중에 트립이 시작·종료됐다 — 그쪽이 최신이다
    }
    if (storedId == null) {
      if (_tripId != null) {
        _reset();
        notifyListeners();
      }
      return;
    }
    if (storedId == _tripId) {
      _ensurePolling();
      await refresh();
      return;
    }
    final journeyId = await _store.readJourneyId();
    final legs = await _store.readLegs();
    if (generation != _generation) {
      return;
    }
    _generation++;
    _tripId = storedId;
    _status = null;
    _stale = false;
    _gone = false;
    _journeyId = journeyId;
    _legs = legs;
    notifyListeners();
    _ensurePolling();
    // 구간 조회는 폴링과 나란히 — 뒤에 줄 세우면 "위치 확인 중" 화면의 구간 스트립이 늦는다
    unawaited(_resolveLegs());
    await refresh();
  }

  /// 트립을 막 시작했다 — 로컬 보관·잠금화면 표면·폴링을 한 번에 건다.
  /// 시작 지점(메인·하차 알림 탭·라이브 뷰·경로 만들기)은 이 메서드만 부르면 된다
  Future<void> begin({
    required String tripId,
    required String label,
    String? journeyId,
    List<JourneyLeg>? legs,
  }) async {
    _generation++;
    _tripId = tripId;
    _label = label;
    _journeyId = journeyId;
    _legs = legs;
    _status = null;
    _stale = false;
    _gone = false;
    notifyListeners();
    unawaited(_store.write(tripId, journeyId: journeyId, legs: legs));
    // 잠금화면 표면 시작 (FR-705) — 미지원 기기는 조용히 무시된다
    unawaited(_liveActivity.start(label, tripId: tripId));
    _ensurePolling();
    // 구간 조회는 폴링과 나란히 — 뒤에 줄 세우면 "위치 확인 중" 화면의 구간 스트립이 늦는다
    unawaited(_resolveLegs());
    await refresh();
  }

  /// 이미 있는 트립으로 들어왔다 (이어보기·푸시 딥링크) — 추적 중이면 라벨·구간만 보강하고,
  /// 모르는 트립이면 그 트립으로 갈아탄다
  Future<void> adopt({
    required String tripId,
    String? label,
    String? journeyId,
    List<JourneyLeg>? legs,
  }) async {
    if (tripId == _tripId) {
      var changed = false;
      if (label != null && label != defaultTripLabel && label != _label) {
        _label = label;
        changed = true;
      }
      if (journeyId != null && journeyId != _journeyId) {
        _journeyId = journeyId;
        changed = true;
      }
      if (legs != null && _legs == null) {
        _legs = legs;
        changed = true;
      }
      if (_gone) {
        _gone = false;
        changed = true;
      }
      if (changed) {
        notifyListeners();
      }
      _ensurePolling();
      // 이미 받아 둔 상태가 있으면 다시 묻지 않는다 — 화면을 여는 것만으로 폴링을 한 번 더
      // 태우면 서버 호출이 겹치고(§9 부하), 화면이 "위치 확인 중" 단계를 건너뛴다
      if (_status == null) {
        await refresh();
      }
      return;
    }
    _generation++;
    _tripId = tripId;
    _label = label ?? defaultTripLabel;
    _journeyId = journeyId;
    _legs = legs;
    _status = null;
    _stale = false;
    _gone = false;
    notifyListeners();
    unawaited(_liveActivity.start(_label, tripId: tripId));
    _ensurePolling();
    // 구간 조회는 폴링과 나란히 — 뒤에 줄 세우면 "위치 확인 중" 화면의 구간 스트립이 늦는다
    unawaited(_resolveLegs());
    await refresh();
  }

  /// 서버 상태 1회 조회. 종착(완료·환승 대기)에서는 더 묻지 않는다 —
  /// 다음 행동은 사용자의 몫이고, mock은 폴링마다 전진하므로 화면 고정에도 필요하다
  Future<void> refresh() async {
    final tripId = _tripId;
    if (tripId == null || _gone || _refreshing) {
      return;
    }
    final phase = _status?.phase;
    if (phase == TripPhase.done || phase == TripPhase.transfer) {
      return;
    }
    _refreshing = true;
    try {
      final status = await api.getTrip(tripId);
      if (tripId != _tripId) {
        return; // 조회 중 트립이 바뀌었다 — 낡은 응답 버림
      }
      apply(status);
    } on ApiException catch (error) {
      if (tripId != _tripId) {
        return;
      }
      if (error.status == 404) {
        // 서버에서 정리된 트립 — 이어보기·잠금화면도 같이 정리한다
        await forget();
        return;
      }
      _stale = true;
      notifyListeners();
    } catch (_) {
      if (tripId != _tripId) {
        return;
      }
      _stale = true;
      notifyListeners();
    } finally {
      _refreshing = false;
    }
  }

  /// 서버에서 받은 상태를 반영한다 — 폴링과 환승 재개(§9-3) 응답이 같은 길로 들어온다.
  /// 잠금화면 표면 갱신도 여기 한 곳에서 (FR-705)
  void apply(TripStatus status) {
    _status = status;
    _stale = false;
    _gone = false;
    unawaited(_liveActivity.update(status));
    _ensurePolling();
    notifyListeners();
  }

  /// 트립 종료 (완료·취소 공용) — 서버 종료는 멱등(§9-3), 실패해도 로컬은 정리한다
  Future<void> finish() async {
    final tripId = _tripId;
    _generation++;
    _reset();
    notifyListeners();
    unawaited(_store.clear());
    unawaited(_liveActivity.end());
    if (tripId == null) {
      return;
    }
    try {
      await api.endTrip(tripId);
    } catch (_) {
      // 서버가 자동 정리한다 (§9-3)
    }
  }

  /// 서버에 없는 트립으로 판명 — 종료 안내로 강등하고 보관·표면을 정리한다
  Future<void> forget() async {
    _generation++;
    _gone = true;
    _status = null;
    _stale = false;
    _stopPolling();
    notifyListeners();
    unawaited(_store.clear());
    unawaited(_liveActivity.end());
  }

  /// 종료 안내를 닫았다 — 다음 복원이 깨끗하게 시작하도록 흔적을 지운다
  void clearGone() {
    if (!_gone) {
      return;
    }
    _reset();
    notifyListeners();
  }

  /// 저장 여정 트립의 구간을 여정 조회로 채운다 — 표시 보강이라 실패는 조용히 무시
  Future<void> _resolveLegs() async {
    final journeyId = _journeyId;
    if (_legs != null || journeyId == null) {
      return;
    }
    try {
      final journeys = await api.listJourneys();
      if (journeyId != _journeyId) {
        return;
      }
      for (final journey in journeys) {
        if (journey.id == journeyId) {
          _legs = journey.legs;
          notifyListeners();
          return;
        }
      }
    } catch (_) {
      // 구간 스트립이 안 그려질 뿐 — 트립 추적에는 영향 없음
    }
  }

  void _reset() {
    _tripId = null;
    _status = null;
    _journeyId = null;
    _legs = null;
    _label = defaultTripLabel;
    _stale = false;
    _gone = false;
    _stopPolling();
  }

  /// 트립이 살아 있고 보는 화면이 있는 동안만 폴링한다 — 종착 상태는 타이머를 걷는다.
  /// 구독자 기준이라 화면이 모두 사라지면(앱 트리 폐기) 타이머도 같이 사라진다
  void _ensurePolling() {
    final phase = _status?.phase;
    final done = phase == TripPhase.done || phase == TripPhase.transfer;
    if (_tripId == null || _gone || done || !hasListeners) {
      _stopPolling();
      return;
    }
    _timer ??= Timer.periodic(tripPollInterval, (_) => unawaited(refresh()));
    // 잠금·백그라운드 동안 타이머가 멈춘다 — 돌아오면 다음 틱을 기다리지 않고 즉시 갱신
    // (2026-09-15 실주행 피드백: 지하철에서 폰을 껐다 켜면 화면이 낡아 보였다)
    _lifecycle ??= AppLifecycleListener(onResume: () => unawaited(refresh()));
  }

  void _stopPolling() {
    _timer?.cancel();
    _timer = null;
    _lifecycle?.dispose();
    _lifecycle = null;
  }

  @override
  void addListener(VoidCallback listener) {
    super.addListener(listener);
    _ensurePolling();
  }

  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
    if (!hasListeners) {
      _stopPolling();
    }
  }

  @override
  void dispose() {
    _stopPolling();
    super.dispose();
  }
}

/// 앱 전역 진행 중 트립 — api 싱글턴과 같은 방식 (테스트에서 교체 가능)
ActiveTripController activeTrip = ActiveTripController();
