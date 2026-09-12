/// API.md 계약의 클라이언트 인터페이스 (CLAUDE.md: data는 domain 모델로 변환해서 넘긴다).
///
/// 기본은 실서버(catchmyride.hansw.dev, §8-3 익명 키 인증).
/// 서버 없이 개발할 때는 `flutter run --dart-define=USE_MOCK=true`로 mock을 쓴다.
library;

import '../domain/models.dart';
import 'auth.dart';
import 'http_api.dart';
import 'mock_api.dart';

abstract interface class NochijimaApi {
  /// §1-2 — 통근 경로 목록 (생성순, 첫 경로가 기본)
  Future<List<CommuteRoute>> listCommuteRoutes();

  /// §1-2 — 경로 생성. 6개째·중복 라벨은 400 INVALID_REQUEST
  Future<CommuteRoute> createCommuteRoute(CommuteRouteRequest request);

  Future<CommuteRoute> updateCommuteRoute(
    String id,
    CommuteRouteRequest request,
  );

  Future<void> deleteCommuteRoute(String id);

  /// §2 — routeId 생략 시 첫 경로 기준
  Future<ArrivalsResponse> getArrivals([String? routeId]);

  Future<void> postBoardingFeedback(BoardingFeedbackRequest request);

  /// §3-1 — 최근 놓침이 잦으면 버퍼 +5분 제안. 적용은 §1-2c 경로 수정으로
  Future<BufferRecommendation> getBufferRecommendation();

  /// §5-1 — query 2자 미만이면 400 INVALID_REQUEST. 온보딩 중 설정 없이도 호출 가능
  Future<List<StopSearchResult>> searchStops(String query);

  /// §5-2 — 선택한 정류장/역의 경유 노선 목록
  Future<List<RouteOption>> getStopRoutes(StopType type, String stopId);

  /// §7 — 주소 → 좌표. query 2자 미만이면 400 INVALID_REQUEST. 결과 없으면 빈 배열
  Future<List<GeocodeResult>> geocode(String query);

  /// §7-1 — 좌표 → 주소. GPS 등록 직후 확인 문구용, 표시 전용(실패해도 등록 흐름 계속).
  /// 좌표 범위 밖이면 400 INVALID_REQUEST
  Future<ReverseGeocodeResult> reverseGeocode(double latitude, double longitude);

  /// §4-1 — 스토어판 FCM 토큰 등록·갱신 (멱등). platform: "IOS" | "ANDROID"
  Future<void> registerPushToken(String token, String platform);
}

/// API.md 공통 Base URL — 지도 미리보기(§6) 이미지 URL도 여기서 만든다
const String apiBaseUrl = 'https://catchmyride.hansw.dev';

/// `--dart-define=USE_MOCK=true`면 mock (오프라인 개발·데모용)
const bool useMockApi = bool.fromEnvironment('USE_MOCK');

/// 앱 전역 API 싱글턴 — 테스트에서만 mock으로 교체한다 (widget test가 실서버를 부르지 않게)
NochijimaApi api = useMockApi
    ? MockNochijimaApi()
    : HttpNochijimaApi(baseUrl: apiBaseUrl, keyStore: AnonymousKeyStore());

/// API.md §6 — 네이버 Static Map 프록시 이미지 URL (집 위치 미리보기).
/// fetch가 아니라 Image.network로 바로 쓰는 URL이라 NochijimaApi 메서드가 아닌 헬퍼로 둔다
/// (미니앱 src/api/index.ts mapPreviewUri와 동일한 이유).
String mapPreviewUrl(
  GeoPoint point, {
  int width = 600,
  int height = 320,
  int level = 16,
}) =>
    '$apiBaseUrl/api/v1/map-preview'
    '?lat=${point.latitude}&lng=${point.longitude}'
    '&w=$width&h=$height&level=$level';
