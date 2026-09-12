import 'package:catch_my_ride/domain/push_entry.dart';
import 'package:flutter_test/flutter_test.dart';

// 미니앱 src/domain/__tests__/pushEntry.test.ts 이식 — 스킴만 catchmyride://로 다르다.

void main() {
  test('from=push + 유효한 날짜면 푸시 진입', () {
    final entry = parsePushEntry(
      Uri.parse('catchmyride://open?from=push&notifiedDate=2026-09-09'),
    );
    expect(entry.fromPush, isTrue);
    expect(entry.notifiedDate, '2026-09-09');
  });

  test('날짜가 없거나 형식이 어긋나면 notifiedDate는 null (진입은 유효)', () {
    expect(
      parsePushEntry(Uri.parse('catchmyride://open?from=push')).notifiedDate,
      isNull,
    );
    final malformed = parsePushEntry(
      Uri.parse('catchmyride://open?from=push&notifiedDate=09-09-2026'),
    );
    expect(malformed.fromPush, isTrue);
    expect(malformed.notifiedDate, isNull);
  });

  test('from=push가 아니면 푸시 진입 아님', () {
    expect(parsePushEntry(null).fromPush, isFalse);
    expect(parsePushEntry(Uri.parse('catchmyride://open')).fromPush, isFalse);
    expect(
      parsePushEntry(Uri.parse('catchmyride://open?from=widget')).fromPush,
      isFalse,
    );
  });
}
