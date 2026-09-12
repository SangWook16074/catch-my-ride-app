/// 버퍼 자동 추천(API.md §3-1) 노출 규칙 — 서버는 판정만 주고, "언제 다시 보여줄지"는 클라이언트가 정한다.
/// 한 번 처리(적용/거절)하면 7일간 다시 묻지 않는다 — 알림 앱이 잔소리 앱이 되면 안 된다.
/// 미니앱 src/domain/bufferSuggestion.ts 이식.
library;

import 'models.dart';

const int suppressDays = 7;

/// 로컬 저장소 키 — 마지막 처리 시각(ISO). 적용·거절 모두 같은 키를 쓴다
const String bufferSuggestionHandledAtKey =
    'catch-my-ride/buffer-suggestion-handled-at';

bool shouldShowBufferSuggestion(
  BufferRecommendation? recommendation,
  String? handledAtIso,
  DateTime now,
) {
  if (recommendation == null || !recommendation.recommend) {
    return false;
  }
  if (handledAtIso == null) {
    return true;
  }
  final handledAt = DateTime.tryParse(handledAtIso);
  if (handledAt == null) {
    return true; // 저장값이 깨졌으면 억제하지 않는다 — 추천이 아예 사라지는 쪽이 더 나쁜 실패
  }
  return now.difference(handledAt) >= const Duration(days: suppressDays);
}
