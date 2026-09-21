/// 최근 간 길(1회성 트립 구간) 로컬 보관 — FR-708. 저장하지 않은 길만 남기고, 여정으로
/// 저장하면 지운다. 서버·여정 목록에는 흔적을 남기지 않는다 (10개 제한·히스토리 오염 방지)
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/journey.dart';

const String recentRoutesKey = 'catch-my-ride/recent-routes';

class RecentRoutesStore {
  Future<List<RecentRoute>> list() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(recentRoutesKey);
      if (raw == null) {
        return const [];
      }
      return [
        for (final item in jsonDecode(raw) as List<dynamic>)
          RecentRoute.fromJson(item as Map<String, dynamic>),
      ];
    } catch (_) {
      return const [];
    }
  }

  /// 1회성 시작 시 맨 앞에 올린다 — 같은 길은 하나로, 최대 5개
  Future<void> push(List<JourneyLeg> legs, {DateTime? now}) async {
    final routes = pushRecentRoute(await list(), legs, now ?? DateTime.now());
    await _write(routes);
  }

  /// 여정으로 저장했거나 유저가 지운 길
  Future<void> remove(List<JourneyLeg> legs) async {
    final routes = [
      for (final route in await list())
        if (!sameLegs(route.legs, legs)) route,
    ];
    await _write(routes);
  }

  Future<void> _write(List<RecentRoute> routes) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        recentRoutesKey,
        jsonEncode([for (final route in routes) route.toJson()]),
      );
    } catch (_) {
      // 조용히 무시 — 최근 간 길이 안 남을 뿐, 트립에는 영향 없음
    }
  }
}
