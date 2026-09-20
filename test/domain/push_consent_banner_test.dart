import 'package:catch_my_ride/domain/push_consent_banner.dart';
import 'package:flutter_test/flutter_test.dart';

// 미니앱 src/domain/__tests__/pushConsentBanner.test.ts 이식 — 노출 규칙이 양쪽 같아야 한다.

final DateTime _now = DateTime(2026, 9, 14, 9);
String _daysAgo(int days) =>
    _now.subtract(Duration(days: days)).toIso8601String();

void main() {
  group('shouldShowPushConsentBanner — 푸시 재동의 배너 노출 규칙', () {
    test('권한 허용 상태면 절대 보여주지 않는다', () {
      expect(shouldShowPushConsentBanner(true, null, _now), isFalse);
      expect(shouldShowPushConsentBanner(true, _daysAgo(30), _now), isFalse);
    });

    test('권한 없음(미결정·거부)이면 보여준다 — 배너는 수동 진입점이라 스팸이 아니다', () {
      expect(shouldShowPushConsentBanner(false, null, _now), isTrue);
    });

    test('"나중에" 후 7일간 억제, 지나면 다시 보여준다', () {
      expect(shouldShowPushConsentBanner(false, _daysAgo(1), _now), isFalse);
      expect(
        shouldShowPushConsentBanner(
          false,
          _daysAgo(pushBannerSuppressDays),
          _now,
        ),
        isTrue,
      );
    });

    test('저장값이 깨졌으면 억제하지 않는다 — 알림이 영영 꺼진 채가 더 나쁜 실패', () {
      expect(shouldShowPushConsentBanner(false, 'not-a-date', _now), isTrue);
    });
  });
}
