import 'package:catch_my_ride/data/active_trip.dart';
import 'package:catch_my_ride/data/api.dart';
import 'package:catch_my_ride/data/mock_api.dart';
import 'package:catch_my_ride/domain/journey.dart';
import 'package:catch_my_ride/ui/design/theme.dart';
import 'package:catch_my_ride/ui/main_page.dart';
import 'package:catch_my_ride/ui/trip_page.dart';
import 'package:catch_my_ride/data/trip_start.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _request = JourneyRequest(
  label: '회사',
  repeatDays: [],
  legs: [
    JourneyLeg(line: '9호선 급행', boardStop: '여의도', alightStop: '당산'),
  ],
);

Future<void> pumpMain(WidgetTester tester, {VoidCallback? onOpenJourney}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(Brightness.light),
      home: Scaffold(
        body: MainPage(
          active: true,
          onOpenCatch: () {},
          onOpenJourney: onOpenJourney ?? () {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    activeTrip = ActiveTripController();
    SharedPreferences.setMockInitialValues({});
    api = MockNochijimaApi();
    tripFixProvider = () async => null; // 테스트엔 geolocator 플러그인이 없다
  });

  testWidgets('여정이 있으면 메인 하차 알림 섹션에 원탭 시작 카드가 보인다', (tester) async {
    await api.createJourney(_request);

    await pumpMain(tester);

    expect(find.text('하차 알림'), findsOneWidget); // 섹션 헤더
    expect(find.text('회사'), findsOneWidget);
    expect(find.text('여의도 → 당산'), findsOneWidget);
    expect(find.text('시작'), findsOneWidget);
  });

  testWidgets('메인의 시작을 누르면 트립이 시작되고 트립 화면이 열린다', (tester) async {
    await api.createJourney(_request);

    await pumpMain(tester);
    await tester.tap(find.text('시작'));
    await tester.pumpAndSettle(); // 트립 화면 폴링 — 2정거장

    expect(find.byType(TripPage), findsOneWidget);
    expect(find.text('2정거장 남았어요'), findsOneWidget);
  });

  testWidgets('여정이 없으면 여정 만들기 유도 카드가 보이고, 카드 탭은 하차 알림 탭으로 보낸다', (
    tester,
  ) async {
    var opened = false;
    await pumpMain(tester, onOpenJourney: () => opened = true);

    expect(find.text('아직 여정이 없어요'), findsOneWidget);
    expect(find.text('여정 만들기'), findsOneWidget);

    // 섹션 헤더의 전체 보기(두 번째)가 하차 알림 탭 전환 콜백을 부른다
    await tester.tap(find.text('전체 보기').last);
    expect(opened, isTrue);
  });
}
