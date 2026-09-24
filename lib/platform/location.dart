/// 집 위치 1회 등록(FR-101)용 원샷 위치 조회 — geolocator 플러그인 래퍼.
/// CLAUDE.md 레이어 규칙: 네이티브 브리지(플러그인)는 platform/에서만 만진다.
///
/// 권한 단계는 측위 타임아웃 밖이다 (TODO 2026-09-09, 미니앱 실측 사고):
/// 권한 요청까지 측위 타임아웃에 포함시키면 유저가 동의창을 읽는 동안 시간이 다 흘러
/// **최초 사용자의 첫 시도가 무조건 실패**한다. 권한 확인 → (필요 시) 다이얼로그 →
/// 허용된 뒤에만 측위를 시작하고, 동의창을 읽는 시간에는 제한을 두지 않는다.
///
/// 측위 전략(미니앱 onboarding.tsx 2026-09-10 개정과 동일): 고정밀(GPS)과 저정밀(와이파이·기지국)을
/// **처음부터 동시에** 요청하고, 3초까지는 고정밀을 우선한다. 고정밀이 먼저 실패하면 즉시
/// 저정밀 결과로 넘어가고, 둘 다 실패할 때만 실패다(전체 12초 상한). 기존 "고정밀 3초 → 저정밀
/// 강등" 순차 방식은 실내에서 3초를 그냥 버렸고, 고정밀이 3초 안에 에러로 죽으면 저정밀 시도 없이
/// 전면 실패했다(실내 실패율 주범). 일시 오류는 1회 자동 재시도하되, 권한 거부·타임아웃은
/// 재시도하지 않는다 — 지도 확인 + 주소 검색 폴백(FR-101 보완)이 있어 수백 m 오차는
/// 유저가 즉시 교정한다.
library;

import 'dart:async';
import 'dart:developer' as developer;

import 'package:geolocator/geolocator.dart';

import '../domain/journey.dart';
import '../domain/models.dart';

/// 권한 거부 — 위저드가 주소 등록 폴백을 안내한다
class LocationPermissionDenied implements Exception {}

/// 이 시간까지는 고정밀을 우선한다(정확도 우선) — 그 안에 오면 저정밀보다 고정밀 채택
const Duration _highAccuracyWait = Duration(seconds: 3);

/// 전체 측위 상한 — 양쪽 요청 모두 이 시간에 타임아웃된다
const Duration _totalWait = Duration(seconds: 12);
const int _retries = 1;

/// 트립 시작 측위 상한 — 이 시간을 넘기면 위치 없이 시작한다 (시작을 막지 않는다)
const Duration _tripFixWait = Duration(seconds: 5);

/// 최근 고정을 대신 쓸 수 있는 나이 상한 — 더 낡으면 다른 역을 가리킬 수 있다
const Duration _lastKnownMaxAge = Duration(minutes: 2);
const Duration _retryDelay = Duration(seconds: 1);

/// 하차 알림 시작 1회 측위 (API.md §9-2 "중간 시작") — **실패는 null**, 시작을 막지 않는다.
///
/// 집 등록(requestCurrentLocation)과 목적이 다르다: 여기선 정확도보다 속도다. 시작 버튼을 누른
/// 유저를 측위 때문에 기다리게 하지 않으므로 상한이 [_tripFixWait]고, 실패하면 최근 고정(2분 이내)만
/// 대신 쓴다 — 더 낡은 위치는 엉뚱한 역을 고르게 하므로 버린다 (NFR-03).
/// 상시 추적이 아니라 시작 시점 1회다 (NFR-05).
Future<TripFix?> requestTripFix() async {
  try {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return null; // 거부 — 위치 없이 시작 (서버가 기존 동작으로 강등)
    }
    final position = await Geolocator.getCurrentPosition(
      locationSettings: LocationSettings(
        accuracy: LocationAccuracy.medium, // 역 하나를 가리면 충분 — 실내에서 고정밀은 자주 실패한다
        timeLimit: _tripFixWait,
      ),
    ).timeout(_tripFixWait);
    return _fixOf(position);
  } catch (_) {
    // 지하 측위 실패·권한 회수·플러그인 부재(테스트) — 최근 고정으로 한 번 더, 그래도 없으면 null
    return _recentFix();
  }
}

Future<TripFix?> _recentFix() async {
  try {
    final last = await Geolocator.getLastKnownPosition();
    if (last == null) {
      return null;
    }
    final age = DateTime.now().difference(last.timestamp);
    return age <= _lastKnownMaxAge ? _fixOf(last) : null;
  } catch (_) {
    return null;
  }
}

TripFix _fixOf(Position position) => TripFix(
  point: GeoPoint(
    latitude: position.latitude,
    longitude: position.longitude,
  ),
  accuracyMeters: position.accuracy > 0 ? position.accuracy : null,
);

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
  Future<GeoPoint> once(LocationAccuracy accuracy) async {
    final position = await Geolocator.getCurrentPosition(
      locationSettings: LocationSettings(
        accuracy: accuracy,
        timeLimit: _totalWait,
      ),
    );
    return GeoPoint(
      latitude: position.latitude,
      longitude: position.longitude,
    );
  }

  final startedAt = DateTime.now();
  // 고정밀·저정밀을 동시에 시작 — 저정밀을 "고정밀 3초 초과 후"에야 시작하면 실내에서 3초를 버린다
  final high = once(LocationAccuracy.high);
  final balanced = once(LocationAccuracy.medium);
  // 둘 다 실패할 때만 실패 — 한쪽 에러가 전체를 죽이지 않는다 (Future.any는 에러도 전파해 부적합)
  final winner = _firstSuccess([high, balanced]);

  // 3초까지는 고정밀 우선. 고정밀이 먼저 "실패"하면 null이 즉시 돌아와 대기 시간을 낭비하지 않는다
  final highEarly = await Future.any<GeoPoint?>([
    high.then<GeoPoint?>((point) => point, onError: (Object _) => null),
    Future<GeoPoint?>.delayed(_highAccuracyWait, () => null),
  ]);
  final point = highEarly ?? await winner;
  developer.log(
    'location fixed in ${DateTime.now().difference(startedAt).inMilliseconds}ms '
    '(source: ${highEarly != null ? 'high' : 'first-success'})',
    name: 'location',
  );
  return point;
}

/// 먼저 성공하는 쪽 — 전부 실패할 때만 마지막 에러로 실패한다
Future<T> _firstSuccess<T>(List<Future<T>> futures) {
  final completer = Completer<T>();
  var failures = 0;
  for (final future in futures) {
    future.then(
      (value) {
        if (!completer.isCompleted) {
          completer.complete(value);
        }
      },
      onError: (Object error, StackTrace stack) {
        failures += 1;
        if (failures == futures.length && !completer.isCompleted) {
          completer.completeError(error, stack);
        }
      },
    );
  }
  return completer.future;
}
