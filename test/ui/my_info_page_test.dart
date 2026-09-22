import 'package:catch_my_ride/data/active_trip.dart';
import 'package:catch_my_ride/data/api.dart';
import 'package:catch_my_ride/data/mock_api.dart';
import 'package:catch_my_ride/domain/journey.dart';
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
    activeTrip = ActiveTripController();
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

  testWidgets('경로·여정·알림·앱 정보 섹션을 보여준다 (통근 기록은 메인으로 이동, 2026-09-19)', (
    tester,
  ) async {
    await pumpPage(tester);

    expect(find.text('나의 통근'), findsNothing);
    expect(find.text('통근 기록'), findsNothing);
    expect(find.text('통근 경로'), findsOneWidget);
    expect(find.text('아직 경로가 없어요'), findsOneWidget);
    expect(find.text('+ 경로 추가'), findsOneWidget);
    expect(find.text('여정 관리'), findsOneWidget);
    expect(find.text('+ 여정 만들기'), findsOneWidget);

    // 아래 섹션은 테스트 뷰포트 밖 — 스크롤해서 확인 (ListView는 lazy)
    await tester.scrollUntilVisible(find.text('버전'), 200);
    expect(find.text('푸시 알림'), findsOneWidget);
    expect(find.text('알림 정책'), findsOneWidget);
    expect(find.text('버전'), findsOneWidget);
  });

  testWidgets('등록된 여정을 여정 관리에 보여주고 삭제할 수 있다', (tester) async {
    await api.createJourney(
      const JourneyRequest(
        label: '회사',
        repeatDays: [],
        legs: [
          JourneyLeg(line: '9호선 급행', boardStop: '여의도', alightStop: '당산'),
        ],
      ),
    );
    await pumpPage(tester);

    expect(find.text('회사'), findsOneWidget);
    expect(find.text('여의도 → 당산'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.text('삭제'));
    await tester.pumpAndSettle();

    expect(find.text('회사'), findsNothing);
    expect(find.text('아직 여정이 없어요'), findsOneWidget);
  });

  testWidgets('알림 정책을 누르면 발송 규칙 안내 시트가 열린다', (tester) async {
    await pumpPage(tester);

    await tester.scrollUntilVisible(find.text('알림 정책'), 200);
    await tester.tap(find.text('알림 정책'));
    await tester.pumpAndSettle();

    expect(find.text('알림, 꼭 필요한 만큼만 보내요'), findsOneWidget);
    expect(find.textContaining('출근 1번에 최대 2번'), findsWidgets);
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
