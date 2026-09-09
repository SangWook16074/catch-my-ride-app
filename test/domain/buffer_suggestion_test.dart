import 'package:catch_my_ride/domain/buffer_suggestion.dart';
import 'package:catch_my_ride/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

// 미니앱 src/domain/__tests__/bufferSuggestion.test.ts 이식.

const _recommend = BufferRecommendation(
  recommend: true,
  missedCount: 2,
  sampleSize: 5,
  suggestedIncrementMinutes: 5,
);

final _now = DateTime(2026, 9, 9, 8);

void main() {
  test('추천이 없거나 recommend=false면 숨긴다', () {
    expect(shouldShowBufferSuggestion(null, null, _now), isFalse);
    expect(
      shouldShowBufferSuggestion(
        const BufferRecommendation(
          recommend: false,
          missedCount: 1,
          sampleSize: 5,
          suggestedIncrementMinutes: 5,
        ),
        null,
        _now,
      ),
      isFalse,
    );
  });

  test('처리 이력이 없으면 보여준다', () {
    expect(shouldShowBufferSuggestion(_recommend, null, _now), isTrue);
  });

  test('처리 후 7일 미만이면 억제한다', () {
    final handledAt = _now.subtract(const Duration(days: 6, hours: 23));
    expect(
      shouldShowBufferSuggestion(
        _recommend,
        handledAt.toIso8601String(),
        _now,
      ),
      isFalse,
    );
  });

  test('처리 후 7일이 지나면 다시 보여준다', () {
    final handledAt = _now.subtract(const Duration(days: suppressDays));
    expect(
      shouldShowBufferSuggestion(
        _recommend,
        handledAt.toIso8601String(),
        _now,
      ),
      isTrue,
    );
  });

  test('저장값이 깨졌으면 억제하지 않는다 — 추천이 사라지는 쪽이 더 나쁜 실패', () {
    expect(
      shouldShowBufferSuggestion(_recommend, 'not-a-date', _now),
      isTrue,
    );
  });
}
