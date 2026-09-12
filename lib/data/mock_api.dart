/// 서버 연동(스토어판 인증 확정) 전까지 API.md 계약을 그대로 흉내내는 mock.
/// 노선별 가상 배차 스케줄(절대 시각)을 유지해, 폴링할 때마다 남은 시간이 실제처럼 줄어든다.
/// 미니앱 src/api/mock.ts 이식 — 검증 규칙·배차 파라미터 동일.
library;

import '../domain/models.dart';
import '../domain/onboarding.dart' show routeLabelMaxLength;
import 'api.dart';

final RegExp _timePattern = RegExp(r'^([01]\d|2[0-3]):[0-5]\d$');
final RegExp _datePattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');

ApiException _notFound() =>
    const ApiException(404, ApiException.settingNotFound, '통근 설정이 없습니다');

ApiException _invalid(String message) =>
    ApiException(400, ApiException.invalidRequest, message);

void _validateSetting(CommuteSetting setting) {
  if (setting.stops.isEmpty) {
    throw _invalid('정류장을 1개 이상 등록해야 합니다');
  }
  for (final stop in setting.stops) {
    if (stop.routes.isEmpty) {
      throw _invalid('${stop.displayName}: 노선을 1개 이상 선택해야 합니다');
    }
  }
  if (setting.walkMinutes <= 0) {
    throw _invalid('도보 시간은 1분 이상이어야 합니다');
  }
  if (setting.bufferMinutes < 0) {
    throw _invalid('여유 시간은 0분 이상이어야 합니다');
  }
  if (setting.activeDays.isEmpty) {
    throw _invalid('적용 요일을 1개 이상 선택해야 합니다');
  }
  if (setting.notificationMode == NotificationMode.fixed) {
    final time = setting.fixedDepartureTime;
    if (time == null || !_timePattern.hasMatch(time)) {
      throw _invalid('정시 모드는 출발 시각(HH:mm)이 필요합니다');
    }
  } else {
    final window = setting.commuteWindow;
    if (window == null ||
        !_timePattern.hasMatch(window.start) ||
        !_timePattern.hasMatch(window.end)) {
      throw _invalid('추천 모드는 출근 시간대(HH:mm~HH:mm)가 필요합니다');
    }
  }
}

class _MockStop {
  const _MockStop({
    required this.type,
    required this.stopId,
    required this.displayName,
    required this.subtitle,
    required this.routes,
  });

  final StopType type;
  final String stopId;
  final String displayName;
  final String subtitle;
  final List<RouteOption> routes;

  StopSearchResult get searchResult => StopSearchResult(
    type: type,
    stopId: stopId,
    displayName: displayName,
    subtitle: subtitle,
  );
}

/// §5 검색용 mock 카탈로그 — 실제 서버는 서울·경기 전 정류소 + 수도권 전 역을 커버한다(API.md §5).
const List<_MockStop> _mockStops = [
  _MockStop(
    type: StopType.seoulBus,
    stopId: '19284',
    displayName: '여의도환승센터',
    subtitle: '19284 · 영등포구',
    routes: [
      RouteOption(name: '720', isExpress: null),
      RouteOption(name: '261', isExpress: null),
      RouteOption(name: '5615', isExpress: null),
    ],
  ),
  _MockStop(
    type: StopType.seoulBus,
    stopId: '19169',
    displayName: '국회의사당역',
    subtitle: '19169 · 영등포구',
    routes: [
      RouteOption(name: '162', isExpress: null),
      RouteOption(name: '262', isExpress: null),
    ],
  ),
  _MockStop(
    type: StopType.gyeonggiBus,
    stopId: '4109334',
    displayName: '수원역.AK플라자',
    subtitle: '수원시 팔달구',
    routes: [
      RouteOption(name: '7770', isExpress: null),
      RouteOption(name: 'M5107', isExpress: null),
    ],
  ),
  _MockStop(
    type: StopType.subway,
    stopId: '여의도',
    displayName: '여의도역',
    subtitle: '5호선 · 9호선(급행)',
    routes: [
      RouteOption(name: '5호선', isExpress: false),
      RouteOption(name: '9호선 급행', isExpress: true),
      RouteOption(name: '9호선 일반', isExpress: false),
    ],
  ),
  _MockStop(
    type: StopType.subway,
    stopId: '국회의사당',
    displayName: '국회의사당역',
    subtitle: '9호선',
    routes: [RouteOption(name: '9호선 일반', isExpress: false)],
  ),
  _MockStop(
    type: StopType.subway,
    stopId: '수원',
    displayName: '수원역',
    subtitle: '1호선 · 수인분당선',
    routes: [
      RouteOption(name: '1호선', isExpress: false),
      RouteOption(name: '수인분당선', isExpress: false),
    ],
  ),
];

const int _maxResultsPerSource = 10;

