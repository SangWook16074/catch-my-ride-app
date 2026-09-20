/// 푸시 재동의 배너 "나중에" 시각 보관 — 도메인 규칙(7일 억제)의 저장소 부분.
/// SuggestionStore(버퍼 추천)와 같은 SharedPreferences 패턴.
library;

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/push_consent_banner.dart';

class PushBannerStore {
  /// 저장 실패 — 다음 세션에 배너가 한 번 더 뜰 뿐, 흐름을 막지 않는다
  Future<void> writeDismissedAt(DateTime now) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(pushBannerDismissedAtKey, now.toIso8601String());
    } catch (_) {
      // 조용히 무시
    }
  }

  Future<String?> readDismissedAt() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(pushBannerDismissedAtKey);
    } catch (_) {
      return null;
    }
  }
}
