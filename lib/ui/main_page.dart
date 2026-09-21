import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/api.dart';
import '../data/trip_store.dart';
import '../domain/commute_report.dart';
import '../domain/journey.dart';
import '../domain/live_view.dart';
import '../domain/models.dart';
import 'components/ad_banner.dart';
import 'components/route_strip.dart';
import 'components/commute_grass.dart';
import 'components/fade_route.dart';
import 'components/tab_header.dart';
import 'design/components/button.dart';
import 'design/components/card.dart';
import 'design/components/sheet.dart';
import 'design/tokens.dart';
import 'journey_create_page.dart';
import 'trip_page.dart';

/// 메인 탭 — 앱의 두 기능(출발 알림·하차 알림)으로 바로 가는 진입점 허브
/// (오너 결정 2026-09-16: 메인은 전체 기능의 진입점들을 보여주는 곳).
///
/// 섹션마다 요약 카드 하나 — 출발 알림은 다음 도착 요약, 하차 알림은 진행 중
/// 트립이 있으면 트립 요약, 없으면 오늘 여정 원탭 시작. 카드는 통째로 탭 가능해서
/// 어디를 눌러도 해당 기능 탭으로 넘어간다 (오너 요구: 메인 → 기능 전환이 아주 쉬워야 한다).
/// 통근 기록(잔디)은 진입점이 아니라 콘텐츠 — 뎁스 없이 섹션 전체를 그대로 노출한다
/// (오너 결정 2026-09-19: 내정보 리포트 화면을 없애고 메인으로 이동).
/// 폴링은 각 기능 탭의 몫 — 여기는 탭이 활성화될 때·당겨서 새로고침만 한다.
class MainPage extends StatefulWidget {
  const MainPage({
    super.key,
    required this.active,
    required this.onOpenCatch,
    required this.onOpenJourney,
  });

  /// 이 탭이 현재 보이는지 — 보이게 되는 순간 요약을 새로 불러온다
  final bool active;

  /// 출발 알림 탭(라이브 뷰)으로 전환
  final VoidCallback onOpenCatch;

  /// 하차 알림 탭(여정 목록)으로 전환
  final VoidCallback onOpenJourney;

  @override
  State<MainPage> createState() => _MainPageState();
}

enum _SummaryPhase { loading, empty, ready, failed }

/// §3-2·§9 기반 섹션(여정·통근 기록)의 로드 상태 — 미배포 서버(404)는 "준비 중"으로 강등
enum _SectionPhase { loading, unavailable, failed, ready }

class _MainPageState extends State<MainPage> {
  final TripStore _tripStore = TripStore();
  _SummaryPhase _phase = _SummaryPhase.loading;
  CommuteRoute? _route;
  ArrivalsResponse? _response;
  bool _stale = false;

  _SectionPhase _journeyPhase = _SectionPhase.loading;
  List<Journey> _journeys = [];

  /// 통근 기록(잔디) 섹션 — 내정보에서 메인으로 이동, 뎁스 없이 전체 노출 (오너 결정 2026-09-19)
  _SectionPhase _reportPhase = _SectionPhase.loading;
  List<FeedbackEntry> _feedback = [];

