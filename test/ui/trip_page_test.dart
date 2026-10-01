import 'package:catch_my_ride/data/active_trip.dart';
import 'package:catch_my_ride/data/api.dart';
import 'package:catch_my_ride/data/mock_api.dart';
import 'package:catch_my_ride/data/trip_start.dart';
import 'package:catch_my_ride/domain/journey.dart';
import 'package:catch_my_ride/domain/models.dart';
import 'package:catch_my_ride/platform/location.dart';
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

/// 구간 바꾸기·내렸어요·되돌리기(§9-3 v0.10/v0.11) 액션의 결과를 직접 지정하는 fake —
/// 실서버의 좌표 기반 열차 특정 로직을 흉내낼 필요 없이 버튼 동작만 검증한다
class _ScriptedTripApi extends MockNochijimaApi {
  _ScriptedTripApi(this.status);

  TripStatus status;
  TripStatus? nextAfterAlight;
  TripStatus? nextAfterUndo;
  TripStatus? nextAfterSwitch;

  @override
  Future<TripStatus> getTrip(String tripId) async => status;

  @override
  Future<TripStatus> alightTrip(String tripId, {TripFix? at}) async {
    final next = nextAfterAlight;
    if (next == null) {
      throw const ApiException(400, 'INVALID_REQUEST', '아직 하차역에 가까워지지 않았어요');
    }
    status = next;
    return status;
  }

  @override
  Future<TripStatus> undoAlight(String tripId) async {
    final next = nextAfterUndo;
    if (next == null) {
      throw const ApiException(400, 'INVALID_REQUEST', '이미 시간이 지나 되돌릴 수 없어요');
    }
    status = next;
    return status;
  }

  @override
  Future<TripStatus> switchLeg(String tripId, int legIndex, {TripFix? at}) async {
    final next = nextAfterSwitch;
    if (next == null) {
      throw const ApiException(400, 'INVALID_REQUEST', '구간을 바꿀 수 없어요');
    }
    status = next;
    return status;
  }
}

Future<void> _pumpScriptedTripPage(
  WidgetTester tester,
  _ScriptedTripApi scripted, {
  String? journeyId,
  List<JourneyLeg>? legs,
}) async {
  await tester.pumpWidget(const SizedBox());
  SharedPreferences.setMockInitialValues({});
  api = scripted;
  activeTrip = ActiveTripController();
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(Brightness.light),
      home: TripPage(tripId: 'trip-1', journeyId: journeyId, legs: legs),
    ),
  );
  await tester.pump();
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

const _legs = [
  JourneyLeg(line: '9호선 급행', boardStop: '여의도', alightStop: '당산'),
];

TripStatus _phase(TripPhase phase) => TripStatus(
  phase: phase,
  legIndex: 0,
  remainingStops: null,
  currentStop: null,
  eventStop: '당산',
  realtimeAvailable: true,
  fetchedAt: DateTime.now().toIso8601String(),
);

Future<void> _pumpTripPage(
  WidgetTester tester,
  TripStatus status, {
  String? journeyId,
  List<JourneyLeg>? legs,
}) async {
  // 앞 화면의 구독을 먼저 끊는다 — 구독이 사라지면 전역 폴링도 멈춘다
  await tester.pumpWidget(const SizedBox());
  SharedPreferences.setMockInitialValues({});
  api = _FixedTripApi(status);
  // 전역 트립 상태는 테스트마다 새로 — 앞 테스트의 트립을 물려받지 않는다
  activeTrip = ActiveTripController();
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(Brightness.light),
      home: TripPage(tripId: 'trip-1', journeyId: journeyId, legs: legs),
    ),
  );
  await tester.pump(); // 첫 폴링 반영
}

