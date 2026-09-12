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

String formatFetchedAt(String iso) {
  final date = DateTime.parse(iso).toLocal();
  String pad(int n) => n.toString().padLeft(2, '0');
  return '${pad(date.hour)}:${pad(date.minute)}:${pad(date.second)}';
}
