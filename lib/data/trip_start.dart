/// 하차 알림 트립 시작 — 시작 시점 위치 1회를 붙여 보낸다 (API.md §9-2 "중간 시작").
///
/// 출발지를 이미 지나 **탄 상태**로 시작하면 탑승역 전광판에는 유저 뒤에 오는 열차만 있어
/// 서버가 뒤차를 잡았다(2026-09-24 오너 제보). 좌표를 같이 보내면 서버가 "지금 있는 역"에서
/// 타고 있는 열차를 찾는다.
///
/// **위치 권한이 없으면 시작하지 않는다** (오너 결정 2026-09-30) — 측위 래퍼가
/// [TripLocationPermissionRequired]를 던지므로 아래 함수들은 서버를 부르지 않고 그대로 전파한다.
/// 화면은 이 예외를 받아 안내 시트(`showTripLocationRequiredSheet`)를 띄운다.
/// 권한이 있는데 측위만 실패한 경우는 좌표 없이 시작한다 (지하에서 시작 버튼을 죽이지 않는다).
///
/// 화면마다 측위를 복사하지 않도록 시작 경로는 전부 여기를 지난다 (CLAUDE.md 레이어 규칙).
library;

import '../domain/journey.dart';
import '../platform/location.dart';
import 'api.dart';

/// 측위 주입 지점 — 기본은 실제 1회 측위(`requestTripFix`, 권한 게이트 포함).
/// 위젯 테스트는 geolocator 플러그인이 없어 채널 응답을 기다리다 멈추므로, `api`를 mock으로
/// 바꾸는 것과 같은 방식으로 여기를 갈아끼운다 (`tripFixProvider = () async => null`
/// = "권한은 있고 측위만 실패", 권한 거부를 보려면 여기서 예외를 던진다)
Future<TripFix?> Function() tripFixProvider = requestTripFix;

/// 권한 게이트 주입 지점 — 화면이 시작 전에 부르는 확인(`ensureTripLocationOrGuide`)이 쓴다.
/// 위젯 테스트는 플러그인이 없어 항상 거부로 떨어지므로 여기를 허용으로 고정한다
/// (`tripLocationGate = () async => TripLocationPermission.granted`)
Future<TripLocationPermission> Function() tripLocationGate =
    ensureTripLocationPermission;

/// 저장 여정 트립 시작 (§9-2)
Future<TripStart> startJourneyTrip(String journeyId) async =>
    api.startTrip(journeyId, at: await tripFixProvider());

/// 1회성(여정 비귀속) 트립 시작 (§9-2, FR-708)
Future<TripStart> startQuickTrip(List<JourneyLeg> legs) async =>
    api.startTripWithLegs(legs, at: await tripFixProvider());

/// 환승 후 다음 구간 재개 (§9-3) — 늦게 눌러도 탄 열차를 잡도록 같은 규칙
Future<TripStatus> advanceTrip(String tripId) async =>
    api.advanceTripLeg(tripId, at: await tripFixProvider());

/// 다시 잡기 (§9-3) — 서버가 내가 탄 열차가 아닌 차량을 추적할 때. 위치가 특히 중요하다:
/// 이미 몇 정거장 갔으니 탑승역 전광판으로는 다시 잡을 수 없다 (오너 요청 2026-09-30)
Future<TripStatus> reIdentifyTrip(String tripId) async =>
    api.reIdentifyTrip(tripId, at: await tripFixProvider());
