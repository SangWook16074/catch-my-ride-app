/// 하차 알림 트립 시작 — 시작 시점 위치 1회를 붙여 보낸다 (API.md §9-2 "중간 시작").
///
/// 출발지를 이미 지나 **탄 상태**로 시작하면 탑승역 전광판에는 유저 뒤에 오는 열차만 있어
/// 서버가 뒤차를 잡았다(2026-09-24 오너 제보). 좌표를 같이 보내면 서버가 "지금 있는 역"에서
/// 타고 있는 열차를 찾는다. 측위 실패·권한 거부는 좌표 없이 그대로 시작한다 — 시작을 막지 않는다.
///
/// 화면마다 측위를 복사하지 않도록 시작 경로는 전부 여기를 지난다 (CLAUDE.md 레이어 규칙).
library;

import '../domain/journey.dart';
import '../platform/location.dart';
import 'api.dart';

/// 측위 주입 지점 — 기본은 실제 1회 측위(`requestTripFix`).
/// 위젯 테스트는 geolocator 플러그인이 없어 채널 응답을 기다리다 멈추므로, `api`를 mock으로
/// 바꾸는 것과 같은 방식으로 여기를 갈아끼운다 (`tripFixProvider = () async => null`)
Future<TripFix?> Function() tripFixProvider = requestTripFix;

/// 저장 여정 트립 시작 (§9-2)
Future<TripStart> startJourneyTrip(String journeyId) async =>
    api.startTrip(journeyId, at: await tripFixProvider());

/// 1회성(여정 비귀속) 트립 시작 (§9-2, FR-708)
Future<TripStart> startQuickTrip(List<JourneyLeg> legs) async =>
    api.startTripWithLegs(legs, at: await tripFixProvider());

/// 환승 후 다음 구간 재개 (§9-3) — 늦게 눌러도 탄 열차를 잡도록 같은 규칙
Future<TripStatus> advanceTrip(String tripId) async =>
    api.advanceTripLeg(tripId, at: await tripFixProvider());
