import 'package:catch_my_ride/data/api.dart';
import 'package:catch_my_ride/data/mock_api.dart';
import 'package:catch_my_ride/domain/models.dart';
import 'package:catch_my_ride/main.dart';
import 'package:catch_my_ride/ui/onboarding_page.dart';
import 'package:catch_my_ride/ui/root_shell.dart';
import 'package:catch_my_ride/data/trip_start.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// mock에 경로 하나를 미리 심는다 — "이미 설정한 사용자" 시나리오용
Future<void> seedRoute() {
  return api.createCommuteRoute(
    const CommuteRouteRequest(
      label: '출근',
      enabled: true,
      setting: CommuteSetting(
        home: GeoPoint(latitude: 37.5665, longitude: 126.978),
        stops: [
          CommuteStop(
            type: StopType.seoulBus,
            stopId: '12345',
            displayName: '테스트 정류장',
            routes: ['146'],
          ),
        ],
        walkMinutes: 5,
        notificationMode: NotificationMode.fixed,
        fixedDepartureTime: '08:20',
        commuteWindow: null,
        bufferMinutes: 3,
        activeDays: [DayOfWeek.mon, DayOfWeek.tue],
      ),
    ),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    api = MockNochijimaApi(); // 테스트는 실서버를 부르지 않는다
    tripFixProvider = () async => null; // 테스트엔 geolocator 플러그인이 없다
  });

  testWidgets('첫 실행에 경로가 없으면 바로 온보딩으로 들어간다', (tester) async {
    await tester.pumpWidget(const CatchMyRideApp());
    await tester.pumpAndSettle();

    expect(find.byType(OnboardingPage), findsOneWidget);
  });

  testWidgets('온보딩에서 뒤로 나오면 루트 셸로 진입한다', (tester) async {
    await tester.pumpWidget(const CatchMyRideApp());
    await tester.pumpAndSettle();

    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();

    expect(find.byType(RootShell), findsOneWidget);
    expect(find.text('아직 통근 설정이 없어요'), findsOneWidget);
  });

  testWidgets('경로가 이미 있으면 온보딩 없이 루트 셸로 들어간다', (tester) async {
    await seedRoute();

    await tester.pumpWidget(const CatchMyRideApp());
    await tester.pumpAndSettle();

    expect(find.byType(OnboardingPage), findsNothing);
    expect(find.byType(RootShell), findsOneWidget);
  });
}