/// §7 지오코딩 mock 카탈로그 — 주소 등록 UX 검증에 필요한 만큼만
const List<GeocodeResult> _mockAddresses = [
  GeocodeResult(
    roadAddress: '서울특별시 영등포구 여의공원로 101',
    jibunAddress: '서울특별시 영등포구 여의도동 23',
    latitude: 37.5219,
    longitude: 126.9245,
  ),
  GeocodeResult(
    roadAddress: '경기도 수원시 팔달구 덕영대로 924',
    jibunAddress: '경기도 수원시 팔달구 매산로1가 18',
    latitude: 37.2656,
    longitude: 127.0002,
  ),
];

int _hashString(String value) {
  var hash = 0;
  for (final unit in value.codeUnits) {
    hash = (hash * 31 + unit) & 0xFFFFFFFF;
  }
  return hash;
}

ArrivalStatus _statusOf(
  int secondsToArrival,
  int walkSeconds,
  int bufferSeconds,
) {
  final margin = secondsToArrival - walkSeconds;
  if (margin < 0) {
    return ArrivalStatus.missed;
  }
  if (margin <= bufferSeconds) {
    return ArrivalStatus.hurry;
  }
  return ArrivalStatus.relaxed;
}

class MockNochijimaApi implements NochijimaApi {
  /// §1-2 다중 경로 — 생성순 유지, 첫 경로가 routeId 생략의 기본
  final List<CommuteRoute> _routes = [];
  int _nextRouteId = 1;

  /// "정류장/노선" → 다음 도착 절대 시각(ms). 지나가면 배차 간격만큼 앞으로 민다.
  final Map<String, int> _schedule = {};
  final Map<String, BoardingResult> _feedbackByDate = {};

  void _validateRoute(CommuteRouteRequest request, [String? selfId]) {
    final label = request.label.trim();
    if (label.isEmpty) {
      throw _invalid('경로 이름을 입력해야 합니다');
    }
    if (label.length > routeLabelMaxLength) {
      throw _invalid('경로 이름은 $routeLabelMaxLength자 이내여야 합니다');
    }
    if (_routes.any((r) => r.id != selfId && r.label == label)) {
      throw _invalid('같은 이름의 경로가 이미 있습니다: $label');
    }
    _validateSetting(request.setting);
  }

  List<int> _nextArrivalsFor(String key, int now) {
    final hash = _hashString(key);
    final headwayMs = (420 + (hash % 481)) * 1000; // 배차 7~15분
    var next = _schedule[key] ?? now + (150 + (hash % 600)) * 1000; // 첫 도착 2.5~12.5분 후
    while (next <= now) {
      next += headwayMs;
    }
    _schedule[key] = next;
    return [next, next + headwayMs];
  }

  ArrivalsResponse _arrivalsFor(CommuteSetting setting) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final walkSeconds = setting.walkMinutes * 60;
    final bufferSeconds = setting.bufferMinutes * 60;

    final arrivals = <Arrival>[];
    for (final stop in setting.stops) {
      for (final route in stop.routes) {
        final key = '${stop.displayName}/$route';
        final isSubway = stop.type == StopType.subway;
        for (final arrivalTs in _nextArrivalsFor(key, now)) {
          final secondsToArrival = (arrivalTs - now) ~/ 1000;
          final minutes = (secondsToArrival / 60).round().clamp(1, 1 << 31);
          final remainingStops = isSubway
              ? null
              : (secondsToArrival / 120).round().clamp(1, 1 << 31);
          arrivals.add(
            Arrival(
              stopDisplayName: stop.displayName,
              routeName: route,
              secondsToArrival: secondsToArrival,
              remainingStops: remainingStops,
              isExpress: isSubway ? route.contains('급행') : null,
              boardable: secondsToArrival >= walkSeconds,
              status: _statusOf(secondsToArrival, walkSeconds, bufferSeconds),
              rawMessage: isSubway ? null : '$minutes분후[$remainingStops번째 전]',
            ),
          );
        }
      }
    }
    arrivals.sort((a, b) {
      final sa = a.secondsToArrival;
      final sb = b.secondsToArrival;
      if (sa == null) {
        return sb == null ? 0 : 1;
      }
      if (sb == null) {
        return -1;
      }
      return sa - sb;
    });

