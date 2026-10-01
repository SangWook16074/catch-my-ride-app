import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../data/active_trip.dart';
import '../data/api.dart';
import '../data/recent_routes_store.dart';
import '../data/trip_start.dart';
import '../domain/journey.dart';
import '../domain/live_view.dart';
import '../domain/models.dart';
import '../platform/location.dart';
import 'components/ad_banner.dart';
import 'components/route_strip.dart';
import 'components/save_journey_sheet.dart';
import 'components/switch_leg_sheet.dart';
import 'components/trip_location_sheet.dart';
import 'design/components/button.dart';
import 'design/components/sheet.dart';
import 'design/tokens.dart';

/// 진행 중 트립 화면 (FR-705) — 남은 정거장 카운트다운, 환승 수동 재개(FR-703).
class TripPage extends StatefulWidget {
  const TripPage({
    super.key,
    required this.tripId,
    // 푸시 딥링크 진입은 여정 라벨을 모른다 — 기능명으로 대체
    this.journeyLabel = '하차 알림',
    this.journeyId,
    this.legs,
  });

  final String tripId;
  final String journeyLabel;

  /// 이 트립의 여정 — 있으면 LOST 화면에서 "처음부터 다시 추적"(같은 여정 재시작)을 제공한다.
  /// 푸시 딥링크 진입 등 모르는 경우 null — 버튼을 숨긴다
  final String? journeyId;

  /// 1회성 트립(FR-708)의 구간 스냅숏 — 여정 없이 시작했으므로 LOST 재시작·구간 표시·
  /// DONE 화면 "이 경로 저장하기"가 이 값을 쓴다. 저장 여정 트립은 null(여정에서 가져온다)
  final List<JourneyLeg>? legs;

  @override
  State<TripPage> createState() => _TripPageState();
}

class _TripPageState extends State<TripPage> {
  /// 상태·폴링·잠금화면 표면은 전역 `activeTrip`이 들고 있다 — 이 화면은 구독만 한다.
  /// (오너 피드백 2026-09-22: 화면마다 따로 폴링해서 탭 카드가 낡은 값에 묶였다)
  bool _restarting = false;

  /// "내가 탄 열차가 아니에요" 진행 중 — 연타로 되돌리기 횟수를 낭비하지 않게 잠근다 (§9-3)
  bool _reIdentifying = false;

  /// 구간 바꾸기 진행 중 (§9-3 v0.10) — 연타로 한도를 낭비하지 않게 잠근다
  bool _switchingLeg = false;

  /// "내렸어요" 진행 중 (§9-3 v0.11)
  bool _alighting = false;

  /// "아직 안 내렸어요" 진행 중 (§9-3 v0.11)
  bool _undoingAlight = false;

  /// "아직 안 내렸어요" 버튼이 마감 시각에 저절로 숨도록 거는 1회성 타이머 (§9-3 v0.11)
  Timer? _undoHideTimer;

  /// 1회성 트립을 완료 후 여정으로 저장했으면 그 라벨 — 저장 버튼을 안내로 바꾼다 (FR-708)
  String? _savedLabel;

  /// 단계 전환 햅틱을 1회만 울리기 위한 직전 단계
  TripPhase? _lastPhase;

  TripStatus? get _status => activeTrip.status;
  List<JourneyLeg>? get _legs => activeTrip.legs;
  bool get _stale => activeTrip.stale;
  bool get _gone => activeTrip.gone;

  /// 구독 중인 전역 트립 컨트롤러 — 구독과 해제가 같은 인스턴스를 향하게 붙잡아 둔다
  late final ActiveTripController _trip;

