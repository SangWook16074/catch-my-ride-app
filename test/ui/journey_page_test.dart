import 'package:catch_my_ride/data/api.dart';
import 'package:catch_my_ride/data/mock_api.dart';
import 'package:catch_my_ride/data/recent_routes_store.dart';
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

  testWidgets('여정이 없으면 가운데 안내 — 바로 시작이 주 버튼, 저장은 보조', (tester) async {
    // 놓치지마 탭 초기 화면과 같은 가운데 타이틀·서브타이틀·버튼 (디자인 통일 2026-09-16).
    // 1회성이 기본 동선 (오너 화면 재구성 2026-09-21)
    await pumpPage(tester);

    expect(find.text('내릴 역, 놓치지 않게\n알려드릴게요'), findsOneWidget);
    expect(find.text('바로 시작하기'), findsOneWidget);
    expect(find.text('경로 생성하기'), findsOneWidget);
  });

  testWidgets('경로 생성하기를 누르면 생성 화면이 열린다', (tester) async {
    await pumpPage(tester);

    await tester.tap(find.text('경로 생성하기'));
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
    // 위치 확인 중 화면은 구간 스트립 애니메이션이 계속 돌아 pumpAndSettle이 끝나지 않는다
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // 첫 폴링 = 열차 특정 전 — 카운트는 몰라도 노선 목격 위치는 보여준다 (§9-3 2026-09-16 개정,
    // mock은 탑승역으로 대신한다)
    expect(find.byType(TripPage), findsOneWidget);
    expect(find.text('당산에서 내려요'), findsOneWidget);
    expect(find.text('현재 여의도 부근'), findsOneWidget);
    // 구간 스트립 — 탑승역·노선으로 이동 맥락을 채운다
    expect(find.text('여의도'), findsOneWidget);
    expect(find.text('9호선 급행'), findsOneWidget);

    // 20초 폴링마다 전진: 2정거장 → 다음 역(ARRIVING) → 하차(단일 구간 = DONE)
    await tester.pump(const Duration(seconds: 20));
    expect(find.text('2정거장 남았어요'), findsOneWidget);
    // 특정 후엔 현재 위치 역명 (§9-3 currentStop — mock은 탑승역으로 대신한다)
    expect(find.text('현재 여의도 부근'), findsOneWidget);

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
    // TripPage 첫 폴링 — 위치 확인 중 (스트립 애니메이션 때문에 pumpAndSettle 불가)
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    await tester.pageBack();
    await tester.pumpAndSettle(); // 목록 복귀 — 이어보기 확인 폴링으로 2정거장

    expect(find.text('진행 중인 트립이 있어요'), findsOneWidget);
    expect(find.text('당산까지 2정거장'), findsOneWidget);

    await tester.tap(find.text('이어보기'));
    await tester.pumpAndSettle(); // 다음 폴링 — 직전 역(ARRIVING)

    expect(find.byType(TripPage), findsOneWidget);
    expect(find.text('다음 역이에요!'), findsOneWidget);
  });

  testWidgets('바로 시작 — 구간만 받고, 저장 스위치를 켜면 이름·요일이 펼쳐진다', (tester) async {
    // FR-708 — 저장은 입력 화면 안 스위치 하나 (오너 화면 재구성 2026-09-21)
    await pumpPage(tester);
    await tester.tap(find.text('바로 시작하기'));
    await tester.pumpAndSettle();

    expect(find.byType(JourneyCreatePage), findsOneWidget);
    expect(find.text('어디까지 가세요?'), findsOneWidget);
    expect(find.text('추적 시작'), findsOneWidget);
    expect(find.text('경로 저장하기'), findsOneWidget);
    expect(find.text('이름'), findsNothing);
    expect(find.text('요일 반복 (선택)'), findsNothing);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(find.text('이름'), findsOneWidget);
    expect(find.text('요일 반복 (선택)'), findsOneWidget);
    expect(find.text('저장하고 추적 시작'), findsOneWidget);

    // 구간 없이 시작하면 저장 여정과 같은 검증 메시지
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    await tester.tap(find.text('추적 시작'));
    await tester.pump();
    expect(find.text('구간을 1개 이상 추가해주세요'), findsOneWidget);
  });

  testWidgets('저장 안 한 1회성 길은 최근 간 길로 남고, 저장하면 여정 목록으로 올라간다', (tester) async {
    // FR-708 → FR-702 전환 루프 — 최근 간 길 카드에서 원탭 저장
    await RecentRoutesStore().push(_request.legs, now: DateTime.now());
    await pumpPage(tester);

    expect(find.text('최근 간 길'), findsOneWidget);
    expect(find.text('여의도 → 당산'), findsOneWidget);
    expect(find.text('다시 시작'), findsOneWidget);
    expect(find.text('저장'), findsOneWidget);

    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();
    expect(find.text('경로를 저장할까요?'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '병원');
    await tester.tap(find.text('저장').last);
    await tester.pumpAndSettle();

    expect(find.text('저장한 여정'), findsOneWidget);
    expect(find.text('병원'), findsOneWidget);
    expect(find.text('최근 간 길'), findsNothing);
    expect(await RecentRoutesStore().list(), isEmpty);
  });

  testWidgets('여정 목록에서도 하차 알림 시작 영역이 맨 위, 진행 중 트립이 있으면 숨긴다', (tester) async {
    await api.createJourney(_request);
    await pumpPage(tester);
    expect(find.text('하차 알림 시작하기'), findsOneWidget);
    expect(find.text('저장한 여정'), findsOneWidget);
    // 경로 생성은 가운데 FAB(아이콘 + 라벨) (오너 요청 2026-09-21)
    expect(find.byType(FloatingActionButton), findsOneWidget);
    expect(find.text('경로 생성하기'), findsOneWidget);

    await tester.tap(find.text('시작'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    // 트립 화면에서 뒤로 — 진행 중 트립 유지
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('이어보기'), findsOneWidget);
    expect(find.text('하차 알림 시작하기'), findsNothing); // 동시 1개 규칙 (§9-2)
  });
}
