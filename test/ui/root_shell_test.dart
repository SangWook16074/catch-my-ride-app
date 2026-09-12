import 'package:catch_my_ride/data/api.dart';
import 'package:catch_my_ride/data/mock_api.dart';
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

  testWidgets('바텀 네비게이션에 4개 탭이 있다', (tester) async {
    await pumpShell(tester);

    expect(find.byType(NavigationBar), findsOneWidget);
    for (final label in ['메인', '놓치지마', '새로운 기능', '내정보']) {
      expect(find.text(label), findsOneWidget);
    }
  });

  testWidgets('탭을 누르면 해당 화면으로 이동한다', (tester) async {
    await pumpShell(tester);

    await tester.tap(find.text('내정보'));
    await tester.pumpAndSettle();
    expect(find.text('내 정보 화면을 준비하고 있어요'), findsOneWidget);

    await tester.tap(find.text('새로운 기능'));
    await tester.pumpAndSettle();
    expect(find.text('새로운 기능이 들어올 자리예요'), findsOneWidget);

    // 메인으로 복귀 — 라이브 뷰(경로 없음 = 온보딩 안내)가 다시 보인다
    await tester.tap(find.text('메인'));
    await tester.pumpAndSettle();
    expect(find.textContaining('통근 설정부터 시작해요'), findsOneWidget);
  });
}
