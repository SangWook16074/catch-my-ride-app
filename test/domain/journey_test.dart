import 'package:catch_my_ride/domain/journey.dart';
import 'package:catch_my_ride/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

const _leg = JourneyLeg(line: '9호선 급행', boardStop: '여의도', alightStop: '당산');

JourneyRequest _request({
  String label = '회사',
  List<JourneyLeg> legs = const [_leg],
}) => JourneyRequest(label: label, repeatDays: const [], legs: legs);

void main() {
  group('validateJourneyRequest', () {
    test('정상 여정은 null', () {
      expect(validateJourneyRequest(_request()), isNull);
    });

    test('라벨 — 빈 값·16자 초과 거부', () {
      expect(validateJourneyRequest(_request(label: '  ')), isNotNull);
      expect(validateJourneyRequest(_request(label: 'a' * 17)), isNotNull);
      expect(validateJourneyRequest(_request(label: 'a' * 16)), isNull);
    });

    test('구간 — 0개·5개 이상 거부', () {
      expect(validateJourneyRequest(_request(legs: const [])), isNotNull);
      expect(
        validateJourneyRequest(
          _request(legs: List.filled(maxJourneyLegs + 1, _leg)),
        ),
        isNotNull,
      );
      expect(
        validateJourneyRequest(
          _request(legs: List.filled(maxJourneyLegs, _leg)),
        ),
        isNull,
      );
    });

    test('탑승 역 = 하차 역 구간 거부', () {
      expect(
        validateJourneyRequest(
          _request(
            legs: const [
              JourneyLeg(line: '2호선', boardStop: '강남', alightStop: '강남'),
            ],
          ),
        ),
        isNotNull,
      );
    });

    test('노선·역이 빈 구간 거부', () {
      expect(
        validateJourneyRequest(
          _request(
            legs: const [
              JourneyLeg(line: '', boardStop: '여의도', alightStop: '당산'),
            ],
          ),
        ),
        isNotNull,
      );
    });
  });

  group('validateJourneyLegs — 1회성 바로 시작(FR-708)은 라벨 없이 구간 규칙만', () {
    test('정상 구간은 null, 라벨이 없어도 통과', () {
      expect(validateJourneyLegs(const [_leg]), isNull);
    });

    test('저장 여정과 같은 구간 규칙 — 0개·5개 이상·같은 역·빈 값 거부', () {
      expect(validateJourneyLegs(const []), '구간을 1개 이상 추가해주세요');
      expect(
        validateJourneyLegs(List.filled(maxJourneyLegs + 1, _leg)),
        '구간은 최대 $maxJourneyLegs개까지 가능해요',
      );
      expect(
        validateJourneyLegs(const [
          JourneyLeg(line: '9호선', boardStop: '당산', alightStop: '당산'),
        ]),
        '탑승 역과 하차 역이 같은 구간이 있어요',
      );
      expect(
        validateJourneyLegs(const [
          JourneyLeg(line: '', boardStop: '여의도', alightStop: '당산'),
        ]),
        '노선과 역을 모두 선택해주세요',
      );
    });
  });

  test('JourneyLeg JSON 왕복 — 로컬 스냅숏(1회성 트립)·서버 요청 공용', () {
    final json = _leg.toJson();
    expect(json['type'], 'SUBWAY'); // v1은 지하철만 (API.md §9)
    expect(JourneyLeg.fromJson(json), _leg);
  });

  group('최근 간 길 (FR-708) — 저장 안 한 1회성 구간', () {
    const other = JourneyLeg(line: '2호선', boardStop: '당산', alightStop: '강남');
    final now = DateTime(2026, 9, 21, 8);

    test('pushRecentRoute — 같은 길은 하나로 맨 앞, 최대 5개', () {
      var routes = pushRecentRoute(const [], [_leg], now);
      routes = pushRecentRoute(routes, [other], now.add(const Duration(hours: 1)));
      routes = pushRecentRoute(routes, [_leg], now.add(const Duration(hours: 2)));
      expect(routes.map((r) => r.legs.first), [_leg, other]);
      expect(routes.first.lastUsedAt, now.add(const Duration(hours: 2)));

      for (var i = 0; i < 10; i++) {
        routes = pushRecentRoute(
          routes,
          [JourneyLeg(line: '$i호선', boardStop: 'a$i', alightStop: 'b$i')],
          now,
        );
      }
      expect(routes, hasLength(maxRecentRoutes));
    });

    test('RecentRoute JSON 왕복', () {
      final route = RecentRoute(legs: const [_leg, other], lastUsedAt: now);
      final back = RecentRoute.fromJson(route.toJson());
      expect(back.legs, route.legs);
      expect(back.lastUsedAt, now);
    });

    test('recentRouteDateLabel — 오늘/어제/날짜', () {
      expect(recentRouteDateLabel(now, now), '오늘');
      expect(recentRouteDateLabel(now.subtract(const Duration(days: 1)), now), '어제');
      expect(recentRouteDateLabel(DateTime(2026, 9, 3), now), '9월 3일');
    });
  });

  test('journeyPathSummary — 구간을 이어 경로 문자열을 만든다', () {
    expect(
      journeyPathSummary(const [
        JourneyLeg(line: '9호선 급행', boardStop: '여의도', alightStop: '당산'),
        JourneyLeg(line: '2호선', boardStop: '당산', alightStop: '강남'),
      ]),
      '여의도 → 당산 → 강남',
    );
    expect(journeyPathSummary(const []), '');
  });

  group('parseTripLink', () {
    test('catchmyride://trip?tripId=… → tripId', () {
      expect(
        parseTripLink(Uri.parse('catchmyride://trip?tripId=abc-123')),
        'abc-123',
      );
    });

    test('트립 링크가 아니거나 tripId가 없으면 null', () {
      expect(parseTripLink(null), isNull);
      expect(
        parseTripLink(Uri.parse('catchmyride://open?from=push')),
        isNull,
      );
      expect(parseTripLink(Uri.parse('catchmyride://trip')), isNull);
      expect(parseTripLink(Uri.parse('catchmyride://trip?tripId=')), isNull);
    });
  });

  test('TripPhase.fromWire 왕복', () {
    for (final phase in TripPhase.values) {
      expect(TripPhase.fromWire(phase.wire), phase);
    }
  });

  test('dayOfWeekFrom — DateTime.weekday(1=월…7=일) 매핑', () {
    expect(dayOfWeekFrom(DateTime(2026, 9, 14)), DayOfWeek.mon); // 월요일
    expect(dayOfWeekFrom(DateTime(2026, 9, 15)), DayOfWeek.tue);
    expect(dayOfWeekFrom(DateTime(2026, 9, 20)), DayOfWeek.sun); // 일요일
  });

  group('pickBoardingJourney — "탔어요" 브리지 여정 선택', () {
    Journey journey(String id, List<DayOfWeek> repeatDays) => Journey(
      id: id,
      label: id,
      repeatDays: repeatDays,
      legs: const [
        JourneyLeg(line: '9호선 급행', boardStop: '여의도', alightStop: '당산'),
      ],
      lastUsedAt: null,
    );

    final tuesday = DateTime(2026, 9, 15); // 화요일

    test('오늘 요일에 반복되는 여정 우선 — 목록 순서(lastUsedAt 내림차순) 유지', () {
      final picked = pickBoardingJourney([
        journey('반복없음', const []),
        journey('화요일-첫째', const [DayOfWeek.tue]),
        journey('화요일-둘째', const [DayOfWeek.tue]),
      ], tuesday);
      expect(picked?.id, '화요일-첫째');
    });

    test('오늘 요일 여정이 없으면 반복 없는 여정으로', () {
      final picked = pickBoardingJourney([
        journey('월요일', const [DayOfWeek.mon]),
        journey('반복없음', const []),
      ], tuesday);
      expect(picked?.id, '반복없음');
    });

    test('다른 요일 전용 여정만 있으면 권하지 않는다', () {
      final picked = pickBoardingJourney([
        journey('월요일', const [DayOfWeek.mon]),
      ], tuesday);
      expect(picked, isNull);
    });

    test('여정이 없으면 null', () {
      expect(pickBoardingJourney(const [], tuesday), isNull);
    });
  });
}