  @override
  void initState() {
    super.initState();
    _trip = activeTrip;
    _trip.addListener(_onTripChanged);
    _lastPhase = activeTrip.status?.phase;
    // 이어보기·푸시 딥링크로 들어왔을 수도 있다 — 컨트롤러가 이 트립을 추적하게 한다
    unawaited(
      activeTrip.adopt(
        tripId: widget.tripId,
        label: widget.journeyLabel,
        journeyId: widget.journeyId,
        legs: widget.legs,
      ),
    );
    // begin()의 알림이 이 위젯이 생기기 전에 이미 지나갔을 수 있다(시작 직후 바로 push하는
    // 흔한 경로) — 첫 프레임 뒤에 한 번 더 확인해 시작 구간 안내를 놓치지 않는다 (§9-2 v0.10)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _checkLegIndexNotice();
      }
    });
  }

  @override
  void dispose() {
    // 폴링은 멈추지 않는다 — 화면을 닫아도 탭 카드·잠금화면은 계속 갱신돼야 한다
    _trip.removeListener(_onTripChanged);
    _undoHideTimer?.cancel();
    super.dispose();
  }

  void _onTripChanged() {
    if (!mounted) {
      return;
    }
    // 화면을 보는 중에도 내릴 타이밍을 몸으로 알린다 — 도착 직전·환승·완료로
    // 넘어가는 순간 1회 (2026-09-19 실주행: 푸시만으로는 환승을 놓치기 쉽다)
    final phase = activeTrip.status?.phase;
    final previous = _lastPhase;
    if (phase != null &&
        previous != null &&
        previous != phase &&
        (phase == TripPhase.arriving ||
            phase == TripPhase.transfer ||
            phase == TripPhase.done)) {
      HapticFeedback.heavyImpact();
    }
    _lastPhase = phase;
    _checkLegIndexNotice();
    _scheduleUndoHide(activeTrip.status?.undoableUntil);
    setState(() {});
  }

  /// 시작 구간 판정(§9-2 v0.10)이 0이 아니면 구간 이름을 알 수 있게 되는 순간 1회 안내.
  /// 구간을 아직 모르면(저장 여정 조회가 늦는 경우) 다음 상태 변화 때 다시 시도한다
  void _checkLegIndexNotice() {
    final pending = activeTrip.pendingLegIndexNotice;
    if (pending == null) {
      return;
    }
    final legs = _legs;
    if (legs == null || pending < 0 || pending >= legs.length) {
      return;
    }
    activeTrip.clearLegIndexNotice();
    final leg = legs[pending];
    _showMessage('안내를 시작해요', '${leg.boardStop} → ${leg.alightStop} 구간부터 안내할게요');
  }

  /// "아직 안 내렸어요" 버튼이 마감 시각에 저절로 사라지게 — 값이 바뀔 때마다 다시 건다
  void _scheduleUndoHide(String? undoableUntil) {
    _undoHideTimer?.cancel();
    _undoHideTimer = null;
    if (undoableUntil == null) {
      return;
    }
    final deadline = DateTime.tryParse(undoableUntil);
    if (deadline == null) {
      return;
    }
    final wait = deadline.difference(DateTime.now());
    if (wait.isNegative) {
      return;
    }
    _undoHideTimer = Timer(wait, () {
      if (mounted) {
        setState(() {});
      }
    });
  }

  Future<void> _advanceLeg() async {
    // 새 구간도 위치로 탄 열차를 잡는다 — 권한이 없으면 재개하지 않고 허용으로 유도한다.
    // 트립은 서버에서 환승 대기로 남아 있어 허용 후 다시 누르면 그대로 이어진다 (2026-09-30)
    if (!await ensureTripLocationOrGuide(context) || !mounted) {
      return;
    }
    // 햅틱: 환승 재개 확정 (CLAUDE.md 적응형 UI 규칙)
    HapticFeedback.mediumImpact();
    try {
      final status = await advanceTrip(widget.tripId);
      activeTrip.apply(status);
    } on TripLocationPermissionRequired catch (denied) {
      // 권한 없이 재개하면 새 구간에서 뒤차를 잡는다 — 트립은 환승 대기로 남아 있으니
      // 권한을 허용하고 다시 누르면 그대로 이어진다 (오너 결정 2026-09-30)
      if (mounted) {
        unawaited(showTripLocationRequiredSheet(context, denied.permission));
      }
    } catch (_) {
      unawaited(activeTrip.refresh());
    }
  }

  /// "내가 탄 열차가 아니에요" — 이 구간을 다시 잡는다 (§9-3, 오너 요청 2026-09-30).
  ///
  /// 서버가 뒤차·앞차를 특정하면 카운트다운과 하차 알림이 유저 열차와 어긋난다. 트립을 버리고
  /// 새로 시작하면 1회성 구간·저장 흐름을 다시 타야 하므로 여기서 바로 고친다. 위치가 필요한
  /// 이유도 시작과 같다 — 이미 몇 정거장 갔으니 탑승역 전광판으로는 못 잡는다
  Future<void> _reIdentify() async {
    if (_reIdentifying) {
      return;
    }
    if (!await ensureTripLocationOrGuide(context) || !mounted) {
      return;
    }
    setState(() => _reIdentifying = true);
    HapticFeedback.mediumImpact();
    try {
      final status = await reIdentifyTrip(widget.tripId);
      activeTrip.apply(status);
      if (mounted) {
        _showMessage(
          '탄 열차를 다시 찾고 있어요',
          '지금 계신 위치를 기준으로 다시 잡아요. 조금 뒤 남은 정거장을 다시 알려드릴게요.',
        );
      }
    } on TripLocationPermissionRequired catch (denied) {
      if (mounted) {
        unawaited(showTripLocationRequiredSheet(context, denied.permission));
      }
    } on ApiException catch (error) {
      if (mounted) {
        _showMessage('다시 잡을 수 없어요', error.message);
      }
    } catch (_) {
      if (mounted) {
        _showMessage('다시 잡을 수 없어요', '네트워크를 확인하고 다시 시도해주세요');
      }
    } finally {
      if (mounted) {
        setState(() => _reIdentifying = false);
      }
    }
  }

  /// 구간 바꾸기 시트를 열고, 고르면 그 구간으로 전환한다 (§9-3 v0.10, 오너 결정 2026-10-01).
  /// 시작 구간 자동 판정이 틀렸거나 좌표 없이 0번 구간에 묶였을 때의 출구 — 고른 구간 안에서
  /// 중간 시작 판정을 다시 하므로 시작과 같은 권한 게이트·측위 1회를 거친다
  Future<void> _openSwitchLeg() async {
    if (_switchingLeg) {
      return;
    }
    final legs = _legs;
    final status = _status;
    if (legs == null || legs.length < 2 || status == null) {
      return;
    }
    final picked = await showSwitchLegSheet(
      context,
      legs: legs,
      currentLegIndex: status.legIndex,
    );
    if (picked == null || !mounted) {
      return;
    }
    if (!await ensureTripLocationOrGuide(context) || !mounted) {
      return;
    }
    setState(() => _switchingLeg = true);
    HapticFeedback.mediumImpact();
    try {
      final newStatus = await switchTripLeg(widget.tripId, picked);
      activeTrip.apply(newStatus);
    } on TripLocationPermissionRequired catch (denied) {
      if (mounted) {
        unawaited(showTripLocationRequiredSheet(context, denied.permission));
      }
    } on ApiException catch (error) {
      if (mounted) {
        // 트립당 3회 한도 초과 등 — 서버 메시지를 그대로("다시 시작해주세요")
        _showMessage('구간을 바꿀 수 없어요', error.message);
      }
    } catch (_) {
      if (mounted) {
        _showMessage('구간을 바꿀 수 없어요', '네트워크를 확인하고 다시 시도해주세요');
      }
    } finally {
      if (mounted) {
        setState(() => _switchingLeg = false);
      }
    }
  }

  /// "내렸어요" (§9-3 v0.11, 오너 결정 2026-10-01) — 상류 지연으로 화면이 한 정거장쯤
  /// 뒤처져도 유저가 서버를 기다리지 않게 한다. 환승 구간이면 곧바로 다음 구간이 시작되므로
  /// 시작과 같은 측위 1회가 필요하다(권한 거부면 막지 않고 시작처럼 안내 시트로 유도)
  Future<void> _alight() async {
    if (_alighting) {
      return;
    }
    final status = _status;
    if (status == null) {
      return;
    }
    final legs = _legs;
    final isLastLeg = legs != null && status.legIndex >= legs.length - 1;
    setState(() => _alighting = true);
    HapticFeedback.mediumImpact();
    try {
      final newStatus = await alightTrip(widget.tripId, isLastLeg: isLastLeg);
      activeTrip.apply(newStatus);
    } on TripLocationPermissionRequired catch (denied) {
      if (mounted) {
        unawaited(showTripLocationRequiredSheet(context, denied.permission));
      }
    } on ApiException catch (error) {
      // "아직 멀리 있어요" 등 — remainingStops가 늦게 바뀌어 버튼이 남아 있던 찰나
      if (mounted) {
        _showMessage('내린 걸로 처리할 수 없어요', error.message);
        unawaited(activeTrip.refresh());
      }
    } catch (_) {
      if (mounted) {
        _showMessage('내린 걸로 처리할 수 없어요', '네트워크를 확인하고 다시 시도해주세요');
      }
    } finally {
      if (mounted) {
        setState(() => _alighting = false);
      }
    }
  }

  /// "아직 안 내렸어요" (§9-3 v0.11) — 실수로 "내렸어요"를 눌렀을 때 직전 구간을 그대로
  /// 복원한다. 되돌리기는 서버가 보관해 둔 상태를 그대로 쓰므로 새 측위가 필요 없다
  Future<void> _undoAlight() async {
    if (_undoingAlight) {
      return;
    }
    setState(() => _undoingAlight = true);
    HapticFeedback.mediumImpact();
    try {
      final status = await undoAlightTrip(widget.tripId);
      activeTrip.apply(status);
    } on ApiException catch (error) {
      // 마감 지남·한도 초과("이미 시간이 지나…", "다시 시작해주세요") — 서버 메시지 그대로
      if (mounted) {
        _showMessage('되돌릴 수 없어요', error.message);
      }
    } catch (_) {
      if (mounted) {
        _showMessage('되돌릴 수 없어요', '네트워크를 확인하고 다시 시도해주세요');
      }
    } finally {
      if (mounted) {
        setState(() => _undoingAlight = false);
      }
    }
  }

  /// 같은 구간으로 재시작할 수 있는가 — 저장 여정이거나 1회성 스냅숏이 있으면
  bool get _canRestart => widget.journeyId != null || widget.legs != null;

  /// 1회성 트립인가 — 여정 없이 스냅숏으로 시작한 트립 (완료 후 저장 제안 대상)
  bool get _isOneOff => widget.journeyId == null && widget.legs != null;

  /// LOST에서 같은 여정(또는 1회성 구간 스냅숏)으로 처음부터 다시 시작 — 기존 트립
  /// 종료(멱등, §9-3) 후 새 트립. 서버가 재목격 복구를 계속 시도하므로(§9-3) 이 버튼은
  /// "기다리기 싫을 때"의 출구다
  Future<void> _restart() async {
    final journeyId = widget.journeyId;
    final legs = widget.legs;
    if (!_canRestart || _restarting) {
      return;
    }
    if (!await ensureTripLocationOrGuide(context) || !mounted) {
      return;
    }
    setState(() => _restarting = true);
    HapticFeedback.mediumImpact();
    try {
      await api.endTrip(widget.tripId);
    } catch (_) {
      // 종료 실패해도 진행 — startTrip이 막히면 아래에서 안내한다
    }
    try {
      final TripStart start;
      if (journeyId != null) {
        start = await startJourneyTrip(journeyId);
      } else {
        start = await startQuickTrip(legs!);
        unawaited(RecentRoutesStore().push(legs));
      }
      // 새 트립으로 갈아탄다 — 보관·잠금화면 표면·폴링을 컨트롤러가 다시 건다
      unawaited(
        activeTrip.begin(
          tripId: start.tripId,
          label: widget.journeyLabel,
          journeyId: journeyId,
          legs: journeyId == null ? legs : null,
          legIndex: start.legIndex,
        ),
      );
      if (!mounted) {
        return;
      }
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => TripPage(
            tripId: start.tripId,
            journeyLabel: widget.journeyLabel,
            journeyId: journeyId,
            legs: legs,
          ),
        ),
      );
    } on TripLocationPermissionRequired catch (denied) {
      if (!mounted) {
        return;
      }
      setState(() => _restarting = false);
      unawaited(showTripLocationRequiredSheet(context, denied.permission));
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _restarting = false);
      _showMessage('다시 시작할 수 없어요', error.message);
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _restarting = false);
      _showMessage('다시 시작할 수 없어요', '네트워크를 확인하고 다시 시도해주세요');
    }
  }

  void _showMessage(String header, String body) {
    unawaited(
      showAppSheet<void>(
        context: context,
        header: header,
        builder: (sheetContext) => Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.xl,
            0,
            AppSpace.xl,
            AppSpace.lg,
          ),
          child: Text(
            body,
            style: AppTypo.bodySm.copyWith(color: sheetContext.colors.inkMuted),
          ),
        ),
      ),
    );
  }

  /// 1회성 트립의 "경로 저장하기" (FR-708 → FR-702) — 트립 중·환승 대기·도착 어디서든.
  /// 라벨만 입력, 10개 초과·중복 라벨은 서버 400 메시지를 그대로 보여준다
  Future<void> _saveAsJourney() async {
    final legs = widget.legs;
    if (legs == null) {
      return;
    }
    final label = await showSaveJourneySheet(context, legs);
    if (label == null || !mounted) {
      return;
    }
    setState(() => _savedLabel = label);
  }

  /// 1회성 트립에만 붙는 저장 행 — 저장 전엔 버튼, 저장 후엔 안내 (오너 화면 재구성 2026-09-21:
  /// 도착 화면에서만 제안하면 앱을 먼저 닫은 사람은 저장 기회를 놓친다)
  Widget? _saveRow() {
    if (!_isOneOff) {
      return null;
    }
    final savedLabel = _savedLabel;
    if (savedLabel != null) {
      return Text(
        '"$savedLabel" 여정으로 저장했어요',
        textAlign: TextAlign.center,
        style: AppTypo.bodySm.copyWith(color: context.colors.primaryStrong),
      );
    }
    // 하단 묶음의 종료 버튼과 같은 크기(block, 기본 높이) — 나란히 둘 때 레이아웃 통일 (오너 피드백 2026-09-21)
    return AppButton(
      label: '경로 저장하기',
      variant: AppButtonVariant.tonal,
      block: true,
      onPressed: () => unawaited(_saveAsJourney()),
    );
  }

  Future<void> _end() async {
    // 종료는 멱등(§9-3) — 실패해도 로컬·표면은 정리되고 화면은 닫는다
    unawaited(activeTrip.finish());
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final saveRow = _saveRow();
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(
        title: Text(widget.journeyLabel, style: AppTypo.heading),
      ),
      // 본문·광고·종료 버튼을 하단에 한 묶음으로 붙인다 — 남는 여백은 요소 사이에
      // 끼우지 않고 위쪽으로만 몬다 (오너 피드백 2026-09-19 2차). 작은 화면에서
      // 묶음이 화면보다 길어지면 넘치는 대신 스크롤로 강등한다
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Padding(
                padding: const EdgeInsets.all(AppSpace.xl),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    _body(),
                    // 트립 진행 중에도 광고 노출 (오너 결정 2026-09-16 2차: 트립 화면
                    // 금지 폐기 — 화면을 오래 보는 구간이라 내정보 대신 여기에 둔다).
                    // 종료 버튼 위 MREC(300×250, 동영상 크리에이티브 가능).
                    // reserveSpace: 로드 전에도 300×250 자리를 잡아둔다 — 광고가 늦게
                    // 뜰 때 카운트다운·버튼이 밀리는 것 방지 (오너 피드백 2026-09-19 3차)
                    const AdBanner(size: AdSize.mediumRectangle, reserveSpace: true),
                    // 하단 액션 묶음 — 1회성 저장 행과 종료/완료를 붙여 둔다. 광고가 둘 사이를
                    // 가르지 않게 (오너 피드백 2026-09-21)
                    if (!_gone) ...[
                      if (saveRow != null) ...[saveRow, const SizedBox(height: AppSpace.sm)],
                      if (_status?.phase == TripPhase.done)
                        AppButton(label: '완료', block: true, onPressed: () => unawaited(_end()))
                      else
                        AppButton(
                          label: '경로 종료',
                          variant: AppButtonVariant.danger,
                          block: true,
                          onPressed: () => unawaited(_end()),
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _body() {
    if (_gone) {
      return _message(
        title: '트립이 종료됐어요',
        subtitle: '이미 끝났거나 서버에서 정리된 트립이에요',
        button: AppButton(
          label: '돌아가기',
          onPressed: () {
            activeTrip.clearGone();
            Navigator.of(context).pop();
          },
        ),
      );
    }
    final status = _status;
    if (status == null) {
      return Text(
        '트립 정보를 불러오고 있어요…',
        style: AppTypo.bodySm.copyWith(color: context.colors.inkSubtle),
      );
    }
    switch (status.phase) {
      case TripPhase.tracking:
      case TripPhase.arriving:
        final arriving = status.phase == TripPhase.arriving;
        final remaining = status.remainingStops;
        // TRACKING + remaining null = 열차 특정 전 "위치 확인 중" — 숫자를 지어내지 않는다 (API.md §9-3)
        final identifying = !arriving && remaining == null;
        // 특정 전이라도 서버가 노선 전체 위치로 후보를 목격하면 currentStop을 준다
        // (§9-3 2026-09-16 개정) — 카운트는 몰라도 위치는 보여준다
        final locatedStop = status.currentStop;
        final legs = _legs;
        final leg = legs != null && status.legIndex >= 0 && status.legIndex < legs.length
            ? legs[status.legIndex]
            : null;
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '${status.eventStop}에서 내려요',
              textAlign: TextAlign.center,
              style: AppTypo.title,
            ),
            const SizedBox(height: AppSpace.lg),
            Text(
              arriving
                  ? '다음 역이에요!'
                  : identifying
                  ? (locatedStop != null ? '현재 $locatedStop 부근' : '위치 확인 중이에요…')
                  : '$remaining정거장 남았어요',
              textAlign: TextAlign.center,
              style: AppTypo.title.copyWith(
                color: arriving
                    ? context.colors.cautionStrong
                    : identifying && locatedStop == null
                    ? context.colors.inkSubtle
                    : context.colors.primaryStrong,
              ),
            ),
            if (arriving) ...[
              const SizedBox(height: AppSpace.sm),
              Text(
                '내릴 준비를 해주세요',
                style: AppTypo.bodySm.copyWith(color: context.colors.inkMuted),
              ),
            ],
            // 특정 후 카운트다운 중 — 열차 현재 위치 역명 (§9-3 currentStop, 모르면 생략)
            if (!arriving && !identifying && locatedStop != null) ...[
              const SizedBox(height: AppSpace.sm),
              Text(
                '현재 $locatedStop 부근',
                textAlign: TextAlign.center,
                style: AppTypo.bodySm.copyWith(color: context.colors.inkMuted),
              ),
            ],
            if (identifying) ...[
              if (leg != null) ...[
                const SizedBox(height: AppSpace.xl),
                RouteStrip(
                  boardStop: leg.boardStop,
                  eventStop: status.eventStop,
                  line: leg.line,
                ),
              ],
              const SizedBox(height: AppSpace.md),
              Text(
                locatedStop != null
                    ? '하차역에 가까워지면 남은 정거장을 알려드려요'
                    : '탑승한 열차를 찾고 있어요. 곧 남은 정거장을 알려드려요',
                textAlign: TextAlign.center,
                style: AppTypo.bodySm.copyWith(color: context.colors.inkMuted),
              ),
            ],
            const SizedBox(height: AppSpace.lg),
            // "내렸어요" — 하차역 2정거장 이내일 때만 (§9-3 v0.11). 상류 지연·서버 틱·클라
            // 폴링이 쌓여 화면이 뒤처져도 유저가 서버를 기다리지 않게 하는 출구
            if (canAlightNow(status)) ...[
              AppButton(
                label: _alighting ? '처리하는 중…' : '내렸어요',
                block: true,
                onPressed: _alighting ? null : () => unawaited(_alight()),
              ),
              const SizedBox(height: AppSpace.md),
            ],
            // 서버가 유저가 탄 열차가 아닌 차량을 잡았을 때의 출구 (§9-3 다시 잡기).
            // "현재 ○○ 부근"이 내 위치와 다르면 유저가 제일 먼저 알아챈다 (오너 요청 2026-09-30)
            AppButton(
              label: _reIdentifying ? '다시 잡고 있어요…' : '내가 탄 열차가 아니에요',
              variant: AppButtonVariant.tonal,
              medium: true,
              onPressed: _reIdentifying ? null : () => unawaited(_reIdentify()),
            ),
            if (_switchLegButton() case final switchButton?) ...[
              const SizedBox(height: AppSpace.sm),
              switchButton,
            ],
            if (_undoAlightButton(status) case final undoButton?) ...[
              const SizedBox(height: AppSpace.sm),
              undoButton,
            ],
            const SizedBox(height: AppSpace.md),
            _footer(status),
          ],
        );
      case TripPhase.transfer:
        return _message(
          title: '${status.eventStop} 도착, 갈아탈 시간이에요',
          subtitle: '다음 구간 차량에 탑승하면 아래를 눌러주세요',
          button: AppButton(
            label: '다음 구간 탔어요',
            block: true,
            onPressed: () => unawaited(_advanceLeg()),
          ),
          secondary: _switchLegButton(),
        );
      case TripPhase.done:
        // 완료 버튼은 하단 액션 묶음(저장 행 옆)에 있다. "내렸어요"로 끝낸 마지막 구간은
        // undoableUntil이 지나기 전까지 이 화면에서도 되돌릴 수 있다 (§9-3 v0.11)
        return _message(
          title: '목적지에 도착했어요',
          subtitle: '오늘도 놓치지 않았어요. 수고했어요!',
          button: null,
          secondary: _undoAlightButton(status),
        );
      case TripPhase.lost:
        // 서버가 재목격·재특정을 계속 시도한다 (§9-3) — 신호가 돌아오면 이 화면은 저절로 풀린다
        return _message(
          title: '추적이 잠시 끊겼어요',
          subtitle: '신호가 다시 잡히면 자동으로 이어가요.\n그동안 역 안내방송을 확인해주세요',
          button: !_canRestart
              ? null
              : AppButton(
                  label: _restarting ? '다시 시작하는 중…' : '처음부터 다시 추적',
                  variant: AppButtonVariant.tonal,
                  block: true,
                  onPressed: _restarting ? null : () => unawaited(_restart()),
                ),
        );
    }
  }

  Widget _message({
    required String title,
    required String subtitle,
    required Widget? button,
    Widget? secondary,
  }) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(title, textAlign: TextAlign.center, style: AppTypo.title),
        const SizedBox(height: AppSpace.sm),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: AppTypo.bodySm.copyWith(color: context.colors.inkMuted),
        ),
        if (button != null) ...[const SizedBox(height: AppSpace.lg), button],
        if (secondary != null) ...[const SizedBox(height: AppSpace.md), secondary],
      ],
    );
  }

  /// 구간 바꾸기 보조 액션 (§9-3 v0.10) — 구간이 2개 이상일 때만 노출
  Widget? _switchLegButton() {
    final legs = _legs;
    if (legs == null || legs.length < 2) {
      return null;
    }
    return AppButton(
      label: _switchingLeg ? '구간을 바꾸는 중…' : '구간 바꾸기',
      variant: AppButtonVariant.tonal,
      medium: true,
      onPressed: _switchingLeg ? null : () => unawaited(_openSwitchLeg()),
    );
  }

  /// "아직 안 내렸어요" 보조 액션 (§9-3 v0.11) — undoableUntil이 있고 지나지 않았을 때만.
  /// 마감 전엔 추적 중 화면·도착 화면 어디서든 뜰 수 있다("내렸어요"가 곧바로 다음 구간을
  /// 시작하거나 트립을 끝내기 때문)
  Widget? _undoAlightButton(TripStatus status) {
    if (!canUndoAlightAt(status.undoableUntil, DateTime.now())) {
      return null;
    }
    return AppButton(
      label: _undoingAlight ? '되돌리는 중…' : '아직 안 내렸어요',
      variant: AppButtonVariant.tonal,
      medium: true,
      onPressed: _undoingAlight ? null : () => unawaited(_undoAlight()),
    );
  }

  Widget _footer(TripStatus status) {
    // 실시간이 끊긴 동안에도 추적은 유지된다(오너 결정 2026-09-30) — 그래서 지금 보이는 숫자가
    // **언제 기준**인지 말해줘야 한다. 낡은 값을 현재처럼 보여주면 조용히 틀리는 것과 같다 (NFR-03)
    final seenAgo = status.realtimeAvailable || status.lastSeenAt == null
        ? null
        : formatSeenAgo(status.lastSeenAt!);
    return Text(
      _stale
          ? '갱신이 늦어져 마지막 정보를 보여드리고 있어요'
          : seenAgo != null
          ? '열차 위치는 $seenAgo 기준이에요 · 실시간 정보 없음'
          : '${formatFetchedAt(status.fetchedAt)} 기준'
                '${status.realtimeAvailable ? '' : ' · 실시간 정보 없음'}',
      style: AppTypo.caption.copyWith(
        color: _stale || seenAgo != null
            ? context.colors.cautionStrong
            : context.colors.inkFaint,
      ),
    );
  }
}
