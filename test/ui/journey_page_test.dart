import 'package:catch_my_ride/data/api.dart';
import 'package:catch_my_ride/data/mock_api.dart';
import 'package:catch_my_ride/domain/journey.dart';
import 'package:catch_my_ride/domain/models.dart';
import 'package:catch_my_ride/ui/design/theme.dart';
import 'package:catch_my_ride/ui/journey_create_page.dart';
import 'package:catch_my_ride/ui/journey_page.dart';
import 'package:catch_my_ride/ui/trip_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _request = JourneyRequest(
  label: '회사',
  repeatDays: [DayOfWeek.mon, DayOfWeek.fri],
  legs: [
    JourneyLeg(line: '9호선 급행', boardStop: '여의도', alightStop: '당산'),
  ],
);

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
        home: const Scaffold(body: JourneyPage(active: true)),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('여정이 없으면 안내와 만들기 버튼을 보여준다', (tester) async {
    await pumpPage(tester);

    expect(find.text('아직 여정이 없어요'), findsOneWidget);
    expect(find.text('+ 여정 만들기'), findsOneWidget);
  });

  testWidgets('여정 만들기를 누르면 생성 화면이 열린다', (tester) async {
    await pumpPage(tester);

    await tester.tap(find.text('+ 여정 만들기'));
    await tester.pumpAndSettle();

    expect(find.byType(JourneyCreatePage), findsOneWidget);
    expect(find.text('저장'), findsOneWidget);
  });

  testWidgets('저장된 여정을 경로 요약·반복 요일과 함께 보여준다', (tester) async {
    await api.createJourney(_request);
    await pumpPage(tester);

    expect(find.text('회사'), findsOneWidget);
    expect(find.text('여의도 → 당산'), findsOneWidget);
    expect(find.text('반복: 월·금'), findsOneWidget);
    expect(find.text('시작'), findsOneWidget);
  });

  testWidgets('시작을 누르면 트립 화면에서 카운트다운이 보인다', (tester) async {
    await api.createJourney(_request);
    await pumpPage(tester);

    await tester.tap(find.text('시작'));
    await tester.pumpAndSettle();

    // mock은 폴링 1회당 1정거장 전진 — 첫 조회 후 2정거장
    expect(find.byType(TripPage), findsOneWidget);
    expect(find.text('당산에서 내려요'), findsOneWidget);
    expect(find.text('2정거장 남았어요'), findsOneWidget);

    // 20초 폴링 2회 → 다음 역(ARRIVING) → 하차(단일 구간 = DONE)
    await tester.pump(const Duration(seconds: 20));
    expect(find.text('다음 역이에요!'), findsOneWidget);

    await tester.pump(const Duration(seconds: 20));
    await tester.pump();
    expect(find.text('목적지에 도착했어요'), findsOneWidget);

    await tester.tap(find.text('완료'));
    await tester.pumpAndSettle();
    expect(find.byType(TripPage), findsNothing);
  });

  testWidgets('트립을 끝내지 않고 나오면 이어보기 카드가 보인다', (tester) async {
    await api.createJourney(_request);
    await pumpPage(tester);

    await tester.tap(find.text('시작'));
    await tester.pumpAndSettle(); // TripPage 첫 폴링 — 2정거장

    await tester.pageBack();
    await tester.pumpAndSettle(); // 목록 복귀 — 이어보기 확인 폴링으로 1정거장

    expect(find.text('진행 중인 트립이 있어요'), findsOneWidget);
    expect(find.text('당산까지 1정거장'), findsOneWidget);

    await tester.tap(find.text('이어보기'));
    await tester.pumpAndSettle(); // 단일 구간 — 다음 폴링에서 도착

    expect(find.byType(TripPage), findsOneWidget);
    expect(find.text('목적지에 도착했어요'), findsOneWidget);
  });
}
