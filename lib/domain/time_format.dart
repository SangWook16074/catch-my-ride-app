/// HH:MM(24시간) ↔ 오전/오후·12시간 표기 변환 — TimeField 바텀시트가 쓴다.
/// 미니앱 src/components/TimeField.tsx의 순수 함수부 이식.
library;

enum Meridiem { am, pm }

class TimeParts {
  const TimeParts({
    required this.meridiem,
    required this.hour12,
    required this.minute,
  });

  final Meridiem meridiem;
  final int hour12;
  final int minute;
}

String _pad(int n) => n.toString().padLeft(2, '0');

/// 오전 12시 = 00시, 오후 12시 = 12시
String toHHMM(Meridiem meridiem, int hour12, int minute) {
  final base = hour12 % 12;
  final hour = meridiem == Meridiem.pm ? base + 12 : base;
  return '${_pad(hour)}:${_pad(minute)}';
}

TimeParts? parseHHMM(String value) {
  final match = RegExp(r'^(\d{2}):(\d{2})$').firstMatch(value);
  if (match == null) {
    return null;
  }
  final hour = int.parse(match.group(1)!);
  final minute = int.parse(match.group(2)!);
  if (hour > 23 || minute > 59) {
    return null;
  }
  return TimeParts(
    meridiem: hour < 12 ? Meridiem.am : Meridiem.pm,
    hour12: hour % 12 == 0 ? 12 : hour % 12,
    minute: minute,
  );
}

/// "08:20" → "오전 8:20" — 필드에 보여줄 표기
String formatKoreanTime(String value) {
  final parts = parseHHMM(value);
  if (parts == null) {
    return value;
  }
  final meridiemLabel = parts.meridiem == Meridiem.am ? '오전' : '오후';
  return '$meridiemLabel ${parts.hour12}:${_pad(parts.minute)}';
}
