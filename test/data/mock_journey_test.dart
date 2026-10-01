import 'package:catch_my_ride/data/mock_api.dart';
import 'package:catch_my_ride/domain/journey.dart';
import 'package:catch_my_ride/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

const _request = JourneyRequest(
  label: '회사',
  repeatDays: [DayOfWeek.mon],
  legs: [
    JourneyLeg(line: '9호선 급행', boardStop: '여의도', alightStop: '당산'),
    JourneyLeg(line: '2호선', boardStop: '당산', alightStop: '강남'),
  ],
);

void main() {
  late MockNochijimaApi api;

  setUp(() => api = MockNochijimaApi());

  test('여정 생성 → 목록 → 삭제 (§9-1)', () async {
    final journey = await api.createJourney(_request);
    expect(journey.label, '회사');
    expect(journey.lastUsedAt, isNull);

    expect(await api.listJourneys(), hasLength(1));

    await api.deleteJourney(journey.id);
    expect(await api.listJourneys(), isEmpty);
  });

  test('라벨 중복·11개째는 400', () async {
    await api.createJourney(_request);
    expect(
      () => api.createJourney(_request),
      throwsA(
        isA<ApiException>().having((e) => e.code, 'code', 'INVALID_REQUEST'),
      ),
    );
    for (var i = 1; i < maxJourneys; i++) {
      await api.createJourney(
        JourneyRequest(label: '여정$i', repeatDays: const [], legs: _request.legs),
      );
    }
    expect(
      () => api.createJourney(
        JourneyRequest(label: '초과', repeatDays: const [], legs: _request.legs),
      ),
      throwsA(isA<ApiException>()),
    );
  });

  test('트립 수명주기 — 시작 → 전진 → 환승 → 재개 → 도착 (§9-2/9-3)', () async {
    final journey = await api.createJourney(_request);
    final start = await api.startTrip(journey.id);

    // lastUsedAt이 갱신돼 히스토리 정렬 키가 된다
    final listed = await api.listJourneys();
    expect(listed.first.lastUsedAt, isNotNull);

    // 첫 폴링 = 열차 특정 전(위치 확인 중, §9-3) → 이후 1정거장씩:
    // null → 2(TRACKING) → 1(ARRIVING) → 0(TRANSFER)
    var status = await api.getTrip(start.tripId);
    expect(status.phase, TripPhase.tracking);
    expect(status.remainingStops, isNull);

    status = await api.getTrip(start.tripId);
    expect(status.phase, TripPhase.tracking);
    expect(status.remainingStops, 2);
    expect(status.eventStop, '당산');

    status = await api.getTrip(start.tripId);
    expect(status.phase, TripPhase.arriving);

    status = await api.getTrip(start.tripId);
    expect(status.phase, TripPhase.transfer);

    // 환승 수동 재개(FR-703) → 두 번째 구간 — 다시 특정 전부터
    status = await api.advanceTripLeg(start.tripId);
    expect(status.phase, TripPhase.tracking);
    expect(status.legIndex, 1);
    expect(status.eventStop, '강남');
    expect(status.remainingStops, isNull);

    // 마지막 구간 완주 → DONE
    await api.getTrip(start.tripId); // 특정
    await api.getTrip(start.tripId); // 2
    await api.getTrip(start.tripId); // 1
    status = await api.getTrip(start.tripId); // 0
    expect(status.phase, TripPhase.done);

    await api.endTrip(start.tripId);
    expect(() => api.getTrip(start.tripId), throwsA(isA<ApiException>()));
    // 종료는 멱등
    await api.endTrip(start.tripId);
  });

  test('동시 트립은 1개 — 두 번째 시작은 400', () async {
    final journey = await api.createJourney(_request);
    await api.startTrip(journey.id);
    expect(
      () => api.startTrip(journey.id),
      throwsA(
        isA<ApiException>().having(
          (e) => e.message,
          'message',
          contains('진행 중인 트립'),
        ),
      ),
    );
  });

  test('TRANSFER가 아니면 next-leg는 400', () async {
    final journey = await api.createJourney(_request);
    final start = await api.startTrip(journey.id);
    expect(
      () => api.advanceTripLeg(start.tripId),
      throwsA(isA<ApiException>()),
    );
  });

  test('여정 삭제 시 진행 중 트립도 정리된다', () async {
    final journey = await api.createJourney(_request);
    final start = await api.startTrip(journey.id);
    await api.deleteJourney(journey.id);
    expect(() => api.getTrip(start.tripId), throwsA(isA<ApiException>()));
  });

  // API.md §9-3 v0.10 — 구간 바꾸기
  test('구간 바꾸기 — 범위·동일 값·한도·DONE 규칙 (§9-3 v0.10)', () async {
    final journey = await api.createJourney(_request);
    final start = await api.startTrip(journey.id);

    // 범위 밖
    expect(() => api.switchLeg(start.tripId, 2), throwsA(isA<ApiException>()));
    expect(() => api.switchLeg(start.tripId, -1), throwsA(isA<ApiException>()));
    // 현재 구간과 같은 값
    expect(() => api.switchLeg(start.tripId, 0), throwsA(isA<ApiException>()));

    // 뒤 구간으로 전환 — 초기화된 상태(위치 확인 중)
    var status = await api.switchLeg(start.tripId, 1);
    expect(status.phase, TripPhase.tracking);
    expect(status.legIndex, 1);
    expect(status.remainingStops, isNull);
    expect(status.eventStop, '강남');

    // 앞 구간으로도 바꿀 수 있다
    status = await api.switchLeg(start.tripId, 0);
    expect(status.legIndex, 0);

    // 한도(3회) — 지금까지 2회 썼으니 1회만 더 가능
    await api.switchLeg(start.tripId, 1);
    expect(
      () => api.switchLeg(start.tripId, 0),
      throwsA(
        isA<ApiException>().having(
          (e) => e.message,
          'message',
          contains('다시 시작'),
        ),
      ),
    );
  });

  test('구간 바꾸기 — TRANSFER에서는 허용, DONE이면 400 (§9-3 v0.10)', () async {
    final journey = await api.createJourney(_request);
    final start = await api.startTrip(journey.id);
    // TRANSFER까지 전진
    await api.getTrip(start.tripId); // 특정
    await api.getTrip(start.tripId); // 2
    await api.getTrip(start.tripId); // 1(ARRIVING)
    final transferStatus = await api.getTrip(start.tripId); // 0(TRANSFER)
    expect(transferStatus.phase, TripPhase.transfer);

    // TRANSFER에서도 구간을 바꿀 수 있다 — TRANSFER 중엔 legIndex가 아직 완료한 구간(0)을
    // 가리키므로, 현재 값과 달라야 하는 규칙상 고를 수 있는 건 1번뿐이다
    final status = await api.switchLeg(start.tripId, 1);
    expect(status.legIndex, 1);
    expect(status.phase, TripPhase.tracking); // 초기화된 상태(위치 확인 중)부터

    // 마지막 구간까지 완주해 DONE으로 만든다
    await api.getTrip(start.tripId); // 특정
    await api.getTrip(start.tripId); // 2
    await api.getTrip(start.tripId); // 1
    final doneStatus = await api.getTrip(start.tripId); // 0 → 마지막 구간이라 DONE
    expect(doneStatus.phase, TripPhase.done);
    expect(() => api.switchLeg(start.tripId, 0), throwsA(isA<ApiException>()));
  });

  // API.md §9-3 v0.11 — "내렸어요" + 되돌리기
  test('내렸어요 — remainingStops > 2면 400 (§9-3 v0.11)', () async {
    final journey = await api.createJourney(_request);
    final start = await api.startTrip(journey.id);
    await api.getTrip(start.tripId); // 특정(remaining=3, mock 3정거장 고정)
    expect(() => api.alightTrip(start.tripId), throwsA(isA<ApiException>()));
  });

  test('내렸어요 — 환승 구간이면 곧바로 다음 구간을 시작한다 (§9-3 v0.11)', () async {
    final journey = await api.createJourney(_request);
    final start = await api.startTrip(journey.id);
    await api.getTrip(start.tripId); // 특정
    await api.getTrip(start.tripId); // remaining=2 → 이제 내렸어요 가능

    final status = await api.alightTrip(start.tripId);
    expect(status.phase, TripPhase.tracking); // TRANSFER를 거치지 않는다
    expect(status.legIndex, 1);
    expect(status.remainingStops, isNull); // 새 구간 — 위치 확인 중부터
    expect(status.undoableUntil, isNotNull);
  });

  test('내렸어요 — 마지막 구간이면 DONE, 되돌리면 다시 TRACKING (§9-3 v0.11)', () async {
    final start = await api.startTripWithLegs(const [
      JourneyLeg(line: '3호선', boardStop: '충무로', alightStop: '교대'),
    ]);
    await api.getTrip(start.tripId); // 특정
    await api.getTrip(start.tripId); // remaining=2

    final alighted = await api.alightTrip(start.tripId);
    expect(alighted.phase, TripPhase.done);
    expect(alighted.undoableUntil, isNotNull);

    final undone = await api.undoAlight(start.tripId);
    expect(undone.phase, TripPhase.tracking);
    expect(undone.remainingStops, 2); // 하차 직전 그대로 복원
    expect(undone.undoableUntil, isNull);
  });

  test('되돌리기 — 스냅숏 없으면 400, 한도(2회) 초과도 400 (§9-3 v0.11)', () async {
    final journey = await api.createJourney(_request);
    final start = await api.startTrip(journey.id);

    // 아직 한 번도 내리지 않았다 — 되돌릴 게 없다
    expect(() => api.undoAlight(start.tripId), throwsA(isA<ApiException>()));

    await api.getTrip(start.tripId); // 특정
    await api.getTrip(start.tripId); // remaining=2
    await api.alightTrip(start.tripId); // 1회 하차 → 다음 구간
    await api.undoAlight(start.tripId); // 1회 되돌리기 — 되돌아온 구간도 remaining=2

    await api.alightTrip(start.tripId); // 다시 하차
    await api.undoAlight(start.tripId); // 2회째 되돌리기 — 한도

    await api.alightTrip(start.tripId); // 세 번째 하차
    expect(
      () => api.undoAlight(start.tripId),
      throwsA(isA<ApiException>()), // 3회째 되돌리기는 한도 초과
    );
  });

  test('1회성 트립(§9-2 POST /api/v1/trips) — 여정 목록은 그대로, 동시 1개·검증은 동일', () async {
    final start = await api.startTripWithLegs(_request.legs);
    expect(await api.listJourneys(), isEmpty); // 몰래 여정을 만들지 않는다 (FR-708)

    final status = await api.getTrip(start.tripId);
    expect(status.phase, TripPhase.tracking);
    expect(status.eventStop, '당산');

    // 동시 트립 1개 — 저장 여정 시작도 막힌다
    final journey = await api.createJourney(_request);
    expect(
      () => api.startTrip(journey.id),
      throwsA(isA<ApiException>().having((e) => e.message, 'message', contains(start.tripId))),
    );

    await api.endTrip(start.tripId);
    expect(
      () => api.startTripWithLegs(const []),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', 'INVALID_REQUEST')),
    );
  });
}
