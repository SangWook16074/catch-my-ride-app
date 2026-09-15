import 'package:flutter/material.dart';

import '../domain/live_view.dart';
import '../domain/models.dart';
import 'components/ad_banner.dart';
import 'design/components/button.dart';
import 'design/components/card.dart';
import 'design/tokens.dart';

/// 라이브 뷰 본문 — 미니앱 LiveViewScreen.tsx 이식.
/// 위젯 배치(헤더 → 안내 배너 → 피드백 카드 → 버퍼 추천 카드 → 도착 목록 → 갱신 시각 푸터)를
/// 미니앱과 동일하게 유지한다. 스타일은 자체 디자인 시스템(design/tokens.dart).
class LiveViewScreen extends StatelessWidget {
  const LiveViewScreen({
    super.key,
    required this.response,
    required this.stale,
    required this.todayFeedback,
    required this.onSubmitFeedback,
    this.onPressSettings,
    this.onPressDeleteRoute,
    this.bufferSuggestion,
    this.appliedBufferMinutes,
    this.onApplyBufferSuggestion,
    this.onDismissBufferSuggestion,
  });

  final ArrivalsResponse response;

  /// 마지막 폴링 실패 — 이전 데이터를 표시 중 (NFR-07)
  final bool stale;
  final BoardingResult? todayFeedback;
  final ValueChanged<BoardingResult> onSubmitFeedback;

  /// 재설정 진입점 — 미지정이면 버튼을 숨긴다
  final VoidCallback? onPressSettings;

  /// 현재 경로 삭제 진입점 — 확인 시트는 페이지 책임. 미지정이면 숨긴다
  final VoidCallback? onPressDeleteRoute;

  /// §3-1 버퍼 자동 추천 — null이면 카드를 숨긴다
  final BufferRecommendation? bufferSuggestion;

  /// 방금 추천을 적용해 바뀐 새 버퍼(분) — 확인 문구를 보여준다
  final int? appliedBufferMinutes;
  final VoidCallback? onApplyBufferSuggestion;
  final VoidCallback? onDismissBufferSuggestion;

  @override
  Widget build(BuildContext context) {
    final best = pickBestBoardable(response.arrivals);

    return ListView(
      // 하단은 글라스 네비 높이(MediaQuery.padding.bottom)까지 비워 마지막 행이 가려지지 않게
      padding: EdgeInsets.only(
        top: AppSpace.lg,
        bottom: AppSpace.lg + MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        // 헤더 — 제목 + 삭제/재설정 진입점
        Padding(
          padding: const EdgeInsets.only(
            left: AppSpace.xl,
            right: AppSpace.xl,
            bottom: AppSpace.md,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      best != null
                          ? '지금 나가면 ${best.routeName} 탈 수 있어요'
                          : '지금은 탈 수 있는 차가 없어요',
                      style: AppTypo.title,
                    ),
                  ),
                  if (onPressDeleteRoute != null) ...[
                    const SizedBox(width: AppSpace.md),
                    _HeaderAction(label: '삭제', onPressed: onPressDeleteRoute!),
                  ],
                  if (onPressSettings != null) ...[
                    const SizedBox(width: AppSpace.md),
                    _HeaderAction(label: '재설정', onPressed: onPressSettings!),
                  ],
                ],
              ),
              const SizedBox(height: AppSpace.xs),
              Text(
                '도보 ${response.walkMinutes}분 기준으로 비교해요',
                style: AppTypo.bodySm.copyWith(color: context.colors.inkMuted),
              ),
            ],
          ),
        ),

        if (stale)
          const _Notice(
            text: '연결이 원활하지 않아요. 마지막으로 받은 정보예요',
            tone: AppCardTone.caution,
          ),
        if (!response.realtimeAvailable)
          const _Notice(
            text: '실시간 정보가 없어요. 잠시 후 다시 확인해주세요',
            tone: AppCardTone.neutral,
          ),

        _FeedbackCard(
          todayFeedback: todayFeedback,
          onSubmitFeedback: onSubmitFeedback,
        ),

        if (appliedBufferMinutes != null)
          AppCard(
            tone: AppCardTone.brand,
            child: Text(
              '여유 시간을 $appliedBufferMinutes분으로 늘렸어요. '
              '다음 알림부터 더 일찍 알려드릴게요',
              style: AppTypo.bodySm.copyWith(color: context.colors.inkMuted),
            ),
          )
        else if (bufferSuggestion != null)
          _SuggestionCard(
            suggestion: bufferSuggestion!,
            onApply: onApplyBufferSuggestion,
            onDismiss: onDismissBufferSuggestion,
          ),

        for (final arrival in response.arrivals) _ArrivalRow(arrival: arrival),

        // 광고는 도착 목록이 끝난 뒤 — 핵심 정보(탈 수 있는 차)를 절대 밀어내지 않는다
        const AdBanner(),

        Padding(
          padding: const EdgeInsets.only(top: AppSpace.lg),
          child: Text(
            '마지막 갱신 ${formatFetchedAt(response.fetchedAt)}',
            textAlign: TextAlign.center,
            style: AppTypo.caption.copyWith(color: context.colors.inkFaint),
          ),
        ),
      ],
    );
  }
}

