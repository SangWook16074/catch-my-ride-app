import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/api.dart';
import '../data/trip_store.dart';
import '../domain/journey.dart';
import '../domain/models.dart';
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
  final TripStore _tripStore = TripStore();
  _JourneyPhase _phase = _JourneyPhase.loading;
  List<Journey> _journeys = [];

  /// 진행 중 트립(이어보기) — 로컬 보관 tripId를 서버 상태로 확인한다
  String? _activeTripId;
  TripStatus? _activeTrip;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(JourneyPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    unawaited(_checkActiveTrip());
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

  Future<void> _checkActiveTrip() async {
    final tripId = await _tripStore.read();
    if (tripId == null) {
      if (mounted) {
        setState(() {
          _activeTripId = null;
          _activeTrip = null;
        });
      }
      return;
    }
    try {
      final status = await api.getTrip(tripId);
      if (!mounted) {
        return;
      }
      setState(() {
        _activeTripId = tripId;
        _activeTrip = status;
      });
    } on ApiException catch (error) {
      if (error.status == 404) {
        // 서버에서 이미 정리된 트립 — 로컬 보관도 정리
        unawaited(_tripStore.clear());
        if (mounted) {
          setState(() {
            _activeTripId = null;
            _activeTrip = null;
          });
        }
      }
    } catch (_) {
      // 네트워크 실패 — 배너만 생략, 다음 갱신에 재시도
    }
  }

  Future<void> _openTrip(String tripId) async {
    // 보관된 여정 id가 있으면 같이 넘긴다 — LOST 화면 "처음부터 다시 추적" 진입점
    final journeyId = await _tripStore.readJourneyId();
    if (!mounted) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TripPage(tripId: tripId, journeyId: journeyId),
      ),
    );
    unawaited(_load());
  }

  Future<void> _openCreate() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const JourneyCreatePage()),
    );
    if (created == true) {
      unawaited(_load());
    }
  }

  Future<void> _startTrip(Journey journey) async {
    // 햅틱: 트립 시작 = 주요 확정 액션 (CLAUDE.md 적응형 UI 규칙)
    HapticFeedback.mediumImpact();
    try {
      final start = await api.startTrip(journey.id);
      // 이어보기·메인 요약 카드용 로컬 보관 (서버에 활성 트립 조회가 없다 — §9)
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
            style: AppTypo.bodySm.copyWith(
              color: sheetContext.colors.inkMuted,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false, // 콘텐츠가 글라스 네비 밑으로 흐른다 — 하단 여백은 ListView padding이 담당
      child: RefreshIndicator.adaptive(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.only(
            top: AppSpace.md,
            bottom: MediaQuery.paddingOf(context).bottom + AppSpace.lg,
          ),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.xl,
                AppSpace.lg,
                AppSpace.xl,
                AppSpace.xs,
              ),
              child: const Text('하차 알림', style: AppTypo.title),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.xl,
                0,
                AppSpace.xl,
                AppSpace.lg,
              ),
              child: Text(
                '탑승하면 시작을 눌러주세요 — 내릴 역을 알려드려요',
                style: AppTypo.bodySm.copyWith(color: context.colors.inkMuted),
              ),
            ),
            ..._body(),
          ],
        ),
      ),
    );
  }

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
                  '서버 업데이트 후 이용할 수 있어요 — 조금만 기다려주세요',
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
        final activeTrip = _activeTrip;
        final activeTripId = _activeTripId;
        return [
          if (activeTrip != null && activeTripId != null)
            AppCard(
              tone: AppCardTone.brand,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('진행 중인 트립이 있어요', style: AppTypo.heading),
                  const SizedBox(height: AppSpace.xs),
                  Text(
                    _activeTripSummary(activeTrip),
                    style: AppTypo.bodySm.copyWith(
                      color: context.colors.inkMuted,
                    ),
                  ),
                  const SizedBox(height: AppSpace.md),
                  AppButton(
                    label: '이어보기',
                    medium: true,
                    block: true,
                    onPressed: () => unawaited(_openTrip(activeTripId)),
                  ),
                ],
              ),
            ),
          if (_journeys.isEmpty)
            AppCard(
              tone: AppCardTone.brand,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('아직 여정이 없어요', style: AppTypo.heading),
                  const SizedBox(height: AppSpace.xs),
                  Text(
                    '출발지부터 목적지까지, 환승 구간까지 넣어두면\n내릴 타이밍을 알려드려요',
                    style: AppTypo.caption.copyWith(
                      color: context.colors.inkMuted,
                    ),
                  ),
                ],
              ),
            )
          else
            for (final journey in _journeys) _journeyCard(journey),
          if (_journeys.length < maxJourneys)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.xl,
                0,
                AppSpace.xl,
                AppSpace.lg,
              ),
              child: AppButton(
                label: '+ 여정 만들기',
                variant: _journeys.isEmpty
                    ? AppButtonVariant.primary
                    : AppButtonVariant.tonal,
                block: true,
                onPressed: () => unawaited(_openCreate()),
              ),
            ),
        ];
    }
  }

  String _activeTripSummary(TripStatus status) => switch (status.phase) {
    TripPhase.transfer => '${status.eventStop} 환승 대기 중 — 탑승하면 눌러주세요',
    TripPhase.lost => '추적이 끊겼어요 — 상태를 확인해주세요',
    TripPhase.done => '목적지 도착 — 트립을 마무리해주세요',
    _ => status.remainingStops == null
        ? '${status.eventStop}행 — 위치 확인 중'
        : '${status.eventStop}까지 ${status.remainingStops}정거장',
  };

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
