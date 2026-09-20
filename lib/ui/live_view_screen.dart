import 'package:flutter/material.dart';

import '../domain/live_view.dart';
import '../domain/models.dart';
import 'components/ad_banner.dart';
import 'design/components/button.dart';
import 'design/components/card.dart';
import 'design/tokens.dart';

/// 라이브 뷰 본문 — 미니앱 LiveViewScreen.tsx 이식.
/// 위젯 배치(히어로 문구 → 안내 배너 → 피드백 카드 → 버퍼 추천 카드 → 푸시 재동의 배너 → 도착 목록
/// → 갱신 시각 푸터)를 미니앱과 동일하게 유지한다. 스타일은 자체 디자인 시스템(design/tokens.dart).
/// 탭 제목·삭제/재설정 액션은 HomePage의 공통 탭 헤더(TabHeader) 담당 (2026-09-16 헤더 통일).
class LiveViewScreen extends StatelessWidget {
  const LiveViewScreen({
    super.key,
    required this.response,
    required this.stale,
    required this.todayFeedback,
    required this.onSubmitFeedback,
    this.setting,
    this.leading,
    this.topPadding = AppSpace.lg,
    this.bufferSuggestion,
    this.appliedBufferMinutes,
    this.onApplyBufferSuggestion,
    this.onDismissBufferSuggestion,
    this.pushBanner = PushBannerState.hidden,
    this.onEnablePush,
    this.onDismissPushBanner,
  });

  final ArrivalsResponse response;

  /// 현재 경로 설정 — 여유·알림 시점 안내(FR-501 개정 2026-09-20). null이면 안내를 숨긴다
  final CommuteSetting? setting;

  /// 마지막 폴링 실패 — 이전 데이터를 표시 중 (NFR-07)
  final bool stale;
  final BoardingResult? todayFeedback;
  final ValueChanged<BoardingResult> onSubmitFeedback;

  /// 히어로 문구 위에 끼우는 위젯(경로 칩 바) — 스크롤에 포함돼 글라스 헤더 뒤로 흐른다
  final Widget? leading;

  /// 스크롤 상단 패딩 — 글라스 헤더 아래에서 시작하도록 페이지가 계산해 넘긴다
  final double topPadding;

  /// §3-1 버퍼 자동 추천 — null이면 카드를 숨긴다
  final BufferRecommendation? bufferSuggestion;

  /// 방금 추천을 적용해 바뀐 새 버퍼(분) — 확인 문구를 보여준다
  final int? appliedBufferMinutes;
  final VoidCallback? onApplyBufferSuggestion;
  final VoidCallback? onDismissBufferSuggestion;

  /// 푸시 재동의 배너 (미니앱 2026-09-14 이식) — 알림 권한 없이 경로만 쓰는 유저에게 다시 켤 길을 준다
  final PushBannerState pushBanner;

  /// "알림 켜기" — 이때만 권한 다이얼로그(거부 상태면 설정 안내)가 뜬다
  final VoidCallback? onEnablePush;

  /// "나중에" — 7일간 다시 보여주지 않는다
  final VoidCallback? onDismissPushBanner;

