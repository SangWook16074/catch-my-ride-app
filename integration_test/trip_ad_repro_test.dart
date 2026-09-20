// 광고 전체 화면 덮음 재현용 — 시뮬레이터에서 실제 AdMob SDK로 하차 알림 → 트립
// 화면까지 자동 주행하고, 바깥에서 simctl 스크린샷으로 관측한다.
// 실행: flutter test integration_test/trip_ad_repro_test.dart -d <sim> --dart-define=USE_MOCK=true
import 'package:catch_my_ride/data/api.dart';
import 'package:catch_my_ride/domain/journey.dart';
import 'package:catch_my_ride/platform/ads.dart';
import 'package:catch_my_ride/ui/design/theme.dart';
import 'package:catch_my_ride/ui/root_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// 실시간으로 [ms]만큼 프레임을 돌린다 — pumpAndSettle은 반복 애니메이션·폴링
/// 타이머 때문에 끝나지 않으므로 쓰지 않는다
Future<void> live(WidgetTester tester, int ms) async {
  final end = DateTime.now().add(Duration(milliseconds: ms));
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('하차 알림 시작 → 트립 화면 광고 관측', (tester) async {
    // 온보딩(StartupGate)을 우회해 루트 셸을 바로 띄운다 — 광고 재현에는 셸이면 충분
    await Ads.init();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: const RootShell(),
      ),
    );
    await live(tester, 3000);

    await api.createJourney(
      const JourneyRequest(
        label: '재현용 여정',
        repeatDays: [],
        legs: [
          JourneyLeg(line: '2호선', boardStop: '강남', alightStop: '시청'),
        ],
      ),
    );

    await tester.tap(find.byIcon(Icons.subway_outlined));
    await live(tester, 2500);

    await tester.tap(find.text('시작').first);
    await live(tester, 2000);
    expect(find.text('트립 종료'), findsOneWidget);

    // 트립 화면을 40초 유지 — 광고 로드·갱신을 기다리며 바깥에서 스크린샷
    await live(tester, 40000);
  });
}
