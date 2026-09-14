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

    // 폴링마다 1정거장 전진: 3 → 2(TRACKING) → 1(ARRIVING) → 0(TRANSFER)
    var status = await api.getTrip(start.tripId);
    expect(status.phase, TripPhase.tracking);
    expect(status.remainingStops, 2);
    expect(status.eventStop, '당산');

    status = await api.getTrip(start.tripId);
    expect(status.phase, TripPhase.arriving);

    status = await api.getTrip(start.tripId);
    expect(status.phase, TripPhase.transfer);

    // 환승 수동 재개(FR-703) → 두 번째 구간
    status = await api.advanceTripLeg(start.tripId);
    expect(status.phase, TripPhase.tracking);
    expect(status.legIndex, 1);
    expect(status.eventStop, '강남');

    // 마지막 구간 완주 → DONE
    await api.getTrip(start.tripId);
    await api.getTrip(start.tripId);
    status = await api.getTrip(start.tripId);
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
}
