import 'package:catch_my_ride/data/active_trip.dart';
import 'package:catch_my_ride/data/api.dart';
import 'package:catch_my_ride/data/mock_api.dart';
import 'package:catch_my_ride/domain/models.dart';
import 'package:catch_my_ride/ui/components/commute_grass.dart';
import 'package:catch_my_ride/ui/design/theme.dart';
import 'package:catch_my_ride/ui/main_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 메인 통근 기록(잔디) 섹션 — 뎁스 없이 전체 노출 (오너 결정 2026-09-19)
Future<void> pumpMain(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(Brightness.light),
      home: Scaffold(
        body: MainPage(active: true, onOpenCatch: () {}, onOpenJourney: () {}),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

String _dateKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

void main() {
  setUp(() {
    activeTrip = ActiveTripController();
    SharedPreferences.setMockInitialValues({});
    api = MockNochijimaApi(); // 테스트는 실서버를 부르지 않는다
  });

  testWidgets('기록이 없으면 잔디 대신 시작 안내를 보여준다', (tester) async {
    await pumpMain(tester);
    await tester.scrollUntilVisible(find.text('통근 기록'), 200);

    expect(find.text('아직 통근 기록이 없어요'), findsOneWidget);
    expect(find.byType(CommuteGrass), findsNothing);
  });

  testWidgets('피드백이 쌓이면 요약 한 줄과 잔디 그리드를 그대로 노출한다', (tester) async {
    await api.postBoardingFeedback(
      BoardingFeedbackRequest(
        result: BoardingResult.boarded,
        notifiedDate: _dateKey(DateTime.now()),
      ),
    );
    await pumpMain(tester);
    await tester.scrollUntilVisible(find.text('통근 기록'), 200);

    expect(find.textContaining('회 탑승 · 연속'), findsOneWidget);
    expect(find.byType(CommuteGrass), findsOneWidget);
    // 잔디 범례 — 성공 중심 톤이지만 상태 구분은 읽을 수 있어야 한다
    expect(find.text('탔어요'), findsOneWidget);
    expect(find.text('놓쳤어요'), findsOneWidget);
    expect(find.text('기록 없음'), findsOneWidget);
  });
}
