/// 집 위치 1회 등록(FR-101)용 원샷 위치 조회 — geolocator 플러그인 래퍼.
/// CLAUDE.md 레이어 규칙: 네이티브 브리지(플러그인)는 platform/에서만 만진다.
///
/// 권한 단계는 측위 타임아웃 밖이다 (TODO 2026-09-09, 미니앱 실측 사고):
/// 권한 요청까지 측위 타임아웃에 포함시키면 유저가 동의창을 읽는 동안 시간이 다 흘러
/// **최초 사용자의 첫 시도가 무조건 실패**한다. 권한 확인 → (필요 시) 다이얼로그 →
/// 허용된 뒤에만 측위를 시작하고, 동의창을 읽는 시간에는 제한을 두지 않는다.
///
/// 측위 전략(미니앱 onboarding.tsx와 동일 취지): 고정밀은 3초까지만 기다리고 늦으면
/// 저정밀로 강등(전체 12초 상한). 일시 오류는 1회 자동 재시도하되, 권한 거부·타임아웃은
/// 재시도하지 않는다 — 지도 확인 + 주소 검색 폴백(FR-101 보완)이 있어 수백 m 오차는
/// 유저가 즉시 교정한다.
library;

import 'dart:async';

import 'package:geolocator/geolocator.dart';

import '../domain/models.dart';

/// 권한 거부 — 위저드가 주소 등록 폴백을 안내한다
class LocationPermissionDenied implements Exception {}

const Duration _highAccuracyWait = Duration(seconds: 3);
const Duration _fallbackWait = Duration(seconds: 9); // 합쳐서 전체 12초 상한
const int _retries = 1;
const Duration _retryDelay = Duration(seconds: 1);

Future<GeoPoint> requestCurrentLocation() async {
  // 1) 권한 — 측위와 분리, 시간 제한 없음
  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }
  if (permission == LocationPermission.denied ||
      permission == LocationPermission.deniedForever) {
    throw LocationPermissionDenied();
  }

  // 2) 측위 — 여기서부터만 타임아웃이 걸린다
  for (var attempt = 0; ; attempt++) {
    try {
      return await _read();
    } on TimeoutException {
      rethrow; // 타임아웃은 재시도 금지 — "무한 대기"를 만들지 않는다
    } on PermissionDeniedException {
      throw LocationPermissionDenied(); // 측위 중 권한 회수 — 재시도 금지
    } catch (_) {
      // 일시 오류(신호 순간 끊김 등)만 1회 자동 재시도
      if (attempt >= _retries) {
        rethrow;
      }
      await Future<void>.delayed(_retryDelay);
    }
  }
}

Future<GeoPoint> _read() async {
  Future<GeoPoint> once(LocationAccuracy accuracy, Duration timeLimit) async {
    final position = await Geolocator.getCurrentPosition(
      locationSettings: LocationSettings(
        accuracy: accuracy,
        timeLimit: timeLimit,
      ),
    );
    return GeoPoint(
      latitude: position.latitude,
      longitude: position.longitude,
    );
  }

  try {
    return await once(LocationAccuracy.high, _highAccuracyWait);
  } on TimeoutException {
    // 고정밀이 상한을 넘김 — 저정밀로 강등해 한 번 더 시도한다
    return once(LocationAccuracy.medium, _fallbackWait);
  }
}
