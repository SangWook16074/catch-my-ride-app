/// 진행 중 트립 id 보관 — 서버 계약(§9)에 "내 활성 트립 조회"가 없으므로 클라이언트가
/// 기억한다 (이어보기·메인 요약 카드용). 서버와 어긋나면 getTrip 404를 받아 정리된다.
library;

import 'package:shared_preferences/shared_preferences.dart';

const String activeTripIdKey = 'catch-my-ride/active-trip-id';

class TripStore {
  /// 저장 실패 — 이어보기 카드가 안 뜰 뿐, 트립 자체(서버 추적·푸시)는 계속된다
  Future<void> write(String tripId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(activeTripIdKey, tripId);
    } catch (_) {
      // 조용히 무시 (suggestion_store와 동일한 태도)
    }
  }

  Future<String?> read() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(activeTripIdKey);
    } catch (_) {
      return null;
    }
  }

  Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(activeTripIdKey);
    } catch (_) {
      // 조용히 무시
    }
  }
}
