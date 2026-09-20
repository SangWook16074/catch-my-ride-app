/// "출발 알림이 꺼져 있어요" 배너 노출 규칙 — 알림 권한 없이 경로만 쓰는 유저(권한 거부·미결정)에게
/// 라이브 뷰에서 다시 켤 길을 준다 (미니앱 2026-09-14 오너 요구 이식, src/domain/pushConsentBanner.ts).
///
/// 스토어판은 FCM 권한 상태를 조용히 조회할 수 있지만(PushBridge.isAuthorized) 자동 재요청은 여전히
/// 금지 — 배너는 수동 진입점이고, "알림 켜기"를 눌렀을 때만 권한 다이얼로그(또는 설정 안내)가 뜬다.
/// "나중에"로 닫으면 7일간 다시 보여주지 않는다 — 잔소리 앱 금지 (buffer_suggestion과 동일 패턴).
library;

const int pushBannerSuppressDays = 7;

/// 로컬 저장소 키 — "나중에" 마지막 탭 시각(ISO)
const String pushBannerDismissedAtKey =
    'catch-my-ride/push-consent-banner-dismissed-at';

bool shouldShowPushConsentBanner(
  bool authorized,
  String? dismissedAtIso,
  DateTime now,
) {
  if (authorized) {
    return false;
  }
  if (dismissedAtIso == null) {
    return true;
  }
  final dismissedAt = DateTime.tryParse(dismissedAtIso);
  if (dismissedAt == null) {
    return true; // 저장값이 깨졌으면 억제하지 않는다 — 알림이 영영 꺼진 채가 더 나쁜 실패
  }
  return now.difference(dismissedAt) >=
      const Duration(days: pushBannerSuppressDays);
}
