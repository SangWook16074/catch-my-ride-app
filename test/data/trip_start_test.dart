import 'package:catch_my_ride/data/api.dart';
import 'package:catch_my_ride/data/mock_api.dart';
import 'package:catch_my_ride/data/trip_start.dart';
import 'package:catch_my_ride/domain/journey.dart';
import 'package:catch_my_ride/platform/location.dart';
import 'package:flutter_test/flutter_test.dart';

/// 하차 알림 시작 funnel 계약 (API.md §9-2, 오너 결정 2026-09-30):
/// **위치 권한이 없으면 서버를 부르지 않는다.** 좌표 없는 시작은 서버가 탑승역 전광판의
/// 뒤차를 잡는다는 뜻이라, 되는 척하지 않고 막는다. 화면은 예외를 받아 안내 시트를 띄운다.
void main() {
  const legs = [
    JourneyLeg(line: '4호선', boardStop: '수유', alightStop: '충무로'),
  ];

  setUp(() {
    api = _ForbiddenApi();
  });

  tearDown(() {
    tripFixProvider = requestTripFix;
  });

  void denyPermission(TripLocationPermission permission) {
    tripFixProvider = () async => throw TripLocationPermissionRequired(permission);
  }

  test('저장 여정 시작 — 권한 없으면 서버 호출 없이 막는다', () async {
    denyPermission(TripLocationPermission.denied);

    await expectLater(
      startJourneyTrip('j-1'),
      throwsA(isA<TripLocationPermissionRequired>()),
    );
  });

  test('1회성 시작(FR-708)도 같은 게이트를 지난다', () async {
    denyPermission(TripLocationPermission.blocked);

    await expectLater(
      startQuickTrip(legs),
      throwsA(
        isA<TripLocationPermissionRequired>().having(
          (error) => error.permission,
          'permission',
          TripLocationPermission.blocked,
        ),
      ),
    );
  });

  test('환승 재개도 막는다 — 새 구간에서 뒤차를 잡지 않게', () async {
    // 트립은 서버에서 TRANSFER로 남아 있으므로, 권한을 허용하고 다시 누르면 그대로 이어진다
    denyPermission(TripLocationPermission.serviceOff);

    await expectLater(
      advanceTrip('t-1'),
      throwsA(isA<TripLocationPermissionRequired>()),
    );
  });

  test('권한이 있고 측위만 실패하면 좌표 없이 시작한다 — 지하에서 시작을 죽이지 않는다', () async {
    api = MockNochijimaApi();
    tripFixProvider = () async => null;

    final start = await startQuickTrip(legs);

    expect(start.tripId, isNotEmpty);
  });
}

/// 호출되면 실패하는 API — "서버를 부르지 않는다"를 구조적으로 증명한다
class _ForbiddenApi extends MockNochijimaApi {
  @override
  Future<TripStart> startTrip(String journeyId, {TripFix? at}) async =>
      fail('권한 없이 트립을 시작하려 했다');

  @override
  Future<TripStart> startTripWithLegs(
    List<JourneyLeg> legs, {
    TripFix? at,
  }) async => fail('권한 없이 1회성 트립을 시작하려 했다');

  @override
  Future<TripStatus> advanceTripLeg(String tripId, {TripFix? at}) async =>
      fail('권한 없이 환승 재개를 하려 했다');
}
