import 'package:catch_my_ride/data/api.dart';
import 'package:catch_my_ride/data/mock_api.dart';
import 'package:catch_my_ride/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('놓치지마 탭에서 경로가 없으면 온보딩 시작 안내를 보여준다', (tester) async {
    SharedPreferences.setMockInitialValues({});
    api = MockNochijimaApi(); // 테스트는 실서버를 부르지 않는다
    await tester.pumpWidget(const CatchMyRideApp());
    // mock API의 첫 listCommuteRoutes 응답을 기다린다
    await tester.pumpAndSettle();

    // 라이브 뷰 본편은 놓치지마 탭에 있다 (첫 탭은 메인 요약 자리)
    await tester.tap(find.text('놓치지마'));
    await tester.pumpAndSettle();

    expect(find.textContaining('통근 설정부터 시작해요'), findsOneWidget);
    expect(find.text('설정 시작하기'), findsOneWidget);
  });
}
