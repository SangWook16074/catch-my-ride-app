import 'package:catch_my_ride/data/api.dart';
import 'package:catch_my_ride/data/mock_api.dart';
import 'package:catch_my_ride/data/trip_store.dart';
import 'package:catch_my_ride/domain/journey.dart';
import 'package:catch_my_ride/ui/design/theme.dart';
import 'package:catch_my_ride/ui/main_page.dart';
import 'package:catch_my_ride/ui/trip_page.dart';
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

void main() {
  testWidgets('진행 중 트립이 있으면 메인에 요약 카드가 보이고 탭하면 트립 화면이 열린다', (
    tester,
  ) async {
    api = MockNochijimaApi();
    final journey = await api.createJourney(_request);
    final start = await api.startTrip(journey.id);
    // 트립 시작 시 로컬 보관되는 값과 동일한 상태를 만든다
    SharedPreferences.setMockInitialValues({activeTripIdKey: start.tripId});

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: Scaffold(
          body: MainPage(
            active: true,
            onOpenCatch: () {},
            onOpenJourney: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle(); // 확인 폴링 — 열차 특정 전(위치 확인 중)

    expect(find.text('하차 알림 진행 중'), findsOneWidget);
    expect(find.text('당산행 위치 확인 중'), findsOneWidget);

    await tester.tap(find.text('하차 알림 진행 중'));
    await tester.pumpAndSettle(); // 트립 화면 폴링 — 2정거장

    expect(find.byType(TripPage), findsOneWidget);
    expect(find.text('2정거장 남았어요'), findsOneWidget);
  });
}