    return ArrivalsResponse(
      fetchedAt: DateTime.fromMillisecondsSinceEpoch(now).toIso8601String(),
      realtimeAvailable: true,
      walkMinutes: setting.walkMinutes,
      arrivals: arrivals,
    );
  }

  @override
  Future<List<CommuteRoute>> listCommuteRoutes() async => List.of(_routes);

  @override
  Future<CommuteRoute> createCommuteRoute(CommuteRouteRequest request) async {
    if (_routes.length >= maxCommuteRoutes) {
      throw _invalid('경로는 최대 $maxCommuteRoutes개까지 저장할 수 있습니다');
    }
    _validateRoute(request);
    final route = CommuteRoute(
      id: 'mock-route-${_nextRouteId++}',
      label: request.label.trim(),
      enabled: request.enabled,
      setting: request.setting,
    );
    _routes.add(route);
    return route;
  }

  @override
  Future<CommuteRoute> updateCommuteRoute(
    String id,
    CommuteRouteRequest request,
  ) async {
    final index = _routes.indexWhere((r) => r.id == id);
    if (index == -1) {
      throw _notFound();
    }
    _validateRoute(request, id);
    final route = CommuteRoute(
      id: id,
      label: request.label.trim(),
      enabled: request.enabled,
      setting: request.setting,
    );
    _routes[index] = route;
    return route;
  }

  @override
  Future<void> deleteCommuteRoute(String id) async {
    final index = _routes.indexWhere((r) => r.id == id);
    if (index == -1) {
      throw _notFound();
    }
    _routes.removeAt(index);
  }

  @override
  Future<ArrivalsResponse> getArrivals([String? routeId]) async {
    final route = routeId == null
        ? (_routes.isEmpty ? null : _routes.first)
        : _routes.where((r) => r.id == routeId).firstOrNull;
    if (route == null) {
      throw _notFound();
    }
    return _arrivalsFor(route.setting);
  }

  @override
  Future<List<StopSearchResult>> searchStops(String query) async {
    final trimmed = query.trim();
    if (trimmed.length < 2) {
      throw _invalid('검색어는 2자 이상이어야 합니다');
    }
    // 정확 일치 우선, 나머지는 카탈로그 순서 유지 (§5-1)
    final matched = _mockStops
        .where((stop) => stop.displayName.contains(trimmed))
        .toList()
      ..sort(
        (a, b) => (b.displayName == trimmed ? 1 : 0) -
            (a.displayName == trimmed ? 1 : 0),
      );
    final perSource = <StopType, int>{};
    final results = <StopSearchResult>[];
    for (final stop in matched) {
      final count = perSource[stop.type] ?? 0;
      if (count >= _maxResultsPerSource) {
        continue;
      }
      perSource[stop.type] = count + 1;
      results.add(stop.searchResult);
    }
    return results;
  }

  @override
  Future<List<RouteOption>> getStopRoutes(StopType type, String stopId) async {
    final stop = _mockStops
        .where((s) => s.type == type && s.stopId == stopId)
        .firstOrNull;
    if (stop == null) {
      throw _invalid('알 수 없는 정류장입니다: ${type.wire}/$stopId');
    }
    return List.of(stop.routes);
  }

  @override
  Future<List<GeocodeResult>> geocode(String query) async {
    final trimmed = query.trim();
    if (trimmed.length < 2) {
      throw _invalid('검색어는 2자 이상이어야 합니다');
    }
    return _mockAddresses
        .where(
          (address) =>
              address.roadAddress.contains(trimmed) ||
              address.jibunAddress.contains(trimmed),
        )
        .toList();
  }

  @override
  Future<void> registerPushToken(String token, String platform) async {
    if (token.isEmpty) {
      throw _invalid('token이 필요합니다');
    }
    // mock은 기록만 — 발송이 없으므로 저장소는 두지 않는다
  }

  /// §7-1 — 좌표 범위(수도권 대략) 검증 후 카탈로그에서 가장 가까운 주소를 돌려준다.
  /// 실서버는 NCP Reverse Geocoding 프록시 — mock은 확인 문구 UX 검증에 필요한 만큼만.
  @override
  Future<ReverseGeocodeResult> reverseGeocode(
    double latitude,
    double longitude,
  ) async {
    if (latitude < 33 || latitude > 39 || longitude < 124 || longitude > 132) {
      throw _invalid('좌표 범위를 벗어났습니다');
    }
    GeocodeResult? nearest;
    double best = double.infinity;
    for (final address in _mockAddresses) {
      final dLat = address.latitude - latitude;
      final dLng = address.longitude - longitude;
      final distance = dLat * dLat + dLng * dLng;
      if (distance < best) {
        best = distance;
        nearest = address;
      }
    }
    return ReverseGeocodeResult(
      roadAddress: nearest?.roadAddress ?? '',
      jibunAddress: nearest?.jibunAddress ?? '',
    );
  }

  @override
  Future<void> postBoardingFeedback(BoardingFeedbackRequest request) async {
    if (!_datePattern.hasMatch(request.notifiedDate)) {
      throw _invalid('notifiedDate는 YYYY-MM-DD 형식이어야 합니다');
    }
    _feedbackByDate[request.notifiedDate] = request.result;
  }

  /// §3-1 — 최근 5건 중 MISSED 2건 이상(표본 3건 이상)이면 +5분 제안 (서버 규칙과 동일)
  @override
  Future<BufferRecommendation> getBufferRecommendation() async {
    final dates = _feedbackByDate.keys.toList()..sort((a, b) => b.compareTo(a));
    final recent = dates.take(5).map((d) => _feedbackByDate[d]!).toList();
    final missedCount =
        recent.where((r) => r == BoardingResult.missed).length;
    return BufferRecommendation(
      recommend: recent.length >= 3 && missedCount >= 2,
      missedCount: missedCount,
      sampleSize: recent.length,
      suggestedIncrementMinutes: 5,
    );
  }
}