class _HeaderAction extends StatelessWidget {
  const _HeaderAction({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.xs),
          child: Text(
            label,
            style: AppTypo.bodySm.copyWith(color: context.colors.inkMuted),
          ),
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text, required this.tone});

  final String text;
  final AppCardTone tone;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      tone: tone,
      margin: const EdgeInsets.only(
        left: AppSpace.xl,
        right: AppSpace.xl,
        bottom: AppSpace.md,
      ),
      child: Text(text, style: AppTypo.bodySm.copyWith(color: context.colors.inkMuted)),
    );
  }
}

/// FR-601 원탭 탑승 피드백 카드
class _FeedbackCard extends StatelessWidget {
  const _FeedbackCard({
    required this.todayFeedback,
    required this.onSubmitFeedback,
  });

  final BoardingResult? todayFeedback;
  final ValueChanged<BoardingResult> onSubmitFeedback;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: todayFeedback != null
          ? Text(
              '피드백을 기록했어요. 내일 더 정확하게 알려드릴게요',
              style: AppTypo.bodySm.copyWith(color: context.colors.inkMuted),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('오늘 알림대로 탑승하셨나요?', style: AppTypo.heading),
                const SizedBox(height: AppSpace.md),
                Row(
                  children: [
                    Expanded(
                      child: AppButton(
                        label: '탔어요',
                        medium: true,
                        block: true,
                        onPressed: () =>
                            onSubmitFeedback(BoardingResult.boarded),
                      ),
                    ),
                    const SizedBox(width: AppSpace.sm),
                    Expanded(
                      child: AppButton(
                        label: '놓쳤어요',
                        variant: AppButtonVariant.tonal,
                        medium: true,
                        block: true,
                        onPressed: () => onSubmitFeedback(BoardingResult.missed),
                      ),
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}

/// §3-1 버퍼 자동 추천 카드 — 놓침이 잦으면 +5분 제안
class _SuggestionCard extends StatelessWidget {
  const _SuggestionCard({
    required this.suggestion,
    required this.onApply,
    required this.onDismiss,
  });

  final BufferRecommendation suggestion;
  final VoidCallback? onApply;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      tone: AppCardTone.brand,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '여유 시간을 ${suggestion.suggestedIncrementMinutes}분 늘려볼까요?',
            style: AppTypo.heading,
          ),
          const SizedBox(height: AppSpace.xs),
          Text(
            '최근 ${suggestion.sampleSize}번 중 ${suggestion.missedCount}번 놓쳤어요. '
            '알림이 조금 더 일찍 오면 놓칠 걱정이 줄어요',
            style: AppTypo.bodySm.copyWith(color: context.colors.inkMuted),
          ),
          const SizedBox(height: AppSpace.md),
          Row(
            children: [
              Expanded(
                child: AppButton(
                  label: '${suggestion.suggestedIncrementMinutes}분 늘리기',
                  medium: true,
                  block: true,
                  onPressed: onApply,
                ),
              ),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: AppButton(
                  label: '괜찮아요',
                  variant: AppButtonVariant.tonal,
                  medium: true,
                  block: true,
                  onPressed: onDismiss,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ArrivalRow extends StatelessWidget {
  const _ArrivalRow({required this.arrival});

  final Arrival arrival;

  @override
  Widget build(BuildContext context) {
    // 회색 비활성은 "시간 정보 없음"에만 쓴다 (TODO 2026-09-09, 미니앱 실측):
    // 못 타는 차를 흐리게 하면 유저가 이미 지나간 차로 오해한다. 시간 정보가 있으면
    // 노선명은 활성 색을 유지하고, 남은 시간만 뮤트 암버로 "곧 도착" 긴박감을 준다
    // (탑승 가능 = 세이지 그린과 구분). 상태 문구는 색상 외 수단으로 전달된다 (NFR-06).
    final hasTime = arrival.secondsToArrival != null;
    final timeColor = !hasTime
        ? context.colors.inkFaint
        : arrival.boardable
        ? context.colors.primaryStrong
        : context.colors.cautionStrong;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpace.xl,
        vertical: 10,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      arrival.routeName,
                      style: AppTypo.body.copyWith(
                        fontWeight: FontWeight.w600,
                        color: hasTime ? context.colors.ink : context.colors.inkFaint,
                      ),
                    ),
                    if (arrival.isExpress ?? false) ...[
                      const SizedBox(width: 6),
                      const _ExpressBadge(),
                    ],
                  ],
                ),
                Text(
                  arrival.remainingStops != null
                      ? '${arrival.stopDisplayName} · ${arrival.remainingStops}정거장 전'
                      : arrival.stopDisplayName,
                  style: AppTypo.caption.copyWith(color: context.colors.inkSubtle),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpace.md),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                formatRemaining(arrival.secondsToArrival),
                style: AppTypo.body.copyWith(
                  fontWeight: FontWeight.w700,
                  color: timeColor,
                ),
              ),
              Text(
                statusLabel(arrival.status),
                style: AppTypo.caption.copyWith(
                  color: hasTime ? context.colors.inkMuted : context.colors.inkFaint,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ExpressBadge extends StatelessWidget {
  const _ExpressBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: context.colors.dangerSoft,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '급행',
        style: AppTypo.caption.copyWith(
          color: context.colors.dangerStrong,
          fontWeight: FontWeight.w600,
          fontSize: 11,
        ),
      ),
    );
  }
}
