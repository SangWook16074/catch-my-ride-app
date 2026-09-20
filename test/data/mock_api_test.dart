import 'package:catch_my_ride/data/mock_api.dart';
import 'package:catch_my_ride/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

// 미니앱 src/api/__tests__/mock.test.ts 이식 — API.md 계약 검증 규칙.

const _setting = CommuteSetting(
  home: GeoPoint(latitude: 37.52, longitude: 126.92),
  stops: [
    CommuteStop(
      type: StopType.seoulBus,
      stopId: '19284',
      displayName: '여의도환승센터',
      routes: ['720'],
    ),
  ],
  walkMinutes: 8,
  notificationMode: NotificationMode.fixed,
  fixedDepartureTime: '07:40',
  commuteWindow: null,
  bufferMinutes: 2,
  activeDays: [DayOfWeek.mon],
);

CommuteRouteRequest _request({String label = '출근'}) =>
    CommuteRouteRequest(label: label, enabled: true, setting: _setting);

void main() {
  group('경로 CRUD (§1-2)', () {
    test('생성 → 목록 → 수정 → 삭제', () async {
      final api = MockNochijimaApi();
      expect(await api.listCommuteRoutes(), isEmpty);

      final created = await api.createCommuteRoute(_request());
      expect(created.label, '출근');
      expect((await api.listCommuteRoutes()).length, 1);

      final updated = await api.updateCommuteRoute(
        created.id,
        _request(label: '퇴근'),
      );
      expect(updated.label, '퇴근');

      await api.deleteCommuteRoute(created.id);
      expect(await api.listCommuteRoutes(), isEmpty);
    });

    test('중복 라벨·6개째·없는 id는 계약대로 거부한다', () async {
      final api = MockNochijimaApi();
      await api.createCommuteRoute(_request());
      expect(
        () => api.createCommuteRoute(_request()),
        throwsA(
          isA<ApiException>().having(
            (e) => e.code,
            'code',
            ApiException.invalidRequest,
          ),
        ),
      );
      for (var n = 2; n <= maxCommuteRoutes; n++) {
        await api.createCommuteRoute(_request(label: '경로 $n'));
      }
      expect(
        () => api.createCommuteRoute(_request(label: '경로 6')),
        throwsA(isA<ApiException>()),
      );
      expect(
        () => api.deleteCommuteRoute('ghost'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.code,
            'code',
            ApiException.settingNotFound,
          ),
        ),
      );
    });
  });

  group('도착 정보 (§2)', () {
    test('설정이 없으면 SETTING_NOT_FOUND', () {
      final api = MockNochijimaApi();
      expect(
        () => api.getArrivals(),
        throwsA(
          isA<ApiException>().having(
            (e) => e.code,
            'code',
            ApiException.settingNotFound,
          ),
        ),
      );
    });

    test('노선별 도착 목록이 남은 시간 오름차순으로 온다', () async {
      final api = MockNochijimaApi();
      await api.createCommuteRoute(_request());
      final response = await api.getArrivals();
      expect(response.walkMinutes, 8);
      expect(response.realtimeAvailable, isTrue);
      expect(response.arrivals, isNotEmpty);
      final seconds = response.arrivals
          .map((a) => a.secondsToArrival!)
          .toList();
      expect(seconds, List.of(seconds)..sort());
    });
  });

  group('검색 (§5)·지오코딩 (§7)', () {
    test('2자 미만은 400', () {
      final api = MockNochijimaApi();
      expect(() => api.searchStops('여'), throwsA(isA<ApiException>()));
      expect(() => api.geocode('여'), throwsA(isA<ApiException>()));
    });

    test('정류장 검색과 경유 노선 조회', () async {
      final api = MockNochijimaApi();
      final results = await api.searchStops('여의도');
      expect(results, isNotEmpty);
      final first = results.first;
      final routes = await api.getStopRoutes(first.type, first.stopId);
      expect(routes, isNotEmpty);
    });

    test('지하철 방면 선택지(§5-3) — 급행은 호선으로 접고, 모르는 노선은 폴백 키', () async {
      final api = MockNochijimaApi();
      final nine = await api.getStopDirections('여의도', '9호선 급행');
      expect(nine.map((d) => d.key), ['상행', '하행']);
      expect(nine.first.label, endsWith(' 방면'));
      final unknown = await api.getStopDirections('어딘가', '경춘선');
      expect(unknown, const [
        DirectionOption(key: '상행', label: '상행'),
        DirectionOption(key: '하행', label: '하행'),
      ]);
      final two = await api.getStopDirections('신도림', '2호선');
      expect(two.map((d) => d.key), ['내선', '외선']);
    });
  });

  group('방면 스코프 (§2 v0.4)', () {
    const subway = CommuteStop(
      type: StopType.subway,
      stopId: '여의도',
      displayName: '여의도역',
      routes: ['9호선 일반'],
    );

    test('저장 방면이 있으면 그 방면 열차만, 행선지 표기가 붙는다', () async {
      final api = MockNochijimaApi();
      await api.createCommuteRoute(
        CommuteRouteRequest(
          label: '출근',
          enabled: true,
          setting: CommuteSetting(
            home: _setting.home,
            stops: [subway.copyWith(direction: '상행')],
            walkMinutes: 8,
            notificationMode: NotificationMode.fixed,
            fixedDepartureTime: '07:40',
            commuteWindow: null,
            bufferMinutes: 2,
            activeDays: const [DayOfWeek.mon],
          ),
        ),
      );
      final response = await api.getArrivals();
      expect(response.arrivals, isNotEmpty);
      expect(
        response.arrivals.map((a) => a.directionLabel).toSet(),
        {'개화행'},
      );
    });

    test('방면 없는 구버전 경로는 전 방면 — 열차마다 행선지가 번갈아 온다', () async {
      final api = MockNochijimaApi();
      await api.createCommuteRoute(
        CommuteRouteRequest(
          label: '출근',
          enabled: true,
          setting: CommuteSetting(
            home: _setting.home,
            stops: const [subway],
            walkMinutes: 8,
            notificationMode: NotificationMode.fixed,
            fixedDepartureTime: '07:40',
            commuteWindow: null,
            bufferMinutes: 2,
            activeDays: const [DayOfWeek.mon],
          ),
        ),
      );
      final response = await api.getArrivals();
      expect(
        response.arrivals.map((a) => a.directionLabel).toSet(),
        {'개화행', '중앙보훈병원행'},
      );
    });
  });

  group('역지오코딩 (§7-1)', () {
    test('좌표 → 주소, 도로명 우선 표시', () async {
      final api = MockNochijimaApi();
      final result = await api.reverseGeocode(37.52, 126.92);
      expect(result.roadAddress, isNotEmpty);
      expect(result.displayAddress, result.roadAddress);
    });

    test('좌표 범위 밖이면 400 INVALID_REQUEST', () {
      final api = MockNochijimaApi();
      expect(
        () => api.reverseGeocode(0, 0),
        throwsA(
          isA<ApiException>().having(
            (e) => e.code,
            'code',
            ApiException.invalidRequest,
          ),
        ),
      );
    });

    test('둘 다 빈 문자열이면 displayAddress는 null — 일반 안내 문구로 강등', () {
      const empty = ReverseGeocodeResult(roadAddress: '', jibunAddress: '');
      expect(empty.displayAddress, isNull);
      const jibunOnly = ReverseGeocodeResult(
        roadAddress: '',
        jibunAddress: '서울특별시 영등포구 여의도동 23',
      );
      expect(jibunOnly.displayAddress, jibunOnly.jibunAddress);
    });
  });

  group('버퍼 추천 (§3-1)', () {
    test('표본 3건 이상 + 놓침 2건 이상이면 +5분 제안', () async {
      final api = MockNochijimaApi();
      expect((await api.getBufferRecommendation()).recommend, isFalse);

      Future<void> feedback(String date, BoardingResult result) =>
          api.postBoardingFeedback(
            BoardingFeedbackRequest(result: result, notifiedDate: date),
          );

      await feedback('2026-09-07', BoardingResult.missed);
      await feedback('2026-09-08', BoardingResult.missed);
      expect((await api.getBufferRecommendation()).recommend, isFalse);

      await feedback('2026-09-09', BoardingResult.boarded);
      final recommendation = await api.getBufferRecommendation();
      expect(recommendation.recommend, isTrue);
      expect(recommendation.missedCount, 2);
      expect(recommendation.sampleSize, 3);
      expect(recommendation.suggestedIncrementMinutes, 5);
    });
  });
}
