import 'package:catch_my_ride/data/api.dart';
import 'package:catch_my_ride/data/mock_api.dart';
import 'package:catch_my_ride/ui/design/components/glass_nav_bar.dart';
import 'package:catch_my_ride/ui/design/theme.dart';
import 'package:catch_my_ride/ui/root_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<void> pumpShell(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    api = MockNochijimaApi(); // 테스트는 실서버를 부르지 않는다
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: const RootShell(),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 페이지 안 텍스트와 겹칠 수 있으니 탭은 네비게이션 바 안에서만 찾아 누른다
  Finder navLabel(String label) => find.descendant(
    of: find.byType(GlassNavBar),
    matching: find.text(label),
  );

  testWidgets('바텀 네비게이션에 4개 탭이 있다', (tester) async {
    await pumpShell(tester);

    expect(find.byType(GlassNavBar), findsOneWidget);
    for (final label in ['메인', '출발 알림', '하차 알림', '내정보']) {
      expect(navLabel(label), findsOneWidget);
    }
  });

  testWidgets('첫 탭 메인에 출발 알림·하차 알림 두 섹션의 진입점이 있다', (tester) async {
    await pumpShell(tester);

    // 섹션마다 전체 보기 하나씩
    expect(find.text('전체 보기'), findsNWidgets(2));
    // 경로가 없는 상태 — 출발 알림 요약 카드는 설정 유도를 보여준다
    expect(find.text('아직 통근 설정이 없어요'), findsOneWidget);
    // 여정이 없는 상태 — 하차 알림 카드는 여정 만들기 유도를 보여준다
    expect(find.text('아직 여정이 없어요'), findsOneWidget);
  });

  testWidgets('요약 카드의 설정 시작하기를 누르면 출발 알림 탭으로 전환된다', (tester) async {
    await pumpShell(tester);

    await tester.tap(find.text('설정 시작하기'));
    await tester.pumpAndSettle();

    expect(find.textContaining('통근 설정부터 시작해요'), findsOneWidget);
  });

  testWidgets('출발 알림 전체 보기를 누르면 출발 알림 탭으로 전환된다', (tester) async {
    await pumpShell(tester);

    await tester.tap(find.text('전체 보기').first);
    await tester.pumpAndSettle();

    expect(find.textContaining('통근 설정부터 시작해요'), findsOneWidget);
  });

  testWidgets('하차 알림 전체 보기를 누르면 하차 알림 탭으로 전환된다', (tester) async {
    await pumpShell(tester);

    await tester.tap(find.text('전체 보기').last);
    await tester.pumpAndSettle();

    expect(find.textContaining('놓치지 않게'), findsOneWidget);
  });

  testWidgets('탭을 누르면 해당 화면으로 이동한다', (tester) async {
    await pumpShell(tester);

    await tester.tap(navLabel('내정보'));
    await tester.pumpAndSettle();
    expect(find.text('통근 경로'), findsOneWidget);

    await tester.tap(navLabel('하차 알림'));
    await tester.pumpAndSettle();
    expect(find.textContaining('놓치지 않게'), findsOneWidget);

    // 출발 알림 = 라이브 뷰 본편 (경로 없음 = 온보딩 안내)
    await tester.tap(navLabel('출발 알림'));
    await tester.pumpAndSettle();
    expect(find.textContaining('통근 설정부터 시작해요'), findsOneWidget);
  });
}
