/// API.md v0.1 계약 모델 — 순수 Dart (CLAUDE.md 레이어 규칙: domain은 Flutter import 금지).
/// 서버 스키마 변경 시 ../API.md와 함께 갱신한다.
library;

enum StopType {
  seoulBus('SEOUL_BUS'),
  gyeonggiBus('GYEONGGI_BUS'),
  subway('SUBWAY');

  const StopType(this.wire);

  /// 서버 계약의 enum 문자열
  final String wire;
}

enum DayOfWeek {
  mon('MON'),
  tue('TUE'),
  wed('WED'),
  thu('THU'),
  fri('FRI'),
  sat('SAT'),
  sun('SUN');

  const DayOfWeek(this.wire);

  final String wire;
}

class GeoPoint {
  const GeoPoint({required this.latitude, required this.longitude});

  final double latitude;
  final double longitude;

  @override
  bool operator ==(Object other) =>
      other is GeoPoint &&
      other.latitude == latitude &&
      other.longitude == longitude;

  @override
  int get hashCode => Object.hash(latitude, longitude);
}

class CommuteStop {
  const CommuteStop({
    required this.type,
    required this.stopId,
    required this.displayName,
    required this.routes,
  });

  final StopType type;

  /// SEOUL_BUS=arsId(5자리) / GYEONGGI_BUS=GBIS stationId / SUBWAY=역명
  final String stopId;
  final String displayName;
  final List<String> routes;

  CommuteStop copyWith({List<String>? routes}) => CommuteStop(
    type: type,
    stopId: stopId,
    displayName: displayName,
    routes: routes ?? List.of(this.routes),
  );

  @override
  bool operator ==(Object other) =>
      other is CommuteStop &&
      other.type == type &&
      other.stopId == stopId &&
      other.displayName == displayName &&
      listEquals(other.routes, routes);

  @override
  int get hashCode =>
      Object.hash(type, stopId, displayName, Object.hashAll(routes));
}

enum NotificationMode {
  fixed('FIXED'),
  recommended('RECOMMENDED');

  const NotificationMode(this.wire);

  final String wire;
}

class CommuteWindow {
  const CommuteWindow({required this.start, required this.end});

  /// "HH:mm"
  final String start;
  final String end;

  @override
  bool operator ==(Object other) =>
      other is CommuteWindow && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);
}

class CommuteSetting {
  const CommuteSetting({
    required this.home,
    required this.stops,
    required this.walkMinutes,
    required this.notificationMode,
    required this.fixedDepartureTime,
    required this.commuteWindow,
    required this.bufferMinutes,
    required this.activeDays,
  });

  final GeoPoint home;
  final List<CommuteStop> stops;
  final int walkMinutes;
  final NotificationMode notificationMode;

  /// 모드 FIXED일 때 필수
  final String? fixedDepartureTime;

  /// 모드 RECOMMENDED일 때 필수
  final CommuteWindow? commuteWindow;
  final int bufferMinutes;
  final List<DayOfWeek> activeDays;

  CommuteSetting copyWith({int? bufferMinutes}) => CommuteSetting(
    home: home,
    stops: stops,
    walkMinutes: walkMinutes,
    notificationMode: notificationMode,
    fixedDepartureTime: fixedDepartureTime,
    commuteWindow: commuteWindow,
    bufferMinutes: bufferMinutes ?? this.bufferMinutes,
    activeDays: activeDays,
  );
}

/// API.md §1-2 — 통근 경로 (유저당 최대 5개, 출근·퇴근 등 라벨 구분)
class CommuteRoute {
  const CommuteRoute({
    required this.id,
    required this.label,
    required this.enabled,
    required this.setting,
  });

  /// 서버 발급 UUID
  final String id;

  /// "출근"/"퇴근" 프리셋 또는 자유 입력 (1~16자)
  final String label;

  /// false = 이 경로 알림 일시 중지
  final bool enabled;
  final CommuteSetting setting;
}

/// 생성·수정 요청 — id는 URL 경로로만 전달한다
class CommuteRouteRequest {
  const CommuteRouteRequest({
    required this.label,
    required this.enabled,
    required this.setting,
  });

  final String label;
  final bool enabled;
  final CommuteSetting setting;
}

const int maxCommuteRoutes = 5;

enum ArrivalStatus { relaxed, hurry, missed }

class Arrival {
  const Arrival({
    required this.stopDisplayName,
    required this.routeName,
    required this.secondsToArrival,
    required this.remainingStops,
    required this.isExpress,
    required this.boardable,
    required this.status,
    required this.rawMessage,
    this.directionLabel,
  });

  final String stopDisplayName;
  final String routeName;

  /// 행선지·방면 표기 — 지하철 "당고개행" / 버스 "강남역 방면"(v0.6). 상류 미제공 시 null
  final String? directionLabel;

