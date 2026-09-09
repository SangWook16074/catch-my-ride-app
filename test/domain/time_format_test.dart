import 'package:catch_my_ride/domain/time_format.dart';
import 'package:flutter_test/flutter_test.dart';

// 미니앱 src/components/__tests__/TimeField.test.tsx의 순수 함수부 이식.

void main() {
  group('toHHMM', () {
    test('오전 12시 = 00시, 오후 12시 = 12시', () {
      expect(toHHMM(Meridiem.am, 12, 0), '00:00');
      expect(toHHMM(Meridiem.pm, 12, 30), '12:30');
    });

    test('오전/오후 변환', () {
      expect(toHHMM(Meridiem.am, 7, 40), '07:40');
      expect(toHHMM(Meridiem.pm, 1, 5), '13:05');
      expect(toHHMM(Meridiem.pm, 11, 55), '23:55');
    });
  });

  group('parseHHMM', () {
    test('24시간 표기를 12시간 부품으로 분해한다', () {
      final morning = parseHHMM('08:20')!;
      expect(morning.meridiem, Meridiem.am);
      expect(morning.hour12, 8);
      expect(morning.minute, 20);

      final midnight = parseHHMM('00:00')!;
      expect(midnight.meridiem, Meridiem.am);
      expect(midnight.hour12, 12);

      final noon = parseHHMM('12:00')!;
      expect(noon.meridiem, Meridiem.pm);
      expect(noon.hour12, 12);
    });

    test('형식 오류·범위 밖은 null', () {
      expect(parseHHMM('7:40'), isNull);
      expect(parseHHMM('24:00'), isNull);
      expect(parseHHMM('12:60'), isNull);
      expect(parseHHMM(''), isNull);
    });
  });

  group('formatKoreanTime', () {
    test('"08:20" → "오전 8:20"', () {
      expect(formatKoreanTime('08:20'), '오전 8:20');
      expect(formatKoreanTime('13:05'), '오후 1:05');
      expect(formatKoreanTime('00:00'), '오전 12:00');
      expect(formatKoreanTime('12:00'), '오후 12:00');
    });

    test('파싱 불가면 원본 유지', () {
      expect(formatKoreanTime('7:40'), '7:40');
    });
  });
}
