import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/active_trip.dart';
import '../data/api.dart';
import '../data/recent_routes_store.dart';
import '../domain/journey.dart';
import '../domain/models.dart';
import 'components/active_trip_card.dart';
import 'components/ad_banner.dart';
import 'components/center_message.dart';
import 'components/fade_route.dart';
import 'components/save_journey_sheet.dart';
import 'components/tab_header.dart';
import 'design/components/button.dart';
import 'design/components/card.dart';
import 'design/components/sheet.dart';
import 'design/tokens.dart';
import 'journey_create_page.dart';
import 'trip_page.dart';

const List<({DayOfWeek day, String label})> journeyDayLabels = [
  (day: DayOfWeek.mon, label: '월'),
  (day: DayOfWeek.tue, label: '화'),
  (day: DayOfWeek.wed, label: '수'),
  (day: DayOfWeek.thu, label: '목'),
  (day: DayOfWeek.fri, label: '금'),
  (day: DayOfWeek.sat, label: '토'),
  (day: DayOfWeek.sun, label: '일'),
];

String _repeatDaysLabel(List<DayOfWeek> days) => [
  for (final entry in journeyDayLabels)
    if (days.contains(entry.day)) entry.label,
].join('·');

enum _JourneyPhase { loading, unavailable, failed, ready }

/// 하차 알림 탭 — 여정 목록·시작 (FR-701~703). 서버 §9 미배포면 "준비 중"으로 강등.
class JourneyPage extends StatefulWidget {
  const JourneyPage({super.key, required this.active});

  /// 이 탭이 현재 보이는지 — 보이게 되는 순간 목록을 새로 불러온다
  final bool active;

  @override
  State<JourneyPage> createState() => _JourneyPageState();
}

class _JourneyPageState extends State<JourneyPage> {
  final RecentRoutesStore _recentStore = RecentRoutesStore();
  _JourneyPhase _phase = _JourneyPhase.loading;
  List<Journey> _journeys = [];

  /// 저장하지 않은 최근 간 길(1회성, FR-708) — 로컬 보관, 원탭 재시작·저장 진입점
  List<RecentRoute> _recent = const [];

  /// 진행 중 트립은 전역 `activeTrip`이 들고 있다 — 메인 탭과 같은 값·같은 카드를 쓴다
  /// (오너 요청 2026-09-22)

  /// 구독 중인 전역 트립 컨트롤러 — 구독과 해제가 같은 인스턴스를 향하게 붙잡아 둔다
  late final ActiveTripController _trip;

  @override
  void initState() {
    super.initState();
    _trip = activeTrip;
    _trip.addListener(_onTripChanged);
    unawaited(_load());
  }

  @override
  void dispose() {
    _trip.removeListener(_onTripChanged);
    super.dispose();
  }

  void _onTripChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void didUpdateWidget(JourneyPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    unawaited(activeTrip.restore());
    unawaited(_loadRecent());
    try {
      final journeys = await api.listJourneys();
      if (!mounted) {
        return;
      }
      setState(() {
        _journeys = journeys;
        _phase = _JourneyPhase.ready;
      });
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      // §9 미배포 서버는 404(NOT_FOUND) — 기능을 "준비 중"으로 강등 (API.md §9)
      setState(
        () => _phase = error.status == 404
            ? _JourneyPhase.unavailable
            : _JourneyPhase.failed,
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _phase = _JourneyPhase.failed);
    }
  }

  Future<void> _loadRecent() async {
    final recent = await _recentStore.list();
    if (mounted) {
      setState(() => _recent = recent);
    }
  }

