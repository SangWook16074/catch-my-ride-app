/// FCM 토큰을 서버(§4-1)에 등록하는 오케스트레이터.
///
/// 호출 시점 두 곳:
/// - 온보딩 저장 직후: [ensureRegistered] — 알림을 받으려고 설정한 직후가 동의를 구할
///   가장 자연스러운 시점 (미니앱 requestPushConsent와 동일). 권한 다이얼로그 → 토큰 → 등록.
/// - 앱 시작: [syncIfAuthorized] — 다이얼로그 없이, 이미 허용된 경우에만 토큰을 재등록해
///   로테이션·재설치를 따라잡는다. onTokenRefresh도 여기서 구독한다.
///
/// 결과는 전부 로깅한다 — "조용한 실패 금지" (TODO 2026-09-09 규칙).
library;

import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io' show Platform;

import '../platform/push.dart';
import 'api.dart';

class PushRegistrar {
  PushRegistrar({PushBridge? bridge}) : _bridge = bridge ?? PushBridge();

  final PushBridge _bridge;
  StreamSubscription<String>? _refreshSub;

  static String get _platformWire => Platform.isIOS ? 'IOS' : 'ANDROID';

  /// 온보딩 저장 직후 — 권한 요청(필요 시 다이얼로그) → 토큰 등록.
  /// 거부·실패여도 앱 사용은 계속돼야 하므로 throw하지 않는다.
  Future<void> ensureRegistered() async {
    final permission = await _bridge.requestPermission();
    if (permission != PushPermission.granted) {
      developer.log('push register skipped: $permission', name: 'push');
      return;
    }
    await _registerToken();
  }

  /// 앱 시작 — 다이얼로그 없이 상태 동기화 + 토큰 로테이션 구독
  Future<void> syncIfAuthorized() async {
    // iOS: 앱이 떠 있어도 하차·환승 푸시(§9-4)가 배너로 보이게 (권한과 무관한 표시 옵션)
    unawaited(_bridge.enableForegroundBanners());
    _refreshSub ??= _bridge.onTokenRefresh.listen((_) {
      unawaited(_registerToken());
    });
    if (await _bridge.isAuthorized()) {
      await _registerToken();
    }
  }

  /// 서버 등록 — 일시 실패는 1회 재시도, 결과 로깅
  Future<void> _registerToken() async {
    final token = await _bridge.getToken();
    if (token == null) {
      developer.log('push register skipped: no token', name: 'push');
      return;
    }
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        await api.registerPushToken(token, _platformWire);
        developer.log('push token registered', name: 'push');
        return;
      } catch (error) {
        developer.log(
          'push token register failed (attempt ${attempt + 1}): $error',
          name: 'push',
        );
        if (attempt == 0) {
          await Future<void>.delayed(const Duration(seconds: 1));
        }
      }
    }
  }
}

/// 앱 전역 싱글턴
final PushRegistrar pushRegistrar = PushRegistrar();
