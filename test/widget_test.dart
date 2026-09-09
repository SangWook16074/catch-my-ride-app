import 'package:catch_my_ride/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('경로가 없으면 온보딩 시작 안내를 보여준다', (tester) async {
    await tester.pumpWidget(const CatchMyRideApp());
    // mock API의 첫 listCommuteRoutes 응답을 기다린다
    await tester.pumpAndSettle();

    expect(find.textContaining('통근 설정부터 시작해요'), findsOneWidget);
    expect(find.text('설정 시작하기'), findsOneWidget);
  });
}