  @override
  Widget build(BuildContext context) {
    final best = pickBestBoardable(response.arrivals);

    return ListView(
      // 하단은 글라스 네비 높이(MediaQuery.padding.bottom)까지 비워 마지막 행이 가려지지 않게
      padding: EdgeInsets.only(
        top: topPadding,
        bottom: AppSpace.lg + MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        if (leading != null) ...[leading!, const SizedBox(height: AppSpace.lg)],
        // 히어로 문구 — 탭 제목(TabHeader) 아래 위계라 heading을 쓴다
        Padding(
          padding: const EdgeInsets.only(
            left: AppSpace.xl,
            right: AppSpace.xl,
            bottom: AppSpace.md,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                best != null
                    ? '지금 나가면 ${best.routeName} 탈 수 있어요'
                    : '지금은 탈 수 있는 차가 없어요',
                style: AppTypo.heading,
              ),
              const SizedBox(height: AppSpace.xs),
              Text(
                '역까지 ${response.walkMinutes}분 걸려요',
                style: AppTypo.bodySm.copyWith(color: context.colors.inkMuted),
              ),
              if (setting != null) ...[
                const SizedBox(height: AppSpace.xs),
                Text(
                  notificationSummary(setting!),
                  style: AppTypo.caption.copyWith(
                    color: context.colors.inkSubtle,
                  ),
                ),
              ],
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

        // 광고는 피드백 카드와 도착 목록(전철 정보) 사이에 깔린다 —
        // 화면에 고정해 따라다니지 않는다 (오너 결정 2026-09-19)
        const AdBanner(),

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

        if (pushBanner == PushBannerState.enabled)
          AppCard(
            child: Text(
              '출발 알림을 켰어요. 이제 나갈 타이밍에 맞춰 알려드릴게요',
              style: AppTypo.bodySm.copyWith(color: context.colors.inkMuted),
            ),
          )
        else if (pushBanner != PushBannerState.hidden)
          _PushConsentCard(
            enabling: pushBanner == PushBannerState.enabling,
            onEnable: onEnablePush,
            onDismiss: onDismissPushBanner,
          ),

        for (final arrival in response.arrivals) _ArrivalRow(arrival: arrival),

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
      child: Text(
        text,
        style: AppTypo.bodySm.copyWith(color: context.colors.inkMuted),
      ),
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
                        onPressed: () =>
                            onSubmitFeedback(BoardingResult.missed),
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

/// 라이브 뷰 푸시 재동의 배너 상태 — visible=배너 / enabling=권한 요청 진행 중(버튼 로딩) /
/// enabled=방금 켜짐(확인 문구) / hidden=없음
enum PushBannerState { hidden, visible, enabling, enabled }

/// "출발 알림이 꺼져 있어요" — 재동의 진입점. 권한 다이얼로그는 "알림 켜기"를 눌렀을 때만
class _PushConsentCard extends StatelessWidget {
  const _PushConsentCard({
    required this.enabling,
    required this.onEnable,
    required this.onDismiss,
  });

  final bool enabling;
  final VoidCallback? onEnable;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('출발 알림이 꺼져 있어요', style: AppTypo.heading),
          const SizedBox(height: AppSpace.xs),
          Text(
            '알림을 켜면 나갈 타이밍에 맞춰 알려드려요. '
            '화면을 보고 있지 않아도 놓치지 않아요',
            style: AppTypo.bodySm.copyWith(color: context.colors.inkMuted),
          ),
          const SizedBox(height: AppSpace.md),
          Row(
            children: [
              Expanded(
                child: AppButton(
                  label: '알림 켜기',
                  medium: true,
                  block: true,
                  loading: enabling,
                  onPressed: enabling ? null : onEnable,
                ),
              ),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: AppButton(
                  label: '나중에',
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
                        color: hasTime
                            ? context.colors.ink
                            : context.colors.inkFaint,
                      ),
                    ),
                    if (arrival.isExpress ?? false) ...[
                      const SizedBox(width: 6),
                      const _ExpressBadge(),
                    ],
                  ],
                ),
                Text(
                  // FR-501 개정: 방면 표기 — 지하철 "수유역 · 당고개행", 버스 "여의도환승센터 · 강남역 방면"(v0.6)
                  [
                    arrival.stopDisplayName,
                    if (arrival.directionLabel != null) arrival.directionLabel,
                    if (arrival.remainingStops != null)
                      '${arrival.remainingStops}정거장 전',
                  ].join(' · '),
                  style: AppTypo.caption.copyWith(
                    color: context.colors.inkSubtle,
                  ),
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
                  color: hasTime
                      ? context.colors.inkMuted
                      : context.colors.inkFaint,
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
