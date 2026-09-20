/// 라이브 뷰 표시 규칙 — 순수 함수만 (테스트: test/domain/live_view_test.dart)
/// 미니앱 src/domain/liveView.ts 이식.
library;

import 'models.dart';

String formatRemaining(int? secondsToArrival) {
  if (secondsToArrival == null) {
    return '정보 없음';
  }
  if (secondsToArrival < 60) {
    return '곧 도착';
  }
  return '${secondsToArrival ~/ 60}분';
}

const Map<ArrivalStatus, String> _statusLabels = {
  ArrivalStatus.relaxed: '여유 있어요',
  ArrivalStatus.hurry: '서두르세요',
  ArrivalStatus.missed: '다음 차를 노리세요',
};

String statusLabel(ArrivalStatus status) => _statusLabels[status]!;

/// 정렬된 도착 목록에서 탑승 가능한 가장 빠른 차량 (FR-303/305)
Arrival? pickBestBoardable(List<Arrival> arrivals) {
  for (final arrival in arrivals) {
    if (arrival.boardable && arrival.secondsToArrival != null) {
      return arrival;
    }
  }
  return null;
}

/// 알림 안내 문구 (FR-501 개정 2026-09-20) — 유저가 정한 여유 시간과 "몇 분 전에 알림이
/// 오는지"를 라이브 뷰에 보여준다. 타이밍 규칙은 서버 DepartureTimingService와 동일:
/// 미리 알림 = 출발 {여유}분 전, 리마인드 = 출발 1분 전 (여유가 2분 미만이면 리마인드만 —
/// 미리 알림 시점이 리마인드와 겹쳐 서버가 리마인드로만 발송한다).
String notificationSummary(CommuteSetting setting) {
  final buffer = setting.bufferMinutes;
  final departure = setting.fixedDepartureTime;
  if (setting.notificationMode == NotificationMode.fixed && departure != null) {
    final times = buffer >= 2
        ? '${_minusMinutes(departure, buffer)}와 ${_minusMinutes(departure, 1)}'
        : _minusMinutes(departure, 1);
    return '여유 $buffer분 · $departure 출발 — $times에 알림이 와요';
  }
  return buffer >= 2
      ? '여유 $buffer분 — 나가야 할 시각 $buffer분 전과 1분 전에 알림이 와요'
      : '여유 $buffer분 — 나가야 할 시각 1분 전에 알림이 와요';
}

String _minusMinutes(String hhmm, int minutes) {
  final parts = hhmm.split(':');
  final total =
      (int.parse(parts[0]) * 60 + int.parse(parts[1]) - minutes + 24 * 60) %
      (24 * 60);
  String pad(int n) => n.toString().padLeft(2, '0');
  return '${pad(total ~/ 60)}:${pad(total % 60)}';
}

String formatFetchedAt(String iso) {
  final date = DateTime.parse(iso).toLocal();
  String pad(int n) => n.toString().padLeft(2, '0');
  return '${pad(date.hour)}:${pad(date.minute)}:${pad(date.second)}';
}