void main() {
  setUp(() {
    // 권한 게이트는 통과 고정, 측위는 null(권한은 있고 좌표만 못 얻은 경우)로 — 이 파일의
    // 새 테스트들은 위치 자체가 아니라 버튼 가시성·액션 호출을 검증한다
    tripLocationGate = () async => TripLocationPermission.granted;
    tripFixProvider = () async => null;
  });

  tearDown(() {
    tripLocationGate = ensureTripLocationPermission;
    tripFixProvider = requestTripFix;
  });

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

  testWidgets('1회성 트립은 추적 중에도 저장할 수 있고, 저장하면 안내로 바뀐다', (tester) async {
    // FR-708 — 1회성 → 재사용(FR-702) 전환 루프. 도착 전에도 저장 (오너 화면 재구성 2026-09-21)
    await _pumpTripPage(tester, _tracking(remainingStops: 3), legs: _legs);

    expect(find.text('3정거장 남았어요'), findsOneWidget);
    expect(find.text('경로 저장하기'), findsOneWidget);

    await tester.tap(find.text('경로 저장하기'));
    await tester.pumpAndSettle();
    expect(find.text('경로를 저장할까요?'), findsOneWidget);
    expect(find.text('여의도 → 당산'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '병원');
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();

    expect(find.text('"병원" 여정으로 저장했어요'), findsOneWidget);
    expect(find.text('경로 저장하기'), findsNothing);
    expect((await api.listJourneys()).single.label, '병원');
    expect((await api.listJourneys()).single.legs, _legs);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('도착 화면에도 저장 제안 — 저장 여정 트립·여정을 모르는 트립엔 없다', (tester) async {
    await _pumpTripPage(tester, _phase(TripPhase.done), legs: _legs);
    expect(find.text('경로 저장하기'), findsOneWidget);
    expect(find.text('완료'), findsOneWidget);

    await _pumpTripPage(tester, _phase(TripPhase.done), journeyId: 'journey-1');
    expect(find.text('경로 저장하기'), findsNothing);

    await _pumpTripPage(tester, _phase(TripPhase.done));
    expect(find.text('경로 저장하기'), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('1회성 트립도 LOST에서 구간 스냅숏으로 처음부터 다시 추적할 수 있다', (tester) async {
    await _pumpTripPage(tester, _phase(TripPhase.lost), legs: _legs);
    expect(find.text('추적이 잠시 끊겼어요'), findsOneWidget);
    expect(find.text('처음부터 다시 추적'), findsOneWidget);

    // 여정도 스냅숏도 모르면(푸시 딥링크 진입) 버튼을 숨긴다
    await _pumpTripPage(tester, _phase(TripPhase.lost));
    expect(find.text('처음부터 다시 추적'), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    '내렸어요는 remainingStops <= 2일 때만 보이고, 되돌리면 아직 안 내렸어요가 사라진다 (§9-3 v0.11)',
    (tester) async {
      const single = [JourneyLeg(line: '3호선', boardStop: '충무로', alightStop: '교대')];
      TripStatus tracking({required int? remainingStops, String? undoableUntil}) =>
          TripStatus(
            phase: TripPhase.tracking,
            legIndex: 0,
            remainingStops: remainingStops,
            currentStop: null,
            eventStop: '교대',
            realtimeAvailable: true,
            fetchedAt: DateTime.now().toIso8601String(),
            undoableUntil: undoableUntil,
          );

      final scripted = _ScriptedTripApi(tracking(remainingStops: 3));
      await _pumpScriptedTripPage(tester, scripted, legs: single);
      // 아직 멀리 있다 — 버튼 없음
      expect(find.text('내렸어요'), findsNothing);

      // 하차역 2정거장 이내로
      scripted.status = tracking(remainingStops: 2);
      await activeTrip.refresh();
      await tester.pump();
      expect(find.text('내렸어요'), findsOneWidget);

      // 마지막 구간 — 내렸어요 → DONE + undoableUntil
      scripted.nextAfterAlight = TripStatus(
        phase: TripPhase.done,
        legIndex: 0,
        remainingStops: 0,
        currentStop: null,
        eventStop: '교대',
        realtimeAvailable: true,
        fetchedAt: DateTime.now().toIso8601String(),
        undoableUntil: DateTime.now().add(const Duration(minutes: 5)).toIso8601String(),
      );
      await tester.tap(find.text('내렸어요'));
      await tester.pumpAndSettle();

      expect(find.text('목적지에 도착했어요'), findsOneWidget);
      expect(find.text('아직 안 내렸어요'), findsOneWidget);

      // 되돌리기 — 직전 구간(remaining=2) 그대로 복원, undoableUntil은 비운다
      scripted.nextAfterUndo = tracking(remainingStops: 2);
      await tester.tap(find.text('아직 안 내렸어요'));
      await tester.pumpAndSettle();

      expect(find.text('2정거장 남았어요'), findsOneWidget);
      expect(find.text('아직 안 내렸어요'), findsNothing);

      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('구간 바꾸기는 구간 2개 이상일 때만 보이고, 고르면 전환한다 (§9-3 v0.10)', (tester) async {
    const legs2 = [
      JourneyLeg(line: '9호선 급행', boardStop: '여의도', alightStop: '당산'),
      JourneyLeg(line: '2호선', boardStop: '당산', alightStop: '강남'),
    ];
    final scripted = _ScriptedTripApi(_tracking(remainingStops: 4));
    await _pumpScriptedTripPage(tester, scripted, legs: legs2);

    expect(find.text('구간 바꾸기'), findsOneWidget);

    scripted.nextAfterSwitch = TripStatus(
      phase: TripPhase.tracking,
      legIndex: 1,
      remainingStops: null,
      currentStop: null,
      eventStop: '강남',
      realtimeAvailable: true,
      fetchedAt: DateTime.now().toIso8601String(),
    );

    await tester.tap(find.text('구간 바꾸기'));
    await tester.pumpAndSettle();
    expect(find.text('여의도 → 당산'), findsOneWidget);
    expect(find.text('당산 → 강남'), findsOneWidget);

    // pumpAndSettle은 못 쓴다 — 새 상태가 위치 확인 중(remainingStops null)이라 RouteStrip의
    // 상시 반복 애니메이션(2400ms 루프)이 떠서 "settle"이 영영 안 끝난다. 시트 닫힘 전환과
    // 상태 반영만큼만 시간을 두고 pump한다
    await tester.tap(find.text('당산 → 강남'));
    await tester.pump(); // 탭 처리·시트 pop 시작
    await tester.pump(const Duration(milliseconds: 300)); // 시트 닫힘 전환 + 상태 반영

    expect(find.text('강남에서 내려요'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('구간이 1개면 구간 바꾸기를 보이지 않는다', (tester) async {
    final scripted = _ScriptedTripApi(_tracking(remainingStops: 4));
    await _pumpScriptedTripPage(tester, scripted, legs: _legs);
    expect(find.text('구간 바꾸기'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('시작 구간 판정(legIndex > 0)이면 1회 안내를 보여준다 (§9-2 v0.10)', (tester) async {
    final scripted = _ScriptedTripApi(
      TripStatus(
        phase: TripPhase.tracking,
        legIndex: 1,
        remainingStops: null,
        currentStop: null,
        eventStop: '강남',
        realtimeAvailable: true,
        fetchedAt: DateTime.now().toIso8601String(),
      ),
    );
    const legs2 = [
      JourneyLeg(line: '9호선 급행', boardStop: '여의도', alightStop: '당산'),
      JourneyLeg(line: '2호선', boardStop: '당산', alightStop: '강남'),
    ];
    await tester.pumpWidget(const SizedBox());
    SharedPreferences.setMockInitialValues({});
    api = scripted;
    activeTrip = ActiveTripController();
    // begin()으로 시작해야 legIndex 안내가 걸린다 (adopt는 안내를 세우지 않는다)
    await activeTrip.begin(
      tripId: 'trip-1',
      label: '회사',
      legs: legs2,
      legIndex: 1,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: TripPage(tripId: 'trip-1', legs: legs2),
      ),
    );
    // pumpAndSettle은 못 쓴다 — remainingStops null(위치 확인 중)이라 RouteStrip의 상시 반복
    // 애니메이션이 떠서 "settle"이 영영 안 끝난다. 첫 프레임(postFrameCallback) + 안내
    // 시트의 전환 애니메이션만큼만 시간을 둔다
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('당산 → 강남 구간부터 안내할게요'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });
}
