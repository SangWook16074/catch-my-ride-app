import 'package:catch_my_ride/data/trip_store.dart';
import 'package:catch_my_ride/domain/journey.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _legs = [
  JourneyLeg(line: '9호선 급행', boardStop: '여의도', alightStop: '당산'),
  JourneyLeg(line: '2호선', boardStop: '당산', alightStop: '강남'),
];

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('1회성 트립은 구간 스냅숏을 보관하고 여정 id는 비운다 (FR-708)', () async {
    final store = TripStore();
    await store.write('trip-1', legs: _legs);

    expect(await store.read(), 'trip-1');
    expect(await store.readJourneyId(), isNull);
    expect(await store.readLegs(), _legs);
  });

  test('저장 여정 트립으로 바꿔 쓰면 이전 스냅숏은 지워진다', () async {
    final store = TripStore();
    await store.write('trip-1', legs: _legs);
    await store.write('trip-2', journeyId: 'journey-1');

    expect(await store.readJourneyId(), 'journey-1');
    expect(await store.readLegs(), isNull);

    await store.clear();
    expect(await store.read(), isNull);
    expect(await store.readLegs(), isNull);
  });

  test('깨진 스냅숏은 null — 화면은 문구만으로 동작한다', () async {
    SharedPreferences.setMockInitialValues({activeTripLegsKey: 'not-json'});
    expect(await TripStore().readLegs(), isNull);
  });
}
