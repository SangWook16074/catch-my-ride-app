import 'package:catch_my_ride/domain/journey.dart';
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

  test('TripPhase.fromWire 왕복', () {
    for (final phase in TripPhase.values) {
      expect(TripPhase.fromWire(phase.wire), phase);
    }
  });
}
