import 'package:catch_my_ride/data/recent_routes_store.dart';
import 'package:catch_my_ride/domain/journey.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _legs = [JourneyLeg(line: '9호선 급행', boardStop: '여의도', alightStop: '당산')];

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('1회성 길을 올리고, 여정으로 저장하면 지운다 (FR-708)', () async {
    final store = RecentRoutesStore();
    await store.push(_legs, now: DateTime(2026, 9, 21));
    expect((await store.list()).single.legs, _legs);

    await store.remove(_legs);
    expect(await store.list(), isEmpty);
  });

  test('깨진 값은 빈 목록', () async {
    SharedPreferences.setMockInitialValues({recentRoutesKey: '{'});
    expect(await RecentRoutesStore().list(), isEmpty);
  });
}
