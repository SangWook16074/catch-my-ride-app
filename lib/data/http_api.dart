/// API.md 계약의 실서버 클라이언트 — catchmyride.hansw.dev.
/// 인증: §8-3 익명 키 (`Authorization: Bearer anon:{key}`, AnonymousKeyStore).
/// JSON ↔ domain 모델 변환은 전부 이 파일에서 한다 (CLAUDE.md: data는 domain 모델로 넘긴다).
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/journey.dart';
import '../domain/models.dart';
import 'api.dart';
import 'auth.dart';

class HttpNochijimaApi implements NochijimaApi {
  HttpNochijimaApi({
    required this.baseUrl,
    required this._keyStore,
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String baseUrl;
  final AnonymousKeyStore _keyStore;
  final http.Client _client;

  static const Duration _timeout = Duration(seconds: 15);

  Future<Map<String, String>> _headers() async {
    final key = await _keyStore.getOrCreate();
    return {
      'Authorization': 'Bearer anon:$key',
      'Content-Type': 'application/json; charset=utf-8',
    };
  }

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse('$baseUrl$path').replace(queryParameters: query);

  /// 2xx가 아니면 공통 에러 응답({code,message})을 ApiException으로 변환한다
  dynamic _decode(http.Response response) {
    final body = utf8.decode(response.bodyBytes);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return body.isEmpty ? null : jsonDecode(body);
    }
    String code = 'HTTP_${response.statusCode}';
    String message = '요청이 실패했습니다';
    try {
      final error = jsonDecode(body) as Map<String, dynamic>;
      code = error['code'] as String? ?? code;
      message = error['message'] as String? ?? message;
    } catch (_) {
      // 비 JSON 에러 바디(프록시 502 등) — 상태 코드 기반 코드 유지
    }
    throw ApiException(response.statusCode, code, message);
  }

  Future<dynamic> _get(String path, [Map<String, String>? query]) async =>
      _decode(
        await _client
            .get(_uri(path, query), headers: await _headers())
            .timeout(_timeout),
      );

  Future<dynamic> _send(
    String method,
    String path, [
    Object? jsonBody,
  ]) async {
    final headers = await _headers();
    final uri = _uri(path);
    final body = jsonBody == null ? null : jsonEncode(jsonBody);
    final response = switch (method) {
      'POST' => await _client
          .post(uri, headers: headers, body: body)
          .timeout(_timeout),
      'PUT' => await _client
          .put(uri, headers: headers, body: body)
          .timeout(_timeout),
      'DELETE' => await _client
          .delete(uri, headers: headers)
          .timeout(_timeout),
      _ => throw ArgumentError(method),
    };
    return _decode(response);
  }

  @override
  Future<List<CommuteRoute>> listCommuteRoutes() async {
    final json = await _get('/api/v1/commute-routes') as Map<String, dynamic>;
    return [
      for (final route in json['routes'] as List<dynamic>)
        _routeFromJson(route as Map<String, dynamic>),
    ];
  }

  @override
  Future<CommuteRoute> createCommuteRoute(CommuteRouteRequest request) async =>
      _routeFromJson(
        await _send('POST', '/api/v1/commute-routes', _requestToJson(request))
            as Map<String, dynamic>,
      );

  @override
  Future<CommuteRoute> updateCommuteRoute(
    String id,
    CommuteRouteRequest request,
  ) async => _routeFromJson(
    await _send('PUT', '/api/v1/commute-routes/$id', _requestToJson(request))
        as Map<String, dynamic>,
  );

  @override
  Future<void> deleteCommuteRoute(String id) =>
      _send('DELETE', '/api/v1/commute-routes/$id');

  @override
  Future<ArrivalsResponse> getArrivals([String? routeId]) async {
    final json = await _get('/api/v1/arrivals', {
      'routeId': ?routeId,
    }) as Map<String, dynamic>;
    return ArrivalsResponse(
      fetchedAt: json['fetchedAt'] as String,
      realtimeAvailable: json['realtimeAvailable'] as bool,
      walkMinutes: (json['walkMinutes'] as num).toInt(),
      arrivals: [
        for (final arrival in json['arrivals'] as List<dynamic>)
          _arrivalFromJson(arrival as Map<String, dynamic>),
      ],
    );
  }

  @override
  Future<void> postBoardingFeedback(BoardingFeedbackRequest request) =>
      _send('POST', '/api/v1/boarding-feedback', {
        'result': request.result.wire,
        'notifiedDate': request.notifiedDate,
      });

  @override
  Future<BufferRecommendation> getBufferRecommendation() async {
    final json =
        await _get('/api/v1/buffer-recommendation') as Map<String, dynamic>;
    return BufferRecommendation(
      recommend: json['recommend'] as bool,
      missedCount: (json['missedCount'] as num).toInt(),
      sampleSize: (json['sampleSize'] as num).toInt(),
      suggestedIncrementMinutes:
          (json['suggestedIncrementMinutes'] as num).toInt(),
    );
  }

  @override
  Future<List<FeedbackEntry>> getFeedbackHistory({int limit = 60}) async {
    final json =
        await _get('/api/v1/boarding-feedback/history', {'limit': '$limit'})
            as Map<String, dynamic>;
    return [
      for (final entry in json['entries'] as List<dynamic>)
        FeedbackEntry(
          date: (entry as Map<String, dynamic>)['date'] as String,
          result: BoardingResult.fromWire(entry['result'] as String),
        ),
    ];
  }

  @override
  Future<List<StopSearchResult>> searchStops(String query) async {
    final json =
        await _get('/api/v1/stops/search', {'query': query})
            as Map<String, dynamic>;
    return [
      for (final result in json['results'] as List<dynamic>)
        StopSearchResult(
          type: _stopTypeFromWire(
            (result as Map<String, dynamic>)['type'] as String,
          ),
          stopId: result['stopId'] as String,
          displayName: result['displayName'] as String,
          subtitle: result['subtitle'] as String? ?? '',
        ),
    ];
  }

  @override
  Future<List<RouteOption>> getStopRoutes(StopType type, String stopId) async {
    final json = await _get('/api/v1/stops/routes', {
      'type': type.wire,
      'stopId': stopId,
    }) as Map<String, dynamic>;
    return [
      for (final route in json['routes'] as List<dynamic>)
        RouteOption(
          name: (route as Map<String, dynamic>)['name'] as String,
          isExpress: route['isExpress'] as bool?,
          directionLabel: route['directionLabel'] as String?,
        ),
    ];
  }

  @override
  Future<List<DirectionOption>> getStopDirections(
    String stopId,
    String route,
  ) async {
    final json = await _get('/api/v1/stops/directions', {
      'stopId': stopId,
      'route': route,
    }) as Map<String, dynamic>;
    return [
      for (final direction in json['directions'] as List<dynamic>)
        DirectionOption(
          key: (direction as Map<String, dynamic>)['key'] as String,
          label: direction['label'] as String? ?? direction['key'] as String,
        ),
    ];
  }

  @override
  Future<List<GeocodeResult>> geocode(String query) async {
    final json =
        await _get('/api/v1/geocode', {'query': query}) as Map<String, dynamic>;
    return [
      for (final result in json['results'] as List<dynamic>)
        GeocodeResult(
          roadAddress:
              (result as Map<String, dynamic>)['roadAddress'] as String? ?? '',
          jibunAddress: result['jibunAddress'] as String? ?? '',
          latitude: (result['latitude'] as num).toDouble(),
          longitude: (result['longitude'] as num).toDouble(),
        ),
    ];
  }

  @override
  Future<void> registerPushToken(String token, String platform) =>
      _send('PUT', '/api/v1/push-token', {
        'token': token,
        'platform': platform,
      });

  @override
  Future<ReverseGeocodeResult> reverseGeocode(
    double latitude,
    double longitude,
  ) async {
    final json = await _get('/api/v1/reverse-geocode', {
      'latitude': '$latitude',
      'longitude': '$longitude',
    }) as Map<String, dynamic>;
    return ReverseGeocodeResult(
      roadAddress: json['roadAddress'] as String? ?? '',
      jibunAddress: json['jibunAddress'] as String? ?? '',
    );
  }

  // §9 하차 알림 — 서버 미구현 단계에선 404가 내려온다 (UI가 "준비 중"으로 강등)

  @override
  Future<List<Journey>> listJourneys() async {
    final json = await _get('/api/v1/journeys') as Map<String, dynamic>;
    return [
      for (final journey in json['journeys'] as List<dynamic>)
        _journeyFromJson(journey as Map<String, dynamic>),
    ];
  }

  @override
  Future<Journey> createJourney(JourneyRequest request) async =>
      _journeyFromJson(
        await _send('POST', '/api/v1/journeys', _journeyRequestToJson(request))
            as Map<String, dynamic>,
      );

  @override
  Future<Journey> updateJourney(String id, JourneyRequest request) async =>
      _journeyFromJson(
        await _send('PUT', '/api/v1/journeys/$id', _journeyRequestToJson(request))
            as Map<String, dynamic>,
      );

  @override
  Future<void> deleteJourney(String id) => _send('DELETE', '/api/v1/journeys/$id');

  @override
  Future<TripStart> startTrip(String journeyId, {TripFix? at}) async {
    final json =
        await _send('POST', '/api/v1/journeys/$journeyId/trips', _fixBody(at))
            as Map<String, dynamic>;
    return TripStart(
      tripId: json['tripId'] as String,
      startedAt: json['startedAt'] as String,
    );
  }

  @override
  Future<TripStart> startTripWithLegs(List<JourneyLeg> legs, {TripFix? at}) async {
    final json =
        await _send('POST', '/api/v1/trips', {
              'legs': [for (final leg in legs) leg.toJson()],
              ...?_fixBody(at),
            })
            as Map<String, dynamic>;
    return TripStart(
      tripId: json['tripId'] as String,
      startedAt: json['startedAt'] as String,
    );
  }

  @override
  Future<TripStatus> getTrip(String tripId) async =>
      _tripStatusFromJson(await _get('/api/v1/trips/$tripId') as Map<String, dynamic>);

  @override
  Future<TripStatus> advanceTripLeg(String tripId, {TripFix? at}) async =>
      _tripStatusFromJson(
        await _send('POST', '/api/v1/trips/$tripId/next-leg', _fixBody(at))
            as Map<String, dynamic>,
      );

  /// §9-2 위치 필드 — 측위에 실패했으면 아예 보내지 않는다 (서버는 없으면 기존 동작)
  Map<String, dynamic>? _fixBody(TripFix? at) =>
      at == null ? null : {'location': at.toJson()};

  @override
  Future<void> endTrip(String tripId) => _send('DELETE', '/api/v1/trips/$tripId');
}

// ---- JSON ↔ domain 변환 ----

StopType _stopTypeFromWire(String wire) =>
    StopType.values.firstWhere((t) => t.wire == wire);

DayOfWeek _dayFromWire(String wire) =>
    DayOfWeek.values.firstWhere((d) => d.wire == wire);

NotificationMode _modeFromWire(String wire) =>
    NotificationMode.values.firstWhere((m) => m.wire == wire);

ArrivalStatus _statusFromWire(String wire) => switch (wire) {
  'RELAXED' => ArrivalStatus.relaxed,
  'HURRY' => ArrivalStatus.hurry,
  _ => ArrivalStatus.missed,
};

Journey _journeyFromJson(Map<String, dynamic> json) => Journey(
  id: json['id'] as String,
  label: json['label'] as String,
  repeatDays: [
    for (final day in json['repeatDays'] as List<dynamic>? ?? const [])
      _dayFromWire(day as String),
  ],
  legs: [
    for (final leg in json['legs'] as List<dynamic>)
      JourneyLeg(
        line: (leg as Map<String, dynamic>)['line'] as String,
        boardStop: leg['boardStop'] as String,
        alightStop: leg['alightStop'] as String,
      ),
  ],
  lastUsedAt: json['lastUsedAt'] as String?,
);

Map<String, dynamic> _journeyRequestToJson(JourneyRequest request) => {
  'label': request.label,
  'repeatDays': [for (final day in request.repeatDays) day.wire],
  'legs': [for (final leg in request.legs) leg.toJson()],
};

TripStatus _tripStatusFromJson(Map<String, dynamic> json) => TripStatus(
  phase: TripPhase.fromWire(json['phase'] as String),
  legIndex: (json['legIndex'] as num).toInt(),
  remainingStops: (json['remainingStops'] as num?)?.toInt(),
  currentStop: json['currentStop'] as String?,
  eventStop: json['eventStop'] as String,
  realtimeAvailable: json['realtimeAvailable'] as bool? ?? true,
  fetchedAt: json['fetchedAt'] as String,
);

CommuteRoute _routeFromJson(Map<String, dynamic> json) => CommuteRoute(
  id: json['id'] as String,
  label: json['label'] as String,
  enabled: json['enabled'] as bool,
  setting: _settingFromJson(json['setting'] as Map<String, dynamic>),
);

CommuteSetting _settingFromJson(Map<String, dynamic> json) {
  final home = json['home'] as Map<String, dynamic>;
  final window = json['commuteWindow'] as Map<String, dynamic>?;
  return CommuteSetting(
    home: GeoPoint(
      latitude: (home['latitude'] as num).toDouble(),
      longitude: (home['longitude'] as num).toDouble(),
    ),
    stops: [
      for (final stop in json['stops'] as List<dynamic>)
        CommuteStop(
          type: _stopTypeFromWire(
            (stop as Map<String, dynamic>)['type'] as String,
          ),
          stopId: stop['stopId'] as String,
          displayName: stop['displayName'] as String,
          routes: [for (final r in stop['routes'] as List<dynamic>) r as String],
          // v0.4 방면 키 — 구버전 경로는 누락/null(전 방면)
          direction: stop['direction'] as String?,
        ),
    ],
    walkMinutes: (json['walkMinutes'] as num).toInt(),
    notificationMode: _modeFromWire(json['notificationMode'] as String),
    fixedDepartureTime: json['fixedDepartureTime'] as String?,
    commuteWindow: window == null
        ? null
        : CommuteWindow(
            start: window['start'] as String,
            end: window['end'] as String,
          ),
    bufferMinutes: (json['bufferMinutes'] as num).toInt(),
    activeDays: [
      for (final day in json['activeDays'] as List<dynamic>)
        _dayFromWire(day as String),
    ],
  );
}

Map<String, dynamic> _settingToJson(CommuteSetting setting) => {
  'home': {
    'latitude': setting.home.latitude,
    'longitude': setting.home.longitude,
  },
  'stops': [
    for (final stop in setting.stops)
      {
        'type': stop.type.wire,
        'stopId': stop.stopId,
        'displayName': stop.displayName,
        'routes': stop.routes,
        'direction': stop.direction,
      },
  ],
  'walkMinutes': setting.walkMinutes,
  'notificationMode': setting.notificationMode.wire,
  'fixedDepartureTime': setting.fixedDepartureTime,
  'commuteWindow': setting.commuteWindow == null
      ? null
      : {
          'start': setting.commuteWindow!.start,
          'end': setting.commuteWindow!.end,
        },
  'bufferMinutes': setting.bufferMinutes,
  'activeDays': [for (final day in setting.activeDays) day.wire],
};

Map<String, dynamic> _requestToJson(CommuteRouteRequest request) => {
  'label': request.label,
  'enabled': request.enabled,
  'setting': _settingToJson(request.setting),
};

Arrival _arrivalFromJson(Map<String, dynamic> json) => Arrival(
  stopDisplayName: json['stopDisplayName'] as String,
  routeName: json['routeName'] as String,
  directionLabel: json['directionLabel'] as String?,
  secondsToArrival: (json['secondsToArrival'] as num?)?.toInt(),
  remainingStops: (json['remainingStops'] as num?)?.toInt(),
  isExpress: json['isExpress'] as bool?,
  boardable: json['boardable'] as bool,
  status: _statusFromWire(json['status'] as String),
  rawMessage: json['rawMessage'] as String?,
);
