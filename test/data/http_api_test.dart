import 'dart:convert';

import 'package:catch_my_ride/data/auth.dart';
import 'package:catch_my_ride/data/http_api.dart';
import 'package:catch_my_ride/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 실서버 클라이언트의 요청 형태(경로·인증 헤더·바디)와 JSON ↔ domain 변환 검증.
// 네트워크 없이 MockClient로 API.md 예시 응답을 재생한다.

HttpNochijimaApi _api(MockClientHandler handler) => HttpNochijimaApi(
  baseUrl: 'https://catchmyride.hansw.dev',
  keyStore: AnonymousKeyStore(),
  client: MockClient(handler),
);

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

// API.md §1-2 CommuteSetting 스키마 예시 그대로
final Map<String, dynamic> _settingJson = {
  'home': {'latitude': 37.5219, 'longitude': 126.9245},
  'stops': [
    {
      'type': 'SEOUL_BUS',
      'stopId': '19284',
      'displayName': '여의도환승센터',
      'routes': ['720', '261'],
      'direction': null,
    },
    {
      'type': 'SUBWAY',
      'stopId': '수유',
      'displayName': '수유역',
      'routes': ['4호선'],
      'direction': '상행',
    },
  ],
  'walkMinutes': 8,
  'notificationMode': 'FIXED',
  'fixedDepartureTime': '08:20',
  'commuteWindow': null,
  'bufferMinutes': 3,
  'activeDays': ['MON', 'TUE'],
};

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'catch-my-ride/anon-key': 'test-anon-key-0001',
    });
  });

  test('익명 키를 Bearer anon:{key}로 보낸다 (§8-3)', () async {
    late http.Request captured;
    final api = _api((request) async {
      captured = request;
      return _json({'routes': []});
    });
    await api.listCommuteRoutes();
    expect(captured.url.path, '/api/v1/commute-routes');
    expect(
      captured.headers['Authorization'],
      'Bearer anon:test-anon-key-0001',
    );
  });

  test('경로 목록·생성 — 스키마 왕복 (§1-2)', () async {
    final api = _api((request) async {
      if (request.method == 'POST') {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        // 요청 바디가 API.md 스키마 그대로인지 — 서버 검증을 흉내
        expect(body['label'], '출근');
        expect(body['enabled'], isTrue);
        expect(body['setting'], _settingJson);
        return _json({
          'id': '550e8400-mock',
          'label': '출근',
          'enabled': true,
          'setting': _settingJson,
        }, 201);
      }
      return _json({
        'routes': [
          {
            'id': 'migrated',
            'label': '출근',
            'enabled': true,
            'setting': _settingJson,
          },
        ],
      });
    });

    final routes = await api.listCommuteRoutes();
    expect(routes.single.id, 'migrated');
    final setting = routes.single.setting;
    expect(setting.home, const GeoPoint(latitude: 37.5219, longitude: 126.9245));
    expect(setting.stops.first.type, StopType.seoulBus);
    expect(setting.stops.first.routes, ['720', '261']);
    expect(setting.stops.first.direction, isNull);
    // v0.4 지하철 방면 키 — 저장·조회 왕복
    expect(setting.stops.last.direction, '상행');
    expect(setting.notificationMode, NotificationMode.fixed);
    expect(setting.fixedDepartureTime, '08:20');
    expect(setting.commuteWindow, isNull);
    expect(setting.activeDays, [DayOfWeek.mon, DayOfWeek.tue]);

    final created = await api.createCommuteRoute(
      CommuteRouteRequest(label: '출근', enabled: true, setting: setting),
    );
    expect(created.id, '550e8400-mock');
  });

  test('도착 정보 — §2 응답 파싱 (direction 필드는 무시)', () async {
    final api = _api(
      (request) async => _json({
        'fetchedAt': '2026-08-27T08:05:31+09:00',
        'realtimeAvailable': true,
        'walkMinutes': 8,
        'arrivals': [
          {
            'stopDisplayName': '여의도환승센터',
            'routeName': '720',
            'direction': null,
            'secondsToArrival': 540,
            'remainingStops': 3,
            'isExpress': null,
            'boardable': true,
            'status': 'RELAXED',
            'rawMessage': '9분후[3번째 전]',
          },
          {
            'stopDisplayName': '여의도역',
            'routeName': '9호선 급행',
            'direction': '상행',
            'secondsToArrival': null,
            'remainingStops': null,
            'isExpress': true,
            'boardable': false,
            'status': 'MISSED',
            'rawMessage': null,
          },
        ],
      }),
    );
    final response = await api.getArrivals('route-1');
    expect(response.realtimeAvailable, isTrue);
    expect(response.arrivals.first.status, ArrivalStatus.relaxed);
    expect(response.arrivals.last.secondsToArrival, isNull);
    expect(response.arrivals.last.isExpress, isTrue);
  });

  test('공통 에러 응답을 ApiException으로 변환한다', () async {
    final api = _api(
      (request) async =>
          _json({'code': 'SETTING_NOT_FOUND', 'message': '통근 설정이 없습니다'}, 404),
    );
    expect(
      () => api.getArrivals(),
      throwsA(
        isA<ApiException>()
            .having((e) => e.status, 'status', 404)
            .having((e) => e.code, 'code', ApiException.settingNotFound),
      ),
    );
  });

  test('비 JSON 에러 바디(프록시 502 등)도 상태 코드로 던진다', () async {
    final api = _api(
      (request) async => http.Response('Bad Gateway', 502),
    );
    expect(
      () => api.listCommuteRoutes(),
      throwsA(isA<ApiException>().having((e) => e.status, 'status', 502)),
    );
  });

  test('검색·역지오코딩 — §5·§7-1 파싱', () async {
    final api = _api((request) async {
      if (request.url.path == '/api/v1/stops/search') {
        expect(request.url.queryParameters['query'], '여의도');
        return _json({
          'results': [
            {
              'type': 'SUBWAY',
              'stopId': '여의도',
              'displayName': '여의도역',
              'subtitle': '5호선 · 9호선',
            },
          ],
        });
      }
      return _json({'roadAddress': '', 'jibunAddress': '여의도동 23'});
    });
    final results = await api.searchStops('여의도');
    expect(results.single.type, StopType.subway);

    final address = await api.reverseGeocode(37.52, 126.92);
    expect(address.displayAddress, '여의도동 23');
  });

  test('지하철 방면 선택지 — §5-3 파싱, label 없으면 key로 폴백', () async {
    final api = _api((request) async {
      expect(request.url.path, '/api/v1/stops/directions');
      expect(request.url.queryParameters['stopId'], '수유');
      expect(request.url.queryParameters['route'], '4호선');
      return _json({
        'directions': [
          {'key': '상행', 'label': '당고개 방면'},
          {'key': '하행'},
        ],
      });
    });
    final directions = await api.getStopDirections('수유', '4호선');
    expect(directions, const [
      DirectionOption(key: '상행', label: '당고개 방면'),
      DirectionOption(key: '하행', label: '하행'),
    ]);
  });
}
