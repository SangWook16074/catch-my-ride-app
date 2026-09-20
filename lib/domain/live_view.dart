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

/// 알림 안내 문구 (FR-501 개정, 오너 문구 확정 2026-09-20) — "몇 분 전에 알림이 오는지"를
/// 라이브 뷰에 보여준다. N = 여유 버퍼(사전 알림 = 출발 {여유}분 전, 서버
/// DepartureTimingService와 동일). 여유가 2분 미만이면 사전 알림이 리마인드와 겹쳐
/// 리마인드만 발송되므로 실제 발송 시점인 1분으로 안내한다.
String notificationSummary(CommuteSetting setting) {
  final minutes = setting.bufferMinutes >= 1 ? setting.bufferMinutes : 1;
  return '현재 여유있게 $minutes분 전에 알림을 보내드려요';
}

String formatFetchedAt(String iso) {
  final date = DateTime.parse(iso).toLocal();
  String pad(int n) => n.toString().padLeft(2, '0');
  return '${pad(date.hour)}:${pad(date.minute)}:${pad(date.second)}';
}
