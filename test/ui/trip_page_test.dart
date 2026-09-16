import 'package:catch_my_ride/data/api.dart';
import 'package:catch_my_ride/data/mock_api.dart';
import 'package:catch_my_ride/domain/journey.dart';
import 'package:catch_my_ride/ui/design/theme.dart';
import 'package:catch_my_ride/ui/trip_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// getTrip만 고정 상태로 바꿔치기 — 진행 화면의 표시 규칙(§9-3)을 상태별로 검증한다
class _FixedTripApi extends MockNochijimaApi {
  _FixedTripApi(this.status);

  final TripStatus status;

  @override
  Future<TripStatus> getTrip(String tripId) async => status;
}

TripStatus _tracking({int? remainingStops, String? currentStop}) => TripStatus(
  phase: TripPhase.tracking,
  legIndex: 0,
  remainingStops: remainingStops,
  currentStop: currentStop,
  eventStop: '당산',
  realtimeAvailable: true,
  fetchedAt: DateTime.now().toIso8601String(),
);

Future<void> _pumpTripPage(WidgetTester tester, TripStatus status) async {
  SharedPreferences.setMockInitialValues({});
  api = _FixedTripApi(status);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(Brightness.light),
      home: const TripPage(tripId: 'trip-1'),
    ),
  );
  await tester.pump(); // 첫 폴링 반영
}

void main() {
  testWidgets('특정 전이라도 서버가 현재 역을 주면 위치 확인 중 대신 부근으로 보여준다', (tester) async {
    // §9-3 2026-09-16 개정 — 노선 전체 위치로 단일 후보를 목격하면 remaining 없이 currentStop이 온다
    await _pumpTripPage(
      tester,
      _tracking(remainingStops: null, currentStop: '샛강'),
    );

    expect(find.text('현재 샛강 부근'), findsOneWidget);
    expect(find.text('위치 확인 중이에요…'), findsNothing);
    expect(find.text('하차역에 가까워지면 남은 정거장을 알려드려요'), findsOneWidget);

    await tester.pumpWidget(const SizedBox()); // 폴링 타이머 정리
  });

  testWidgets('현재 역도 모르면 위치 확인 중으로 아는 척하지 않는다', (tester) async {
    await _pumpTripPage(
      tester,
      _tracking(remainingStops: null, currentStop: null),
    );

    expect(find.text('위치 확인 중이에요…'), findsOneWidget);
    expect(find.text('탑승한 열차를 찾고 있어요. 곧 남은 정거장을 알려드려요'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('카운트다운 중에는 남은 정거장과 현재 역을 함께 보여준다', (tester) async {
    await _pumpTripPage(
      tester,
      _tracking(remainingStops: 4, currentStop: '노량진'),
    );

    expect(find.text('4정거장 남았어요'), findsOneWidget);
    expect(find.text('현재 노량진 부근'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });
}