  /// null = 실시간 정보 없음 (아는 척 금지 — "정보 없음" 표시)
  final int? secondsToArrival;
  final int? remainingStops;

  /// 지하철 급행 여부. 버스는 null
  final bool? isExpress;
  final bool boardable;
  final ArrivalStatus status;
  final String? rawMessage;
}

class ArrivalsResponse {
  const ArrivalsResponse({
    required this.fetchedAt,
    required this.realtimeAvailable,
    required this.walkMinutes,
    required this.arrivals,
  });

  /// ISO-8601 — "마지막 갱신 시각"으로 표시
  final String fetchedAt;
  final bool realtimeAvailable;
  final int walkMinutes;
  final List<Arrival> arrivals;
}

/// API.md §5-1 — 전체 정류장/역 검색 결과 (온보딩 FR-102)
class StopSearchResult {
  const StopSearchResult({
    required this.type,
    required this.stopId,
    required this.displayName,
    required this.subtitle,
  });

  final StopType type;
  final String stopId;
  final String displayName;

  /// 동명 정류장 구분용 보조 정보 — 정류소 번호·행정구 / 호선
  final String subtitle;
}

/// API.md §5-2 — 정류장 경유 노선 (온보딩 FR-103)
class RouteOption {
  const RouteOption({
    required this.name,
    required this.isExpress,
    this.directionLabel,
  });

  final String name;

  /// 지하철 급행 여부. 버스는 null
  final bool? isExpress;

  /// 버스 방면 표기("강남역 방면", v0.6) — 반대편 정류장 선택을 알아채게 한다. 지하철·미제공 시 null
  final String? directionLabel;
}

/// API.md §7 — 주소 검색(지오코딩) 결과
class GeocodeResult {
  const GeocodeResult({
    required this.roadAddress,
    required this.jibunAddress,
    required this.latitude,
    required this.longitude,
  });

  final String roadAddress;
  final String jibunAddress;
  final double latitude;
  final double longitude;
}

/// API.md §7-1 — 역지오코딩(좌표 → 주소). GPS 등록 직후 "어떤 주소로 잡혔는지" 확인용.
/// 못 찾은 쪽은 빈 문자열(에러 아님) — 클라이언트는 도로명 우선, 둘 다 비면 일반 안내 문구로 강등.
class ReverseGeocodeResult {
  const ReverseGeocodeResult({
    required this.roadAddress,
    required this.jibunAddress,
  });

  final String roadAddress;
  final String jibunAddress;

  /// 표시용 주소 — 도로명 우선, 둘 다 비면 null
  String? get displayAddress {
    if (roadAddress.isNotEmpty) {
      return roadAddress;
    }
    if (jibunAddress.isNotEmpty) {
      return jibunAddress;
    }
    return null;
  }
}

enum BoardingResult {
  boarded('BOARDED'),
  missed('MISSED');

  const BoardingResult(this.wire);

  final String wire;

  static BoardingResult fromWire(String wire) =>
      values.firstWhere((result) => result.wire == wire);
}

/// API.md §3-2 — 탑승 피드백 이력 한 건 (통근 리포트 원본, 서버가 최신순으로 준다)
class FeedbackEntry {
  const FeedbackEntry({required this.date, required this.result});

  /// "YYYY-MM-DD"
  final String date;
  final BoardingResult result;
}

/// API.md §3-1 — 여유 버퍼 자동 추천 (최근 피드백 5건 기반, 서버는 제안만)
class BufferRecommendation {
  const BufferRecommendation({
    required this.recommend,
    required this.missedCount,
    required this.sampleSize,
    required this.suggestedIncrementMinutes,
  });

  final bool recommend;
  final int missedCount;
  final int sampleSize;
  final int suggestedIncrementMinutes;
}

class BoardingFeedbackRequest {
  const BoardingFeedbackRequest({
    required this.result,
    required this.notifiedDate,
  });

  final BoardingResult result;

  /// "YYYY-MM-DD"
  final String notifiedDate;
}

/// 404 SETTING_NOT_FOUND 등을 흐름 제어에 쓰기 위한 에러 타입
class ApiException implements Exception {
  const ApiException(this.status, this.code, this.message);

  final int status;
  final String code;
  final String message;

  static const String settingNotFound = 'SETTING_NOT_FOUND';
  static const String invalidRequest = 'INVALID_REQUEST';

  @override
  String toString() => 'ApiException($status, $code, $message)';
}

/// 순수 Dart 리스트 동등 비교 — domain은 flutter/foundation을 쓰지 않는다.
bool listEquals<T>(List<T>? a, List<T>? b) {
  if (identical(a, b)) {
    return true;
  }
  if (a == null || b == null || a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}
