/// 진행 중 트립 카드 — 메인 탭과 하차 알림 탭이 **같은 모양**을 쓴다
/// (오너 요청 2026-09-22: 하차 알림 탭도 메인처럼 보이게).
///
/// 값은 전역 `activeTrip`이 공급한다 — 이 위젯은 표시만 한다.
library;

import 'package:flutter/material.dart';

import '../../domain/journey.dart';
import '../design/components/card.dart';
import '../design/tokens.dart';
import 'route_strip.dart';

class ActiveTripCard extends StatelessWidget {
  const ActiveTripCard({
    super.key,
    required this.status,
    required this.onTap,
    this.leg,
  });

  final TripStatus status;

  /// 이동 중 구간 — 있으면 구간 스트립을 같이 그린다. 모르면 생략
  final JourneyLeg? leg;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final leg = this.leg;
    return GestureDetector(
      onTap: onTap,
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
                      Text(activeTripSummary(status), style: AppTypo.heading),
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
            if (leg != null) ...[
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
    );
  }
}

/// 카드 한 줄 요약 — 위치를 알면 "현재 ○○ 부근"까지 붙인다 (§9-3 currentStop,
/// 오너 피드백 2026-09-22: 특정이 끝났는데도 "위치 확인 중"에 묶여 보였다)
String activeTripSummary(TripStatus status) => switch (status.phase) {
  TripPhase.transfer => '${status.eventStop} 환승 대기 중',
  TripPhase.lost => '추적이 끊겼어요',
  TripPhase.done => '목적지 도착',
  _ => switch ((status.remainingStops, status.currentStop)) {
    (final int remaining, _) => '${status.eventStop}까지 $remaining정거장',
    (null, final String current) => '현재 $current 부근',
    _ => '${status.eventStop}행 위치 확인 중',
  },
};
