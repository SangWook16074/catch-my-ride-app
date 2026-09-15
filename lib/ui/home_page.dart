import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/api.dart';
import '../data/suggestion_store.dart';
import '../data/trip_store.dart';
import '../domain/buffer_suggestion.dart';
import '../domain/journey.dart';
import '../domain/models.dart';
import '../domain/push_entry.dart';
import '../platform/deep_links.dart';
import '../platform/push.dart';
import 'components/route_delete_sheet.dart';
import 'components/route_rename_sheet.dart';
import 'design/components/button.dart';
import 'design/components/chip.dart';
import 'design/components/sheet.dart';
import 'design/tokens.dart';
import 'live_view_screen.dart';
import 'onboarding_page.dart';
import 'trip_page.dart';

/// 라이브 뷰 폴링 주기 — FR-204: 활성 사용 시 15~30초
const Duration _pollInterval = Duration(seconds: 20);

enum _Phase { loading, loadFailed, needOnboarding, ready }

/// 메인 화면 — 미니앱 pages/index.tsx 이식.
/// 경로 칩 바 + 라이브 뷰. 온보딩 미완료면 시작 안내를 보여준다.
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  final SuggestionStore _suggestionStore = SuggestionStore();
  final TripStore _tripStore = TripStore();

  _Phase _phase = _Phase.loading;
  ArrivalsResponse? _response;

  /// 다중 경로(출근·퇴근) — 선택된 경로 기준으로 도착 정보를 폴링한다
  List<CommuteRoute> _routes = [];
  String? _selectedRouteId;
  bool _stale = false;
  BoardingResult? _todayFeedback;

  /// §3-1 버퍼 자동 추천 — 놓침이 잦으면 +5분 제안 카드
  BufferRecommendation? _bufferSuggestion;
  int? _appliedBufferMinutes;

  Timer? _timer;
  bool _hasData = false;

  /// 푸시 딥링크가 알려준 날짜 — 피드백 기록에 쓴다 (자정 넘김 등 엣지 대비)
  final DeepLinks _deepLinks = DeepLinks();
  final PushBridge _push = PushBridge();
  String? _pushNotifiedDate;
  StreamSubscription<Uri>? _linkSub;
  StreamSubscription<Uri>? _pushLinkSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refresh());
    unawaited(_checkBufferSuggestion());
    unawaited(_initDeepLinks());
    _timer = Timer.periodic(_pollInterval, (_) => unawaited(_refresh()));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    unawaited(_linkSub?.cancel());
    unawaited(_pushLinkSub?.cancel());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 잠금·백그라운드 동안 폴링 타이머가 멈춘다 — 돌아오면 즉시 갱신 (2026-09-15 실주행 피드백)
    if (state == AppLifecycleState.resumed) {
      unawaited(_refresh());
    }
  }

  /// 딥링크 진입(catchmyride://open?from=push&notifiedDate=…) —
  /// 커스텀 스킴(콜드·웜)과 FCM 알림 탭(data.link) 모두 같은 파서를 태운다
  Future<void> _initDeepLinks() async {
    _pushLinkSub = _push.openedLinks.listen((uri) {
      if (mounted) {
        _handleLink(uri);
      }
    });
    final initial = await _deepLinks.getInitialLink();
    if (mounted && initial != null) {
      _handleLink(initial);
    }
    _linkSub = _deepLinks.uriStream.listen((uri) {
      if (mounted) {
        _handleLink(uri);
      }
    });
  }

  /// 푸시로 들어왔으면 탑승 여부 프롬프트를 먼저 띄운다 (미니앱 promptFeedback 이식).
  /// 이미 오늘 피드백을 남겼으면 다시 묻지 않는다
  void _handleLink(Uri uri) {
    // 하차 푸시(catchmyride://trip?tripId=…, §9-4) — 트립 진행 화면으로.
    // 탑승 피드백 프롬프트(from=push)와는 별개 흐름
    final tripId = parseTripLink(uri);
    if (tripId != null) {
      unawaited(_openTripLink(tripId));
      return;
    }
    final entry = parsePushEntry(uri);
    if (!entry.fromPush || _todayFeedback != null) {
      return;
    }
    _pushNotifiedDate = entry.notifiedDate;
    unawaited(
      showAppSheet<void>(
        context: context,
        header: '오늘 알림대로 탑승하셨나요?',
        builder: (sheetContext) => Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.xl,
            0,
            AppSpace.xl,
            AppSpace.lg,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '알려주시면 다음 알림이 더 정확해져요',
                style: AppTypo.bodySm.copyWith(
                  color: sheetContext.colors.inkMuted,
                ),
              ),
              const SizedBox(height: AppSpace.md),
              Row(
                children: [
                  for (final (index, result) in const [
                    BoardingResult.boarded,
                    BoardingResult.missed,
                  ].indexed) ...[
                    if (index > 0) const SizedBox(width: AppSpace.sm),
                    Expanded(
                      child: AppButton(
                        label: result == BoardingResult.boarded
                            ? '탔어요'
                            : '놓쳤어요',
                        variant: result == BoardingResult.boarded
                            ? AppButtonVariant.primary
                            : AppButtonVariant.tonal,
                        medium: true,
                        block: true,
                        onPressed: () {
                          Navigator.of(sheetContext).pop();
                          HapticFeedback.mediumImpact();
                          unawaited(_handleFeedback(result));
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 트립 딥링크 진입 — 로컬 보관이 같은 트립이면 여정 id도 같이 넘긴다
  /// (LOST 화면 "처음부터 다시 추적" 진입점)
  Future<void> _openTripLink(String tripId) async {
    final storedTripId = await _tripStore.read();
    final journeyId =
        storedTripId == tripId ? await _tripStore.readJourneyId() : null;
    if (!mounted) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TripPage(tripId: tripId, journeyId: journeyId),
      ),
    );
  }

  Future<void> _refresh() async {
    try {
      // 경로 목록은 폴링마다 갱신 — 온보딩에서의 추가·삭제를 자연 반영한다
      final nextRoutes = await api.listCommuteRoutes();
      if (!mounted) {
        return;
      }
      if (nextRoutes.isEmpty) {
        setState(() => _phase = _Phase.needOnboarding);
        return;
      }
      var routeId = _selectedRouteId;
      if (routeId == null || !nextRoutes.any((r) => r.id == routeId)) {
        routeId = nextRoutes.first.id;
      }
      final next = await api.getArrivals(routeId);
      if (!mounted) {
        return;
      }
      _hasData = true;
      setState(() {
        _routes = nextRoutes;
        _selectedRouteId = routeId;
        _response = next;
        _stale = false;
        _phase = _Phase.ready;
      });
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      if (error.code == ApiException.settingNotFound) {
        setState(() => _phase = _Phase.needOnboarding);
        return;
      }
      _markStale();
    } catch (_) {
      if (!mounted) {
        return;
      }
      _markStale();
    }
  }

  /// 네트워크/서버 장애 — 마지막 정보를 유지하고 stale 표시 (NFR-07).
  /// 보여줄 정보가 아직 없으면(첫 로딩 실패) 무한 로딩 대신 실패 화면으로 전환한다.
  void _markStale() {
    setState(() {
      _stale = true;
      if (_phase != _Phase.ready) {
        _phase = _hasData ? _Phase.ready : _Phase.loadFailed;
      }
    });
  }

  /// 세션 시작·피드백 제출 직후에만 조회 — 20초 폴링에는 싣지 않는다
  /// (부가 기능이 본편을 무겁게 하면 안 됨)
  Future<void> _checkBufferSuggestion() async {
    try {
      final recommendation = await api.getBufferRecommendation();
      final handledAt = await _suggestionStore.readHandledAt();
      if (!mounted) {
        return;
      }
      final show = shouldShowBufferSuggestion(
        recommendation,
        handledAt,
        DateTime.now(),
      );
      setState(() => _bufferSuggestion = show ? recommendation : null);
    } catch (_) {
      // 추천 조회 실패는 조용히 무시 — 라이브 뷰 본편 흐름을 막지 않는다
    }
  }

  Future<void> _handleFeedback(BoardingResult result) async {
    final today = DateTime.now();
    String pad(int n) => n.toString().padLeft(2, '0');
    // 푸시가 알려준 날짜가 있으면 그 날짜로 기록한다 (자정 넘김 등 엣지 대비)
    final notifiedDate = _pushNotifiedDate ??
        '${today.year}-${pad(today.month)}-${pad(today.day)}';
    try {
      await api.postBoardingFeedback(
        BoardingFeedbackRequest(result: result, notifiedDate: notifiedDate),
      );
      if (!mounted) {
        return;
      }
      setState(() => _todayFeedback = result);
      // 방금 놓침이 기록됐으면 추천이 켜졌을 수 있다 — 바로 다시 판정
      unawaited(_checkBufferSuggestion());
      if (result == BoardingResult.boarded) {
        // 탑승 = 하차 알림을 시작할 최적 타이밍 (열차 특정 후보 스냅샷, §9-2) —
        // 오늘 맞는 여정이 있으면 바로 이어준다 (2026-09-15 실주행 피드백)
        unawaited(_maybeOfferTripStart());
      }
    } catch (_) {
      // 전송 실패 — 완료 상태로 표시하지 않아 버튼이 남고, 다시 누르면 재시도된다
    }
  }

  /// "탔어요" → 하차 알림 브리지 — 오늘 요일에 맞는 여정을 골라 시작을 제안한다.
  /// 여정이 없거나 §9 미배포(404)·네트워크 실패면 조용히 생략 — 피드백 본편을 막지 않는다
  Future<void> _maybeOfferTripStart() async {
    List<Journey> journeys;
    try {
      journeys = await api.listJourneys();
    } catch (_) {
      return;
    }
    final journey = pickBoardingJourney(journeys, DateTime.now());
    if (journey == null || !mounted) {
      return;
    }
    final start = await showAppSheet<bool>(
      context: context,
      header: '하차 알림도 시작할까요?',
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpace.xl,
          0,
          AppSpace.xl,
          AppSpace.lg,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${journey.label} · ${journeyPathSummary(journey.legs)}\n'
              '내릴 역이 가까워지면 알려드려요',
              style: AppTypo.bodySm.copyWith(
                color: sheetContext.colors.inkMuted,
              ),
            ),
            const SizedBox(height: AppSpace.md),
            Row(
              children: [
                Expanded(
                  child: AppButton(
                    label: '시작',
                    medium: true,
                    block: true,
                    onPressed: () => Navigator.of(sheetContext).pop(true),
                  ),
                ),
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: AppButton(
                    label: '괜찮아요',
                    variant: AppButtonVariant.tonal,
                    medium: true,
                    block: true,
                    onPressed: () => Navigator.of(sheetContext).pop(false),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (start != true || !mounted) {
      return;
    }
    await _startJourneyTrip(journey);
  }

  Future<void> _startJourneyTrip(Journey journey) async {
    // 햅틱: 트립 시작 = 주요 확정 액션 (CLAUDE.md 적응형 UI 규칙)
    HapticFeedback.mediumImpact();
    try {
      final start = await api.startTrip(journey.id);
      unawaited(_tripStore.write(start.tripId, journeyId: journey.id));
      if (!mounted) {
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => TripPage(
            tripId: start.tripId,
            journeyLabel: journey.label,
            journeyId: journey.id,
          ),
        ),
      );
    } on ApiException {
      // 이미 진행 중 트립이 있음(§9-2 동시 1개) — 보관된 트립 이어보기로 유도
      final tripId = await _tripStore.read();
      final journeyId = await _tripStore.readJourneyId();
      if (!mounted || tripId == null) {
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => TripPage(tripId: tripId, journeyId: journeyId),
        ),
      );
    } catch (_) {
      // 네트워크 실패 — 조용히 생략, 하차 알림 탭에서 다시 시작할 수 있다
    }
  }

  CommuteRoute? get _selectedRoute {
    for (final route in _routes) {
      if (route.id == _selectedRouteId) {
        return route;
      }
    }
    return _routes.isEmpty ? null : _routes.first;
  }

  /// 추천 적용 — 선택된 경로의 버퍼를 +5분으로 수정(§1-2c).
  /// 실패하면 카드가 남아 다시 누르면 재시도된다
  Future<void> _applySuggestion() async {
    final suggestion = _bufferSuggestion;
    final route = _selectedRoute;
    if (suggestion == null || route == null) {
      return;
    }
    final newBuffer =
        route.setting.bufferMinutes + suggestion.suggestedIncrementMinutes;
    try {
      await api.updateCommuteRoute(
        route.id,
        CommuteRouteRequest(
          label: route.label,
          enabled: route.enabled,
          setting: route.setting.copyWith(bufferMinutes: newBuffer),
        ),
      );
      unawaited(_suggestionStore.writeHandledAt(DateTime.now()));
      if (!mounted) {
        return;
      }
      setState(() {
        _bufferSuggestion = null;
        _appliedBufferMinutes = newBuffer;
      });
      unawaited(_refresh());
    } catch (_) {
      // 저장 실패 — 카드 유지(재시도 가능). 별도 안내는 두지 않는다
    }
  }

  void _dismissSuggestion() {
    unawaited(_suggestionStore.writeHandledAt(DateTime.now()));
    setState(() => _bufferSuggestion = null);
  }

  Future<void> _openOnboarding(String? routeId) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => OnboardingPage(routeId: routeId),
      ),
    );
    // 온보딩·재설정에서 돌아오면 즉시 갱신 (미니앱 focus 리스너와 동일 역할)
    unawaited(_refresh());
  }

  void _selectRoute(CommuteRoute route) {
    if (route.id == _selectedRouteId) {
      // 이미 선택된 칩 재탭 = 이름 수정
      unawaited(_openRenameSheet(route));
      return;
    }
    setState(() => _selectedRouteId = route.id);
    unawaited(_refresh());
  }

  Future<void> _openRenameSheet(CommuteRoute target) {
    return showRouteRenameSheet(
      context: context,
      initialLabel: target.label,
      otherLabels: _routes
          .where((r) => r.id != target.id)
          .map((r) => r.label)
          .toList(),
      onSave: (label) async {
        try {
          await api.updateCommuteRoute(
            target.id,
            CommuteRouteRequest(
              label: label,
              enabled: target.enabled,
              setting: target.setting,
            ),
          );
        } on ApiException catch (error) {
          // 이미 삭제된 경로 — refresh가 목록을 정리하게 두고 시트는 닫는다
          if (error.code == ApiException.settingNotFound) {
            unawaited(_refresh());
            return true;
          }
          return false;
        } catch (_) {
          return false;
        }
        unawaited(_refresh());
        return true;
      },
    );
  }

  /// 헤더 "삭제"의 대상 = 지금 보고 있는 경로
  Future<void> _requestDeleteRoute() async {
    final target = _selectedRoute;
    if (target == null) {
      return;
    }
    final deleted = await showRouteDeleteSheet(
      context: context,
      routeLabel: target.label,
      isLastRoute: _routes.length <= 1,
      onConfirm: () async {
        try {
          await api.deleteCommuteRoute(target.id);
        } on ApiException catch (error) {
          // 이미 없는 경로는 목적 달성 — 성공과 동일하게 처리
          if (error.code != ApiException.settingNotFound) {
            return false;
          }
        } catch (_) {
          return false;
        }
        return true;
      },
    );
    if (deleted) {
      // 삭제된 경로가 선택돼 있던 상태 — refresh가 첫 경로로 넘기고,
      // 마지막 경로였으면 재온보딩 화면이 된다
      unawaited(_refresh());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      body: SafeArea(child: _body()),
    );
  }

  Widget _body() {
    final response = _response;

    if (_phase == _Phase.needOnboarding) {
      return _CenterMessage(
        title: '놓치지 않는 출근길,\n통근 설정부터 시작해요',
        titleLarge: true,
        subtitle: '출발지·정류장·도보 시간만 알려주시면\n언제 나가야 하는지 알려드려요',
        buttonLabel: '설정 시작하기',
        onPressed: () => unawaited(_openOnboarding(null)),
      );
    }

    if (_phase == _Phase.loadFailed && response == null) {
      return _CenterMessage(
        title: '도착 정보를 불러오지 못했어요',
        subtitle: '네트워크를 확인하고 다시 시도해주세요',
        buttonLabel: '다시 시도',
        onPressed: () => unawaited(_refresh()),
      );
    }

    if (_phase == _Phase.loading || response == null) {
      return Center(
        child: Text(
          '도착 정보를 불러오고 있어요…',
          style: AppTypo.bodySm.copyWith(color: context.colors.inkSubtle),
        ),
      );
    }

    final selectedRoute = _selectedRoute;
    return Column(
      children: [
        if (_routes.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(
              left: AppSpace.xl,
              right: AppSpace.xl,
              top: AppSpace.md,
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final route in _routes)
                    AppChip(
                      label: route.label,
                      selected: route.id == _selectedRouteId,
                      onPressed: () => _selectRoute(route),
                    ),
                  if (_routes.length < maxCommuteRoutes)
                    AppChip(
                      label: '+ 추가',
                      selected: false,
                      onPressed: () => unawaited(_openOnboarding('new')),
                    ),
                ],
              ),
            ),
          ),
        Expanded(
          child: LiveViewScreen(
            response: response,
            stale: _stale,
            todayFeedback: _todayFeedback,
            onSubmitFeedback: (result) {
              // 햅틱: 주요 확정 액션 (CLAUDE.md 적응형 UI 규칙)
              HapticFeedback.mediumImpact();
              unawaited(_handleFeedback(result));
            },
            bufferSuggestion: _bufferSuggestion,
            appliedBufferMinutes: _appliedBufferMinutes,
            onApplyBufferSuggestion: () => unawaited(_applySuggestion()),
            onDismissBufferSuggestion: _dismissSuggestion,
            onPressSettings: () =>
                unawaited(_openOnboarding(_selectedRouteId)),
            onPressDeleteRoute: selectedRoute == null
                ? null
                : () => unawaited(_requestDeleteRoute()),
          ),
        ),
      ],
    );
  }
}

class _CenterMessage extends StatelessWidget {
  const _CenterMessage({
    required this.title,
    required this.subtitle,
    required this.buttonLabel,
    required this.onPressed,
    this.titleLarge = false,
  });

  final String title;
  final String subtitle;
  final String buttonLabel;
  final VoidCallback onPressed;
  final bool titleLarge;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: titleLarge ? AppTypo.title : AppTypo.heading,
            ),
            const SizedBox(height: AppSpace.lg),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: AppTypo.bodySm.copyWith(color: context.colors.inkMuted),
            ),
            const SizedBox(height: AppSpace.lg),
            AppButton(label: buttonLabel, onPressed: onPressed),
          ],
        ),
      ),
    );
  }
}
