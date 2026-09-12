import 'package:catch_my_ride/data/api.dart';
import 'package:catch_my_ride/data/mock_api.dart';
import 'package:catch_my_ride/domain/models.dart';
import 'package:catch_my_ride/ui/design/theme.dart';
import 'package:catch_my_ride/ui/my_info_page.dart';
import 'package:catch_my_ride/ui/onboarding_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  });

  Future<void> pumpPage(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        // 실제 앱에서는 루트 셸 Scaffold 안에 있다 — 같은 조건으로 감싼다
        home: const Scaffold(body: MyInfoPage(active: true)),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('경로 관리·알림·앱 정보 섹션을 보여준다', (tester) async {
    await pumpPage(tester);

    expect(find.text('통근 경로'), findsOneWidget);
    expect(find.text('아직 경로가 없어요'), findsOneWidget);
    expect(find.text('+ 경로 추가'), findsOneWidget);
    expect(find.text('푸시 알림'), findsOneWidget);
    expect(find.text('버전'), findsOneWidget);
  });

  testWidgets('등록된 경로를 라벨·요약과 함께 보여준다', (tester) async {
    await seedRoute();
    await pumpPage(tester);

    expect(find.text('출근'), findsOneWidget);
    expect(find.text('정류장 1 · 정시 오전 8:20'), findsOneWidget);
    expect(find.text('아직 경로가 없어요'), findsNothing);
  });

  testWidgets('경로 행을 누르면 해당 경로 수정 온보딩이 열린다', (tester) async {
    await seedRoute();
    await pumpPage(tester);

    await tester.tap(find.text('출근'));
    await tester.pumpAndSettle();

    expect(find.byType(OnboardingPage), findsOneWidget);
  });

  testWidgets('경로 추가를 누르면 생성 온보딩이 열린다', (tester) async {
    await pumpPage(tester);

    await tester.tap(find.text('+ 경로 추가'));
    await tester.pumpAndSettle();

    expect(find.byType(OnboardingPage), findsOneWidget);
  });
}
