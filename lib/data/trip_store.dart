/// 진행 중 트립 id 보관 — 서버 계약(§9)에 "내 활성 트립 조회"가 없으므로 클라이언트가
/// 기억한다 (이어보기·메인 요약 카드용). 서버와 어긋나면 getTrip 404를 받아 정리된다.
/// 여정 id도 같이 보관한다 — LOST 화면 "처음부터 다시 추적" 진입점(같은 여정 재시작)용.
library;

import 'package:shared_preferences/shared_preferences.dart';

const String activeTripIdKey = 'catch-my-ride/active-trip-id';
const String activeTripJourneyIdKey = 'catch-my-ride/active-trip-journey-id';

class TripStore {
  /// 저장 실패 — 이어보기 카드가 안 뜰 뿐, 트립 자체(서버 추적·푸시)는 계속된다
  Future<void> write(String tripId, {String? journeyId}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(activeTripIdKey, tripId);
      if (journeyId == null) {
        await prefs.remove(activeTripJourneyIdKey);
      } else {
        await prefs.setString(activeTripJourneyIdKey, journeyId);
      }
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

  /// 보관 중인 트립의 여정 id — 없으면 null (푸시 딥링크만으로 연 트립 등)
  Future<String?> readJourneyId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(activeTripJourneyIdKey);
    } catch (_) {
      return null;
    }
  }

  Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(activeTripIdKey);
      await prefs.remove(activeTripJourneyIdKey);
    } catch (_) {
      // 조용히 무시
    }
  }
}
