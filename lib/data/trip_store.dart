/// 진행 중 트립 id 보관 — 서버 계약(§9)에 "내 활성 트립 조회"가 없으므로 클라이언트가
/// 기억한다 (이어보기·메인 요약 카드용). 서버와 어긋나면 getTrip 404를 받아 정리된다.
/// 여정 id도 같이 보관한다 — LOST 화면 "처음부터 다시 추적" 진입점(같은 여정 재시작)용.
/// 1회성 트립(FR-708)은 여정이 없으므로 구간(legs) 스냅숏을 대신 보관한다 — 같은 구간
/// 재시작·DONE 화면 "이 경로 저장하기"가 이 값을 쓴다.
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/journey.dart';

const String activeTripIdKey = 'catch-my-ride/active-trip-id';
const String activeTripJourneyIdKey = 'catch-my-ride/active-trip-journey-id';
const String activeTripLegsKey = 'catch-my-ride/active-trip-legs';

class TripStore {
  /// 저장 실패 — 이어보기 카드가 안 뜰 뿐, 트립 자체(서버 추적·푸시)는 계속된다.
  /// [journeyId]와 [legs]는 둘 중 하나만 — 저장 여정 트립은 id, 1회성 트립은 구간 스냅숏
  Future<void> write(
    String tripId, {
    String? journeyId,
    List<JourneyLeg>? legs,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(activeTripIdKey, tripId);
      if (journeyId == null) {
        await prefs.remove(activeTripJourneyIdKey);
      } else {
        await prefs.setString(activeTripJourneyIdKey, journeyId);
      }
      if (legs == null) {
        await prefs.remove(activeTripLegsKey);
      } else {
        await prefs.setString(
          activeTripLegsKey,
          jsonEncode([for (final leg in legs) leg.toJson()]),
        );
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

  /// 보관 중인 트립의 여정 id — 없으면 null (푸시 딥링크만으로 연 트립·1회성 트립 등)
  Future<String?> readJourneyId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(activeTripJourneyIdKey);
    } catch (_) {
      return null;
    }
  }

  /// 보관 중인 1회성 트립의 구간 스냅숏 — 없거나 깨졌으면 null
  Future<List<JourneyLeg>?> readLegs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(activeTripLegsKey);
      if (raw == null) {
        return null;
      }
      final decoded = jsonDecode(raw) as List<dynamic>;
      return [
        for (final item in decoded)
          JourneyLeg.fromJson(item as Map<String, dynamic>),
      ];
    } catch (_) {
      return null;
    }
  }

  Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(activeTripIdKey);
      await prefs.remove(activeTripJourneyIdKey);
      await prefs.remove(activeTripLegsKey);
    } catch (_) {
      // 조용히 무시
    }
  }
}
