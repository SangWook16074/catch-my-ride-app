/// 하차 알림 — 여정(Journey)·트립 도메인 (명세서 §3.7, API.md §9).
/// 순수 Dart — 검증 규칙은 전부 단위 테스트 대상 (CLAUDE.md 레이어 규칙).
library;

import 'models.dart';

const int maxJourneys = 10;
const int maxJourneyLegs = 4;
const int journeyLabelMaxLength = 16;

/// 여정의 한 구간 — 탑승 역에서 노선을 타고 하차(환승) 역까지. v1은 지하철만 (FR-703)
class JourneyLeg {
  const JourneyLeg({
    required this.line,
    required this.boardStop,
    required this.alightStop,
  });

  /// §5-2 표기 그대로 ("9호선 급행")
  final String line;

  /// 역명 (= §5-1 SUBWAY stopId)
  final String boardStop;
  final String alightStop;

  @override
  bool operator ==(Object other) =>
      other is JourneyLeg &&
      other.line == line &&
      other.boardStop == boardStop &&
      other.alightStop == alightStop;

  @override
  int get hashCode => Object.hash(line, boardStop, alightStop);
}

class Journey {
  const Journey({
    required this.id,
    required this.label,
    required this.repeatDays,
    required this.legs,
    required this.lastUsedAt,
  });

  final String id;
  final String label;

  /// 요일 반복(FR-702) — 빈 리스트 = 반복 없음. 자동 시작 아님(시작은 항상 수동)
  final List<DayOfWeek> repeatDays;
  final List<JourneyLeg> legs;

  /// ISO-8601 — 트립 시작 시 서버 갱신(히스토리 정렬 키). 생성 직후 null
  final String? lastUsedAt;
}

/// 생성·수정 요청 (id·lastUsedAt 없음)
class JourneyRequest {
  const JourneyRequest({
    required this.label,
    required this.repeatDays,
    required this.legs,
  });

  final String label;
  final List<DayOfWeek> repeatDays;
  final List<JourneyLeg> legs;
}

/// 여정 검증 — 위반이면 사용자에게 보여줄 메시지, 정상이면 null.
/// 노선-역 도달 가능성 검증은 서버 책임(API.md §9) — 여기선 형태만 본다
String? validateJourneyRequest(JourneyRequest request) {
  final label = request.label.trim();
  if (label.isEmpty) {
    return '여정 이름을 입력해주세요';
  }
  if (label.length > journeyLabelMaxLength) {
    return '여정 이름은 $journeyLabelMaxLength자 이내여야 해요';
  }
  if (request.legs.isEmpty) {
    return '구간을 1개 이상 추가해주세요';
  }
  if (request.legs.length > maxJourneyLegs) {
    return '구간은 최대 $maxJourneyLegs개까지 가능해요';
  }
  for (final leg in request.legs) {
    if (leg.line.trim().isEmpty ||
        leg.boardStop.trim().isEmpty ||
        leg.alightStop.trim().isEmpty) {
      return '노선과 역을 모두 선택해주세요';
    }
    if (leg.boardStop == leg.alightStop) {
      return '탑승 역과 하차 역이 같은 구간이 있어요';
    }
  }
  return null;
}

/// "여의도 → 당산 → 강남" — 목록·요약 표시용
String journeyPathSummary(List<JourneyLeg> legs) {
  if (legs.isEmpty) {
    return '';
  }
  final parts = <String>[legs.first.boardStop];
  for (final leg in legs) {
    parts.add(leg.alightStop);
  }
  return parts.join(' → ');
}

/// DateTime.weekday(1=월 … 7=일) → DayOfWeek
DayOfWeek dayOfWeekFrom(DateTime date) => DayOfWeek.values[date.weekday - 1];

/// "탔어요" 탑승 피드백 직후 하차 알림으로 이어줄 여정 선택 (2026-09-15 실주행 피드백 —
/// 탑승 순간이 열차 특정(§9-2 후보 스냅샷)에 가장 유리한 시작 타이밍이다).
/// 오늘 요일에 반복되는 여정 우선, 없으면 반복 없는 여정 — 각각 목록 순서(서버가
/// lastUsedAt 내림차순 정렬, §9-1)가 우선순위. 다른 요일 전용 여정은 권하지 않는다.
Journey? pickBoardingJourney(List<Journey> journeys, DateTime now) {
  final today = dayOfWeekFrom(now);
  for (final journey in journeys) {
    if (journey.repeatDays.contains(today)) {
      return journey;
    }
  }
  for (final journey in journeys) {
    if (journey.repeatDays.isEmpty) {
      return journey;
    }
  }
  return null;
}

/// 하차 푸시 딥링크(`catchmyride://trip?tripId=…`) 파싱 — 트립 링크가 아니면 null (API.md §9-4)
String? parseTripLink(Uri? uri) {
  if (uri == null || uri.host != 'trip') {
    return null;
  }
  final tripId = uri.queryParameters['tripId'];
  return (tripId == null || tripId.isEmpty) ? null : tripId;
}

/// 트립 진행 상태 (API.md §9-3)
enum TripPhase {
  tracking('TRACKING'),
  arriving('ARRIVING'),
  transfer('TRANSFER'),
  done('DONE'),
  lost('LOST');

  const TripPhase(this.wire);

  final String wire;

  static TripPhase fromWire(String wire) =>
      values.firstWhere((phase) => phase.wire == wire);
}

class TripStart {
  const TripStart({required this.tripId, required this.startedAt});

  final String tripId;
  final String startedAt;
}

class TripStatus {
  const TripStatus({
    required this.phase,
    required this.legIndex,
    required this.remainingStops,
    required this.currentStop,
    required this.eventStop,
    required this.realtimeAvailable,
    required this.fetchedAt,
  });

  final TripPhase phase;
  final int legIndex;

  /// 이벤트 역(하차/환승)까지 남은 정거장 — LOST면 null (아는 척 금지, NFR-03)
  final int? remainingStops;

  /// 열차 현재 위치 역명 — 특정 후 목격 값, 모르면 null. "현재 ○○ 부근" 표시용 (§9-3)
  final String? currentStop;

  /// 이번 구간의 하차/환승 역명
  final String eventStop;
  final bool realtimeAvailable;
  final String fetchedAt;
}