  Future<void> _openTrip(String tripId) async {
    // 여정 id·1회성 구간 스냅숏은 컨트롤러가 들고 있다 — LOST 화면 "처음부터 다시 추적"·
    // 완료 후 저장 제안 진입점
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TripPage(
          tripId: tripId,
          journeyLabel: activeTrip.label,
          journeyId: activeTrip.journeyId,
          legs: activeTrip.isOneOff ? activeTrip.legs : null,
        ),
      ),
    );
    unawaited(_load());
  }

  /// 여정 저장만 — 이름·구간·요일 (FR-701/702)
  Future<void> _openCreate() async {
    // 여정 입력 진입은 페이드 전환 (오너 결정 2026-09-16)
    final created = await Navigator.of(
      context,
    ).push<Object?>(fadeRoute(const JourneyCreatePage()));
    if (created == true) {
      unawaited(_load());
    }
  }

  /// 바로 시작 (FR-708) — 구간만 넣고 추적, 저장은 화면 안 스위치로 선택.
  /// 시작되면 트립 화면으로 (저장 스위치를 켰으면 여정 트립, 아니면 1회성 트립)
  Future<void> _openStart() async {
    final result = await Navigator.of(context).push<Object?>(
      fadeRoute(const JourneyCreatePage(mode: JourneyCreateMode.start)),
    );
    if (result is! JourneyTripStarted || !mounted) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TripPage(
          tripId: result.tripId,
          journeyLabel: result.journeyLabel ?? journeyPathSummary(result.legs),
          journeyId: result.journeyId,
          legs: result.journeyId == null ? result.legs : null,
        ),
      ),
    );
    unawaited(_load());
  }

  /// 최근 간 길 원탭 재시작 — 1회성 트립 그대로 (FR-708)
  Future<void> _restartRecent(RecentRoute route) async {
    HapticFeedback.mediumImpact();
    try {
      final start = await api.startTripWithLegs(route.legs);
      unawaited(
        activeTrip.begin(
          tripId: start.tripId,
          label: journeyPathSummary(route.legs),
          legs: route.legs,
        ),
      );
      unawaited(_recentStore.push(route.legs));
      if (!mounted) {
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => TripPage(
            tripId: start.tripId,
            journeyLabel: journeyPathSummary(route.legs),
            legs: route.legs,
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

  /// 최근 간 길 → 여정 저장 (라벨만) — 저장되면 여정 목록으로 올라가고 최근에서 빠진다
  Future<void> _saveRecent(RecentRoute route) async {
    final label = await showSaveJourneySheet(context, route.legs);
    if (label != null) {
      unawaited(_load());
    }
  }

  Future<void> _removeRecent(RecentRoute route) async {
    await _recentStore.remove(route.legs);
    unawaited(_loadRecent());
  }

  Future<void> _startTrip(Journey journey) async {
    // 햅틱: 트립 시작 = 주요 확정 액션 (CLAUDE.md 적응형 UI 규칙)
    HapticFeedback.mediumImpact();
    try {
      final start = await api.startTrip(journey.id);
      // 이어보기·메인 요약 카드·잠금화면 표면을 한 번에 건다 (서버에 활성 트립 조회가 없다 — §9)
      unawaited(
        activeTrip.begin(
          tripId: start.tripId,
          label: journey.label,
          journeyId: journey.id,
        ),
      );
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
      // 트립에서 돌아오면 히스토리(lastUsedAt) 순서를 반영
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

  Future<void> _deleteJourney(Journey journey) async {
    final confirmed = await showAppSheet<bool>(
      context: context,
      header: '"${journey.label}" 여정을 삭제할까요?',
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpace.xl,
          0,
          AppSpace.xl,
          AppSpace.lg,
        ),
        child: AppButton(
          label: '삭제',
          variant: AppButtonVariant.danger,
          block: true,
          onPressed: () => Navigator.of(sheetContext).pop(true),
        ),
      ),
    );
    if (confirmed != true) {
      return;
    }
    try {
      await api.deleteJourney(journey.id);
    } on ApiException catch (error) {
      // 이미 없는 여정은 목적 달성 — 목록 갱신으로 정리
      if (error.code != ApiException.settingNotFound && error.status != 404) {
        return;
      }
    } catch (_) {
      return;
    }
    unawaited(_load());
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
    // 콘텐츠가 글라스 헤더·네비 뒤로 흐른다 — 상하 여백은 스크롤 padding이 담당
    final headerBottom =
        MediaQuery.paddingOf(context).top + TabHeader.contentHeight;
    // 여정 없는 초기 화면 — 출발 알림 탭 온보딩 안내와 같은 가운데 타이틀·서브타이틀·버튼
    // (오너 결정 2026-09-16: 탭 디자인 통일). 진행 중 트립이 있으면 목록 레이아웃 유지
    // 1회성이 기본 동선 — 저장은 입력 화면 안 스위치·트립 중·최근 간 길에서 언제든
    // (오너 화면 재구성 2026-09-21)
    if (_phase == _JourneyPhase.ready &&
        _journeys.isEmpty &&
        _recent.isEmpty &&
        !activeTrip.hasTrip) {
      return Scaffold(
        backgroundColor: context.colors.background,
        extendBodyBehindAppBar: true,
        appBar: const TabHeader(title: '하차 알림'),
        body: Padding(
          padding: EdgeInsets.only(top: headerBottom),
          child: CenterMessage(
            title: '내릴 역, 놓치지 않게\n알려드릴게요',
            titleLarge: true,
            subtitle: '탑승 역과 내릴 역만 넣으면 바로 추적해요.\n자주 가는 길은 저장해두고 원탭으로 시작해요',
            buttonLabel: '바로 시작하기',
            onPressed: () => unawaited(_openStart()),
            secondaryLabel: '경로 생성하기',
            onSecondaryPressed: () => unawaited(_openCreate()),
          ),
        ),
      );
    }
    // 경로 생성은 목록 위에 떠 있는 FAB(가운데, 아이콘 + 라벨) — 목록 끝까지 내려가지 않아도
    // 보인다 (오너 요청 2026-09-21). 10개 꽉 찼으면 숨긴다. 하단 여백은 글라스 네비 높이
    // (MediaQuery.padding.bottom에 포함) 위로 띄운다
    final showFab = _phase == _JourneyPhase.ready && _journeys.length < maxJourneys;
    final navBottom = MediaQuery.paddingOf(context).bottom;
    return Scaffold(
      backgroundColor: context.colors.background,
      extendBodyBehindAppBar: true,
      appBar: const TabHeader(title: '하차 알림'),
      body: Stack(
        children: [
          RefreshIndicator.adaptive(
            edgeOffset: headerBottom,
            onRefresh: _load,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.only(
                top: headerBottom + AppSpace.md,
                // FAB가 마지막 카드를 덮지 않게 그 높이만큼 더 띄운다
                bottom: navBottom + AppSpace.lg + (showFab ? _fabClearance : 0),
              ),
              children: _body(),
            ),
          ),
          if (showFab)
            Positioned(
              left: 0,
              right: 0,
              bottom: navBottom + AppSpace.md,
              child: Center(
                child: FloatingActionButton.extended(
                  heroTag: 'journey-create-fab',
                  onPressed: () => unawaited(_openCreate()),
                  backgroundColor: context.colors.primary,
                  foregroundColor: context.colors.onPrimary,
                  elevation: 3,
                  shape: const StadiumBorder(),
                  icon: const Icon(Icons.add),
                  label: const Text('경로 생성하기', style: AppTypo.body),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// FAB 높이(56) + 여백 — 목록 하단 패딩 보정
  static const double _fabClearance = 56 + AppSpace.lg;

  List<Widget> _body() {
    switch (_phase) {
      case _JourneyPhase.loading:
        return [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.xl),
            child: Text(
              '여정을 불러오고 있어요…',
              style: AppTypo.bodySm.copyWith(color: context.colors.inkSubtle),
            ),
          ),
        ];
      case _JourneyPhase.unavailable:
        return [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('하차 알림을 준비하고 있어요', style: AppTypo.heading),
                const SizedBox(height: AppSpace.xs),
                Text(
                  '서버 업데이트 후 이용할 수 있어요. 조금만 기다려주세요',
                  style: AppTypo.caption.copyWith(
                    color: context.colors.inkMuted,
                  ),
                ),
              ],
            ),
          ),
        ];
      case _JourneyPhase.failed:
        return [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('여정을 불러오지 못했어요', style: AppTypo.heading),
                const SizedBox(height: AppSpace.md),
                AppButton(
                  label: '다시 시도',
                  variant: AppButtonVariant.tonal,
                  medium: true,
                  onPressed: () => unawaited(_load()),
                ),
              ],
            ),
          ),
        ];
      case _JourneyPhase.ready:
        final hasTrip = activeTrip.hasTrip;
        return [
          // 메인 탭과 같은 카드 — 탭마다 다른 모양을 쓰지 않는다 (오너 요청 2026-09-22)
          if (hasTrip)
            ActiveTripCard(
              status: activeTrip.status!,
              leg: activeTrip.currentLeg,
              onTap: () => unawaited(_openTrip(activeTrip.tripId!)),
            ),
          // 여정·최근 길 없음 + 진행 중 트립 없음은 build의 가운데 안내가 담당한다.
          // 시작 진입점이 맨 위의 영역(카드) — 진행 중 트립이 있으면 동시 1개 규칙(§9-2)에 걸리므로 숨긴다
          if (!hasTrip) _startCard(),
          if (_journeys.isNotEmpty) _sectionHeader('저장한 여정'),
          for (final journey in _journeys) _journeyCard(journey),
          // 저장 안 한 1회성 길 — 원탭 재시작·나중에 저장 (FR-708 → FR-702 전환 루프)
          if (_recent.isNotEmpty) _sectionHeader('최근 간 길'),
          for (final route in _recent) _recentCard(route, !hasTrip),
          // 경로 생성은 build의 FAB가 담당한다
          // 광고는 여정 목록·만들기 버튼 아래 스크롤 끝 — 시작 동선을 가로막지 않고,
          // 화면에 고정해 따라다니지 않는다 (오너 결정 2026-09-19: 셸 하단 플로팅 폐기)
          const AdBanner(),
        ];
    }
  }

  /// 새 길 바로 시작 영역 — 버튼 하나가 아니라 안내 문구를 가진 카드 (오너 요청 2026-09-21)
  Widget _startCard() {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('어디까지 가세요?', style: AppTypo.heading),
          const SizedBox(height: AppSpace.xs),
          Text(
            '탑승 역과 내릴 역만 넣으면 바로 추적해요',
            style: AppTypo.caption.copyWith(color: context.colors.inkMuted),
          ),
          const SizedBox(height: AppSpace.md),
          AppButton(
            label: '하차 알림 시작하기',
            medium: true,
            block: true,
            onPressed: () => unawaited(_openStart()),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.xl,
        AppSpace.xs,
        AppSpace.xl,
        AppSpace.sm,
      ),
      child: Text(
        title,
        style: AppTypo.caption.copyWith(color: context.colors.inkSubtle),
      ),
    );
  }

  Widget _recentCard(RecentRoute route, bool canStart) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  journeyPathSummary(route.legs),
                  style: AppTypo.heading,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              GestureDetector(
                onTap: () => unawaited(_removeRecent(route)),
                behavior: HitTestBehavior.opaque,
                child: Icon(
                  Icons.close,
                  size: 20,
                  color: context.colors.inkSubtle,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.xs),
          Text(
            '${recentRouteDateLabel(route.lastUsedAt, DateTime.now())} · '
            '${route.legs.map((leg) => leg.line).join(' → ')}',
            style: AppTypo.caption.copyWith(color: context.colors.inkSubtle),
          ),
          const SizedBox(height: AppSpace.md),
          Row(
            children: [
              if (canStart) ...[
                Expanded(
                  child: AppButton(
                    label: '다시 시작',
                    medium: true,
                    block: true,
                    onPressed: () => unawaited(_restartRecent(route)),
                  ),
                ),
                const SizedBox(width: AppSpace.sm),
              ],
              Expanded(
                child: AppButton(
                  label: '저장',
                  variant: AppButtonVariant.tonal,
                  medium: true,
                  block: true,
                  onPressed: () => unawaited(_saveRecent(route)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _journeyCard(Journey journey) {
    final repeat = _repeatDaysLabel(journey.repeatDays);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  journey.label,
                  style: AppTypo.heading,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              GestureDetector(
                onTap: () => unawaited(_deleteJourney(journey)),
                behavior: HitTestBehavior.opaque,
                child: Icon(
                  Icons.delete_outline,
                  size: 20,
                  color: context.colors.inkSubtle,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.xs),
          Text(
            journeyPathSummary(journey.legs),
            style: AppTypo.bodySm.copyWith(color: context.colors.inkMuted),
          ),
          if (repeat.isNotEmpty) ...[
            const SizedBox(height: AppSpace.xs),
            Text(
              '반복: $repeat',
              style: AppTypo.caption.copyWith(color: context.colors.inkSubtle),
            ),
          ],
          const SizedBox(height: AppSpace.md),
          AppButton(
            label: '시작',
            medium: true,
            block: true,
            onPressed: () => unawaited(_startTrip(journey)),
          ),
        ],
      ),
    );
  }
}
