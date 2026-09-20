import 'package:catch_my_ride/domain/live_view.dart';
import 'package:catch_my_ride/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

// 미니앱 src/domain/__tests__/liveView.test.ts 이식.

Arrival _arrival({
  int? seconds,
  bool boardable = true,
  ArrivalStatus status = ArrivalStatus.relaxed,
}) => Arrival(
  stopDisplayName: '여의도환승센터',
  routeName: '720',
  secondsToArrival: seconds,
  remainingStops: 3,
  isExpress: null,
  boardable: boardable,
  status: status,
  rawMessage: null,
);

void main() {
  group('formatRemaining', () {
    test('null은 정보 없음 — 아는 척 금지 (NFR-03)', () {
      expect(formatRemaining(null), '정보 없음');
    });

    test('60초 미만은 곧 도착', () {
      expect(formatRemaining(0), '곧 도착');
      expect(formatRemaining(59), '곧 도착');
    });

    test('분 단위 내림 표기', () {
      expect(formatRemaining(60), '1분');
      expect(formatRemaining(179), '2분');
      expect(formatRemaining(600), '10분');
    });
  });

  group('statusLabel', () {
    test('상태별 한국어 라벨', () {
      expect(statusLabel(ArrivalStatus.relaxed), '여유 있어요');
      expect(statusLabel(ArrivalStatus.hurry), '서두르세요');
      expect(statusLabel(ArrivalStatus.missed), '다음 차를 노리세요');
    });
  });

  group('pickBestBoardable', () {
    test('탑승 가능하고 실시간 정보가 있는 첫 차량을 고른다 (FR-303/305)', () {
      final arrivals = [
        _arrival(seconds: 100, boardable: false, status: ArrivalStatus.missed),
        _arrival(seconds: null),
        _arrival(seconds: 400),
        _arrival(seconds: 700),
      ];
      expect(pickBestBoardable(arrivals)?.secondsToArrival, 400);
    });

    test('탑승 가능한 차가 없으면 null', () {
      expect(pickBestBoardable([]), isNull);
      expect(
        pickBestBoardable([
          _arrival(seconds: 100, boardable: false),
          _arrival(seconds: null),
        ]),
        isNull,
      );
    });
  });

  group('formatFetchedAt', () {
    test('HH:MM:SS 로컬 표기', () {
      // 타임존 오프셋 없는 ISO 문자열은 로컬 시각으로 파싱된다
      expect(formatFetchedAt('2026-09-09T08:05:03'), '08:05:03');
    });
  });

  group('notificationSummary — 여유·알림 시점 안내 (FR-501 개정 2026-09-20)', () {
    CommuteSetting setting({
      NotificationMode mode = NotificationMode.recommended,
      String? fixedDepartureTime,
      int bufferMinutes = 5,
    }) => CommuteSetting(
      home: const GeoPoint(latitude: 37.5, longitude: 126.9),
      stops: const [],
      walkMinutes: 8,
      notificationMode: mode,
      fixedDepartureTime: fixedDepartureTime,
      commuteWindow: mode == NotificationMode.recommended
          ? const CommuteWindow(start: '07:30', end: '09:30')
          : null,
      bufferMinutes: bufferMinutes,
      activeDays: const [DayOfWeek.mon],
    );

    test('여유 버퍼를 N으로 안내한다 (오너 문구 확정 2026-09-20)', () {
      expect(
        notificationSummary(setting()),
        '현재 여유있게 5분 전에 알림을 보내드려요',
      );
    });

    test('정시 모드도 같은 문구 — 사전 알림 = 출발−버퍼라 N은 동일', () {
      expect(
        notificationSummary(
          setting(mode: NotificationMode.fixed, fixedDepartureTime: '08:10'),
        ),
        '현재 여유있게 5분 전에 알림을 보내드려요',
      );
    });

    test('여유 2분 미만 — 리마인드만 발송되므로 실제 발송 시점인 1분으로 안내', () {
      expect(
        notificationSummary(setting(bufferMinutes: 0)),
        '현재 여유있게 1분 전에 알림을 보내드려요',
      );
      expect(
        notificationSummary(setting(bufferMinutes: 1)),
        '현재 여유있게 1분 전에 알림을 보내드려요',
      );
    });
  });
}
