import 'package:catch_my_ride/domain/models.dart';
import 'package:catch_my_ride/ui/live_view_screen.dart';
import 'package:catch_my_ride/ui/design/theme.dart';
import 'package:catch_my_ride/ui/design/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// TODO 2026-09-09 회색 비활성 규칙 검증:
// 회색은 "시간 정보 없음"에만 — 못 타는 차(시간 있음)는 노선명 활성 색 + 주황 시간.

Arrival _arrival({
  required String routeName,
  required int? seconds,
  required bool boardable,
  required ArrivalStatus status,
}) => Arrival(
  stopDisplayName: '여의도환승센터',
  routeName: routeName,
  secondsToArrival: seconds,
  remainingStops: null,
  isExpress: null,
  boardable: boardable,
  status: status,
  rawMessage: null,
);

Color _textColor(WidgetTester tester, String text) =>
    tester.widget<Text>(find.text(text)).style!.color!;

void main() {
  testWidgets('회색 비활성은 시간 정보 없음에만 — 못 타는 차는 활성 노선명 + 주황 시간', (tester) async {
    final response = ArrivalsResponse(
      fetchedAt: DateTime(2026, 9, 9, 8).toIso8601String(),
      realtimeAvailable: true,
      walkMinutes: 8,
      arrivals: [
        _arrival(
          routeName: '720',
          seconds: 600,
          boardable: true,
          status: ArrivalStatus.relaxed,
        ),
        _arrival(
          routeName: '261',
          seconds: 120,
          boardable: false,
          status: ArrivalStatus.missed,
        ),
        _arrival(
          routeName: '5615',
          seconds: null,
          boardable: false,
          status: ArrivalStatus.missed,
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: Scaffold(
          body: LiveViewScreen(
            response: response,
            stale: false,
            todayFeedback: null,
            onSubmitFeedback: (_) {},
          ),
        ),
      ),
    );

    // 탑승 가능: 활성 노선명 + 세이지 그린 시간
    expect(_textColor(tester, '720'), AppColors.light.ink);
    expect(_textColor(tester, '10분'), AppColors.light.primaryStrong);

    // 못 타는 차(시간 있음): 노선명은 활성 색 유지, 시간은 뮤트 암버 — 지나간 차로 오해 방지
    expect(_textColor(tester, '261'), AppColors.light.ink);
    expect(_textColor(tester, '2분'), AppColors.light.cautionStrong);

    // 시간 정보 없음: 여기에만 회색 비활성
    expect(_textColor(tester, '5615'), AppColors.light.inkFaint);
    expect(_textColor(tester, '정보 없음'), AppColors.light.inkFaint);

    // 상태 문구는 색상 외 수단으로 그대로 전달 (NFR-06)
    expect(find.text('다음 차를 노리세요'), findsNWidgets(2));
  });

  group('푸시 재동의 배너 (미니앱 2026-09-14 이식)', () {
    final response = ArrivalsResponse(
      fetchedAt: DateTime(2026, 9, 14, 8).toIso8601String(),
      realtimeAvailable: true,
      walkMinutes: 8,
      arrivals: [
        _arrival(
          routeName: '720',
          seconds: 600,
          boardable: true,
          status: ArrivalStatus.relaxed,
        ),
      ],
    );

    Future<void> pump(
      WidgetTester tester, {
      required PushBannerState state,
      VoidCallback? onEnable,
      VoidCallback? onDismiss,
    }) {
      return tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(Brightness.light),
          home: Scaffold(
            body: LiveViewScreen(
              response: response,
              stale: false,
              todayFeedback: null,
              onSubmitFeedback: (_) {},
              pushBanner: state,
              onEnablePush: onEnable,
              onDismissPushBanner: onDismiss,
            ),
          ),
        ),
      );
    }

    testWidgets('hidden이면 배너가 없다', (tester) async {
      await pump(tester, state: PushBannerState.hidden);
      expect(find.text('출발 알림이 꺼져 있어요'), findsNothing);
    });

    testWidgets('visible — "알림 켜기"·"나중에"가 콜백을 부른다', (tester) async {
      var enabled = 0;
      var dismissed = 0;
      await pump(
        tester,
        state: PushBannerState.visible,
        onEnable: () => enabled++,
        onDismiss: () => dismissed++,
      );
      expect(find.text('출발 알림이 꺼져 있어요'), findsOneWidget);
      await tester.tap(find.text('알림 켜기'));
      await tester.tap(find.text('나중에'));
      expect(enabled, 1);
      expect(dismissed, 1);
    });

    testWidgets('enabled — 확인 문구로 바뀐다', (tester) async {
      await pump(tester, state: PushBannerState.enabled);
      expect(find.text('출발 알림이 꺼져 있어요'), findsNothing);
      expect(find.textContaining('출발 알림을 켰어요'), findsOneWidget);
    });
  });
}