  /// 진행 중 트립(하차 알림) 요약 — 로컬 보관 tripId를 서버 상태로 확인
  String? _tripId;
  TripStatus? _trip;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(MainPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 다른 탭에 있다 돌아왔을 때 — 요약이 낡아 있지 않게 조용히 갱신
    if (widget.active && !oldWidget.active) {
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    unawaited(_checkTrip());
    unawaited(_loadJourneys());
    unawaited(_loadFeedback());
    try {
      final routes = await api.listCommuteRoutes();
      if (!mounted) {
        return;
      }
      if (routes.isEmpty) {
        setState(() => _phase = _SummaryPhase.empty);
        return;
      }
      final route = routes.first;
      final response = await api.getArrivals(route.id);
      if (!mounted) {
        return;
      }
      setState(() {
        _route = route;
        _response = response;
        _stale = false;
        _phase = _SummaryPhase.ready;
      });
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      if (error.code == ApiException.settingNotFound) {
        setState(() => _phase = _SummaryPhase.empty);
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

  /// 실패 시 마지막 정보를 유지하고 갱신 지연만 표시한다 (NFR-07과 동일한 태도)
  void _markStale() {
    setState(() {
      if (_response != null) {
        _stale = true;
      } else {
        _phase = _SummaryPhase.failed;
      }
    });
  }

  Future<void> _loadJourneys() async {
    try {
      final journeys = await api.listJourneys();
      if (!mounted) {
        return;
      }
      setState(() {
        _journeys = journeys;
        _journeyPhase = _SectionPhase.ready;
      });
      if (_trip != null && _tripLegs == null) {
        final legs = await _resolveTripLegs();
        if (mounted && legs != null) {
          setState(() => _tripLegs = legs);
        }
      }
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      // §9 미배포 서버는 404(NOT_FOUND) — 하차 알림 탭과 같은 "준비 중" 강등
      setState(
        () => _journeyPhase = error.status == 404
            ? _SectionPhase.unavailable
            : _SectionPhase.failed,
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _journeyPhase = _SectionPhase.failed);
    }
  }

  Future<void> _loadFeedback() async {
    try {
      final feedback = await api.getFeedbackHistory();
      if (!mounted) {
        return;
      }
      setState(() {
        _feedback = feedback;
        _reportPhase = _SectionPhase.ready;
      });
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      // §3-2 미배포 서버는 404 — "준비 중"으로 강등 (여정 섹션과 같은 태도)
      setState(
        () => _reportPhase = error.status == 404
            ? _SectionPhase.unavailable
            : _SectionPhase.failed,
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _reportPhase = _SectionPhase.failed);
    }
  }

  void _openCatch() {
    HapticFeedback.selectionClick();
    widget.onOpenCatch();
  }

  void _openJourneyTab() {
    HapticFeedback.selectionClick();
    widget.onOpenJourney();
  }

  /// 진행 중 트립의 구간 — 카드 구간 스트립용. 1회성은 로컬 스냅숏, 저장 여정은 목록에서 찾는다
  List<JourneyLeg>? _tripLegs;

  /// 저장 여정 트립은 목록(_journeys)이 늦게 오면 못 찾는다 — 트립 확인·여정 로드 양쪽 끝에서 다시 푼다
  Future<List<JourneyLeg>?> _resolveTripLegs() async {
    final journeyId = await _tripStore.readJourneyId();
    if (journeyId == null) {
      return _tripStore.readLegs();
    }
    return _journeys.where((j) => j.id == journeyId).firstOrNull?.legs;
  }

  Future<void> _checkTrip() async {
    final tripId = await _tripStore.read();
    if (tripId == null) {
      if (mounted) {
        setState(() {
          _tripId = null;
          _trip = null;
          _tripLegs = null;
        });
      }
      return;
    }
    try {
      final status = await api.getTrip(tripId);
      final legs = await _resolveTripLegs();
      if (!mounted) {
        return;
      }
      setState(() {
        _tripId = tripId;
        _trip = status;
        _tripLegs = legs;
      });
    } on ApiException catch (error) {
      if (error.status == 404) {
        // 서버에서 정리된 트립 — 로컬 보관도 정리
        unawaited(_tripStore.clear());
        if (mounted) {
          setState(() {
            _tripId = null;
            _trip = null;
          });
        }
      }
    } catch (_) {
      // 네트워크 실패 — 카드만 생략
    }
  }

  Future<void> _openTrip(String tripId) async {
    HapticFeedback.selectionClick();
    // 보관된 여정 id(또는 1회성 구간 스냅숏)가 있으면 같이 넘긴다 — LOST 화면
    // "처음부터 다시 추적"·완료 후 저장 제안 진입점
    final journeyId = await _tripStore.readJourneyId();
    final legs = await _tripStore.readLegs();
    if (!mounted) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            TripPage(tripId: tripId, journeyId: journeyId, legs: legs),
      ),
    );
    unawaited(_load());
  }

  Future<void> _openCreate() async {
    // 여정 만들기 진입은 페이드 전환 (오너 결정 2026-09-16, 하차 알림 탭과 동일)
    final created = await Navigator.of(
      context,
    ).push<bool>(fadeRoute(const JourneyCreatePage()));
    if (created == true) {
      unawaited(_load());
    }
  }

  /// 메인에서 여정 원탭 시작 — 하차 알림 탭의 시작과 같은 플로우 (탑승 직후 앱을 열면
  /// 메인이 첫 화면이라, 여기서 바로 시작할 수 있어야 한다)
  Future<void> _startJourney(Journey journey) async {
    // 햅틱: 트립 시작 = 주요 확정 액션 (CLAUDE.md 적응형 UI 규칙)
    HapticFeedback.mediumImpact();
    try {
      final start = await api.startTrip(journey.id);
      // 이어보기·요약 카드용 로컬 보관 (서버에 활성 트립 조회가 없다 — §9)
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
      unawaited(_load());
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      _showMessage('시작할 수 없어요', error.message);
    } catch (_) {
      if (!mounted) {
        return;
      }
      _showMessage('시작할 수 없어요', '네트워크를 확인하고 다시 시도해주세요');
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

  @override
  Widget build(BuildContext context) {
    // 콘텐츠가 글라스 헤더·네비 뒤로 흐른다 — 상하 여백은 ListView padding이 담당
    final headerBottom =
        MediaQuery.paddingOf(context).top + TabHeader.contentHeight;
    return Scaffold(
      backgroundColor: context.colors.background,
      extendBodyBehindAppBar: true,
      appBar: const TabHeader(title: '메인'),
      body: RefreshIndicator.adaptive(
        edgeOffset: headerBottom,
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.only(
            top: headerBottom + AppSpace.md,
            bottom: MediaQuery.paddingOf(context).bottom + AppSpace.lg,
          ),
          children: [
            _sectionHeader('출발 알림', _openCatch),
            GestureDetector(onTap: _openCatch, child: _summaryCard()),
            _sectionHeader('하차 알림', _openJourneyTab),
            if (_trip != null && _tripId != null)
              GestureDetector(
                onTap: () => unawaited(_openTrip(_tripId!)),
                // 다른 섹션의 데이터 카드와 같은 기본 톤 — 진행 중이라고 카드 전체를 브랜드색으로
                // 칠하지 않는다 (오너 피드백 2026-09-21: 하차 알림만 색이 달라 보였다)
                child: AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '하차 알림 진행 중',
                                  style: AppTypo.caption.copyWith(
                                    color: context.colors.primaryStrong,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: AppSpace.xs),
                                Text(_tripSummary(_trip!), style: AppTypo.heading),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.chevron_right,
                            size: 20,
                            color: context.colors.inkSubtle,
                          ),
                        ],
                      ),
                      // 트립 화면과 같은 구간 스트립 애니메이션 (오너 요청 2026-09-21) —
                      // 이동 중 구간(추적·도착 직전)에만, 구간을 알 때만
                      if (_tripStripLeg() case final leg?) ...[
                        const SizedBox(height: AppSpace.lg),
                        RouteStrip(
                          boardStop: leg.boardStop,
                          eventStop: leg.alightStop,
                          line: leg.line,
                        ),
                      ],
                    ],
                  ),
                ),
              )
            else
              _journeyEntryCard(),
            // 광고는 스크롤 콘텐츠 사이(하차 알림·통근 기록 섹션 사이)에 깔린다 —
            // 화면에 고정해 따라다니지 않는다 (오너 결정 2026-09-19)
            const AdBanner(),
            _sectionHeader('통근 기록'),
            _grassCard(),
          ],
        ),
      ),
    );
  }

  /// 섹션 헤더 — 헤더 영역 타이틀(AppTypo.title)과 같은 폰트로 시선을 잡는다
  /// (오너 피드백 2026-09-19: 캡션은 눈에 안 들어온다). [onOpen]이 있으면 오른쪽에
  /// 해당 탭 전체 보기, 없으면 제목만 (통근 기록처럼 뎁스 없이 전체를 노출하는 섹션)
  Widget _sectionHeader(String title, [VoidCallback? onOpen]) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.xl,
        AppSpace.md,
        AppSpace.xl,
        AppSpace.sm,
      ),
      child: Row(
        children: [
          Expanded(child: Text(title, style: AppTypo.title)),
          if (onOpen != null)
            GestureDetector(
              onTap: onOpen,
              behavior: HitTestBehavior.opaque,
              child: Row(
                children: [
                  Text(
                    '전체 보기',
                    style: AppTypo.caption.copyWith(
                      color: context.colors.inkMuted,
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    size: 14,
                    color: context.colors.inkMuted,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _tripSummary(TripStatus status) => switch (status.phase) {
    TripPhase.transfer => '${status.eventStop} 환승 대기 중',
    TripPhase.lost => '추적이 끊겼어요',
    TripPhase.done => '목적지 도착',
    _ =>
      status.remainingStops == null
          ? '${status.eventStop}행 위치 확인 중'
          : '${status.eventStop}까지 ${status.remainingStops}정거장',
  };

  Widget _summaryCard() {
    switch (_phase) {
      case _SummaryPhase.loading:
        return AppCard(
          child: Text(
            '도착 정보를 불러오고 있어요…',
            style: AppTypo.bodySm.copyWith(color: context.colors.inkSubtle),
          ),
        );
      case _SummaryPhase.failed:
        return AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('요약을 불러오지 못했어요', style: AppTypo.heading),
              const SizedBox(height: AppSpace.xs),
              Text(
                '네트워크를 확인하고 다시 시도해주세요',
                style: AppTypo.caption.copyWith(color: context.colors.inkMuted),
              ),
              const SizedBox(height: AppSpace.md),
              AppButton(
                label: '다시 시도',
                variant: AppButtonVariant.tonal,
                medium: true,
                onPressed: () => unawaited(_load()),
              ),
            ],
          ),
        );
      case _SummaryPhase.empty:
        return AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('아직 통근 설정이 없어요', style: AppTypo.heading),
              const SizedBox(height: AppSpace.xs),
              Text(
                '경로를 등록하면 다음 도착과 출발 타이밍을\n여기서 바로 볼 수 있어요',
                style: AppTypo.caption.copyWith(color: context.colors.inkMuted),
              ),
              const SizedBox(height: AppSpace.md),
              AppButton(label: '설정 시작하기', medium: true, onPressed: _openCatch),
            ],
          ),
        );
      case _SummaryPhase.ready:
        return _readyCard();
    }
  }

  Widget _readyCard() {
    final route = _route!;
    final response = _response!;
    final best = pickBestBoardable(response.arrivals);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _labelPill(route.label),
              const Spacer(),
              Icon(
                Icons.chevron_right,
                size: 20,
                color: context.colors.inkSubtle,
              ),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          if (best == null) ...[
            const Text('지금 탈 수 있는 차가 없어요', style: AppTypo.heading),
            const SizedBox(height: AppSpace.xs),
            Text(
              '눌러서 전체 도착 정보를 확인하세요',
              style: AppTypo.caption.copyWith(color: context.colors.inkSubtle),
            ),
          ] else ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Text(
                    best.routeName,
                    style: AppTypo.heading,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: AppSpace.md),
                Text(
                  formatRemaining(best.secondsToArrival),
                  style: AppTypo.title.copyWith(
                    color: context.colors.primaryStrong,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpace.xs),
            Text(
              '${best.stopDisplayName} · ${statusLabel(best.status)}',
              style: AppTypo.caption.copyWith(color: context.colors.inkMuted),
            ),
          ],
          const SizedBox(height: AppSpace.md),
          Text(
            _stale
                ? '갱신이 늦어져 마지막 정보를 보여드리고 있어요'
                : '도보 ${response.walkMinutes}분 · ${formatFetchedAt(response.fetchedAt)} 기준',
            style: AppTypo.caption.copyWith(
              color: _stale
                  ? context.colors.cautionStrong
                  : context.colors.inkFaint,
            ),
          ),
        ],
      ),
    );
  }

  /// 진행 중 트립 카드에 스트립을 그릴 구간 — 추적·도착 직전 상태에서 현재 구간, 그 외 null
  JourneyLeg? _tripStripLeg() {
    final trip = _trip;
    final legs = _tripLegs;
    if (trip == null || legs == null) {
      return null;
    }
    if (trip.phase != TripPhase.tracking && trip.phase != TripPhase.arriving) {
      return null;
    }
    if (trip.legIndex < 0 || trip.legIndex >= legs.length) {
      return null;
    }
    return legs[trip.legIndex];
  }

  // 메인의 카드는 전부 기본 톤 — 빈 상태(여정·경로·기록 없음)도 브랜드색으로 칠하지 않는다
  // (오너 피드백 2026-09-21: 하차 알림 영역만 그린 배경으로 보였다)

  /// 하차 알림 섹션 카드 — 진행 중 트립이 없을 때의 진입점
  Widget _journeyEntryCard() {
    switch (_journeyPhase) {
      case _SectionPhase.loading:
        return AppCard(
          child: Text(
            '여정을 불러오고 있어요…',
            style: AppTypo.bodySm.copyWith(color: context.colors.inkSubtle),
          ),
        );
      case _SectionPhase.unavailable:
        return AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('하차 알림을 준비하고 있어요', style: AppTypo.heading),
              const SizedBox(height: AppSpace.xs),
              Text(
                '서버 업데이트 후 이용할 수 있어요. 조금만 기다려주세요',
                style: AppTypo.caption.copyWith(color: context.colors.inkMuted),
              ),
            ],
          ),
        );
      case _SectionPhase.failed:
        return AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('여정을 불러오지 못했어요', style: AppTypo.heading),
              const SizedBox(height: AppSpace.xs),
              Text(
                '네트워크를 확인하고 다시 시도해주세요',
                style: AppTypo.caption.copyWith(color: context.colors.inkMuted),
              ),
              const SizedBox(height: AppSpace.md),
              AppButton(
                label: '다시 시도',
                variant: AppButtonVariant.tonal,
                medium: true,
                onPressed: () => unawaited(_loadJourneys()),
              ),
            ],
          ),
        );
      case _SectionPhase.ready:
        if (_journeys.isEmpty) {
          return AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('아직 여정이 없어요', style: AppTypo.heading),
                const SizedBox(height: AppSpace.xs),
                Text(
                  '출발지부터 목적지까지 넣어두면\n내릴 타이밍을 알려드려요',
                  style: AppTypo.caption.copyWith(
                    color: context.colors.inkMuted,
                  ),
                ),
                const SizedBox(height: AppSpace.md),
                AppButton(
                  label: '여정 만들기',
                  medium: true,
                  onPressed: () => unawaited(_openCreate()),
                ),
              ],
            ),
          );
        }
        return _journeyQuickCard();
    }
  }

  /// 오늘 여정 원탭 시작 카드 — 오늘 요일 반복 여정 우선(pickBoardingJourney),
  /// 없으면 목록 첫 여정(lastUsedAt 내림차순, §9-1)
  Widget _journeyQuickCard() {
    final journey =
        pickBoardingJourney(_journeys, DateTime.now()) ?? _journeys.first;
    return GestureDetector(
      onTap: _openJourneyTab,
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _labelPill(journey.label),
                const Spacer(),
                Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: context.colors.inkSubtle,
                ),
              ],
            ),
            const SizedBox(height: AppSpace.md),
            Text(
              journeyPathSummary(journey.legs),
              style: AppTypo.heading,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: AppSpace.xs),
            Text(
              '탑승하면 시작을 눌러주세요. 내릴 역을 알려드려요',
              style: AppTypo.caption.copyWith(color: context.colors.inkMuted),
            ),
            const SizedBox(height: AppSpace.md),
            AppButton(
              label: '시작',
              medium: true,
              block: true,
              onPressed: () => unawaited(_startJourney(journey)),
            ),
          ],
        ),
      ),
    );
  }

  /// 통근 기록 섹션 — 잔디 그리드를 뎁스 없이 통째로 노출한다 (별도 리포트 화면 없음).
  /// 성공 중심 톤(§9): 요약도 탑승·연속 성공만 말하고 놓침을 세어 보여주지 않는다
  Widget _grassCard() {
    switch (_reportPhase) {
      case _SectionPhase.loading:
        return AppCard(
          child: Text(
            '기록을 불러오고 있어요…',
            style: AppTypo.bodySm.copyWith(color: context.colors.inkSubtle),
          ),
        );
      case _SectionPhase.unavailable:
        return AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('통근 기록을 준비하고 있어요', style: AppTypo.heading),
              const SizedBox(height: AppSpace.xs),
              Text(
                '서버 업데이트 후 이용할 수 있어요. 조금만 기다려주세요',
                style: AppTypo.caption.copyWith(color: context.colors.inkMuted),
              ),
            ],
          ),
        );
      case _SectionPhase.failed:
        return AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('기록을 불러오지 못했어요', style: AppTypo.heading),
              const SizedBox(height: AppSpace.xs),
              Text(
                '네트워크를 확인하고 다시 시도해주세요',
                style: AppTypo.caption.copyWith(color: context.colors.inkMuted),
              ),
              const SizedBox(height: AppSpace.md),
              AppButton(
                label: '다시 시도',
                variant: AppButtonVariant.tonal,
                medium: true,
                onPressed: () => unawaited(_loadFeedback()),
              ),
            ],
          ),
        );
      case _SectionPhase.ready:
        if (_feedback.isEmpty) {
          return AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('아직 통근 기록이 없어요', style: AppTypo.heading),
                const SizedBox(height: AppSpace.xs),
                Text(
                  '아침에 "탔어요/놓쳤어요"를 누르면\n여기에 잔디처럼 기록이 쌓여요',
                  style: AppTypo.caption.copyWith(
                    color: context.colors.inkMuted,
                  ),
                ),
              ],
            ),
          );
        }
        final now = DateTime.now();
        final report = buildCommuteReport(_feedback, now);
        return AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '이번 주 ${report.weekBoarded}/${report.weekTotal}회 탑승 · '
                '연속 ${report.currentStreak}회 성공',
                style: AppTypo.bodySm.copyWith(
                  color: context.colors.inkMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AppSpace.md),
              CommuteGrass(entries: _feedback, today: now),
            ],
          ),
        );
    }
  }

  /// 경로·여정 라벨 알약 — 두 섹션 카드가 같은 시각 언어를 쓴다
  Widget _labelPill(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: 2),
      decoration: BoxDecoration(
        color: context.colors.primarySoft,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        label,
        style: AppTypo.caption.copyWith(
          color: context.colors.primaryStrong,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
