/// 버퍼 추천 처리 시각 보관 — 도메인 규칙(7일 억제)의 저장소 부분.
/// 미니앱은 앱인토스 Storage를 썼고, 스토어판은 SharedPreferences를 쓴다.
library;

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/buffer_suggestion.dart';

class SuggestionStore {
  /// 저장 실패 — 다음 세션에 카드가 한 번 더 뜰 뿐, 흐름을 막지 않는다
  Future<void> writeHandledAt(DateTime now) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        bufferSuggestionHandledAtKey,
        now.toIso8601String(),
      );
    } catch (_) {
      // 조용히 무시 (미니앱 writeBufferSuggestionHandledAt과 동일)
    }
  }

  Future<String?> readHandledAt() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(bufferSuggestionHandledAtKey);
    } catch (_) {
      return null;
    }
  }
}
