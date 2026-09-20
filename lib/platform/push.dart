/// 푸시(FCM) 브리지 — firebase_messaging 플러그인 래퍼.
/// CLAUDE.md 레이어 규칙: 네이티브 브리지(플러그인)는 platform/에서만 만진다.
///
/// 설계 규칙 (TODO 2026-09-09, 미니앱 실측 사고에서 이식):
/// 1) 권한 다이얼로그를 다른 다이얼로그와 연속으로 띄우지 않는다 — 호출 시점은 UI가 정한다
/// 2) 상태를 단계별로 확인하고 결과를 로깅해 조용한 실패를 남기지 않는다
/// 3) "성공 응답 ≠ 실제 전달" — 전달 확인은 서버 발송 로그 책임, 여기선 토큰 확보까지만
library;

import 'dart:async';
import 'dart:developer' as developer;

import 'package:firebase_messaging/firebase_messaging.dart';

/// 권한 요청 결과 — 로깅·재시도 판단용
enum PushPermission { granted, denied, error }

class PushBridge {
  FirebaseMessaging get _messaging => FirebaseMessaging.instance;

  /// 알림 권한 요청. iOS는 최초 1회만 시스템 다이얼로그가 뜨고
  /// 이후 호출은 현재 상태를 조용히 반환한다 — 저장할 때마다 불러도 스팸이 아니다
  /// (미니앱 requestPushConsent의 alreadyAgreed 동작과 동일한 성격).
  Future<PushPermission> requestPermission() async {
    try {
      final settings = await _messaging.requestPermission();
      final status = settings.authorizationStatus;
      developer.log('push permission: $status', name: 'push');
      return switch (status) {
        AuthorizationStatus.authorized ||
        AuthorizationStatus.provisional => PushPermission.granted,
        _ => PushPermission.denied,
      };
    } catch (error) {
      developer.log('push permission error: $error', name: 'push');
      return PushPermission.error;
    }
  }

  /// iOS 포그라운드 표시 — 기본값은 앱이 떠 있으면 FCM 배너를 조용히 삼킨다.
  /// 트립 화면을 보는 중에도 하차·환승 푸시(§9-4)가 배너·소리로 보여야 하므로 켠다
  /// (2026-09-19 실주행: 환승 푸시가 "안 온 것처럼" 보인 원인).
  /// Android는 이 옵션의 영향이 없다(포그라운드 표면은 트립 지속 알림 담당) — 호출 무해
  Future<void> enableForegroundBanners() async {
    try {
      await _messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        sound: true,
      );
    } catch (error) {
      developer.log('push foreground presentation error: $error', name: 'push');
    }
  }

  /// 현재 권한 상태 확인 — 다이얼로그를 띄우지 않는다 (앱 시작 시 동기화용)
  Future<bool> isAuthorized() async {
    try {
      final settings = await _messaging.getNotificationSettings();
      return settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;
    } catch (_) {
      return false;
    }
  }

  /// FCM 등록 토큰 — 실패(APNs 미준비 등)는 null. 호출부가 재시도를 정한다
  Future<String?> getToken() async {
    try {
      return await _messaging.getToken();
    } catch (error) {
      developer.log('push token error: $error', name: 'push');
      return null;
    }
  }

  /// 토큰 로테이션 — 서버 재등록 트리거
  Stream<String> get onTokenRefresh => _messaging.onTokenRefresh;

  /// 알림 탭으로 앱이 열렸을 때의 딥링크(data.link) 스트림.
  /// 서버가 §4-1대로 `catchmyride://open?from=push&notifiedDate=…`를 실어준다 —
  /// 커스텀 스킴 딥링크와 같은 파서(parsePushEntry)를 태운다.
  Stream<Uri> get openedLinks {
    try {
      final controller = StreamController<Uri>();
      // 콜드 스타트: 알림 탭으로 앱이 시작된 경우
      unawaited(
        _messaging.getInitialMessage().then((message) {
          final uri = _linkOf(message);
          if (uri != null) {
            controller.add(uri);
          }
        }),
      );
      // 웜: 백그라운드에서 알림 탭으로 복귀
      FirebaseMessaging.onMessageOpenedApp.listen((message) {
        final uri = _linkOf(message);
        if (uri != null) {
          controller.add(uri);
        }
      });
      return controller.stream;
    } catch (error) {
      // Firebase 미초기화(테스트 등) — 푸시 딥링크만 비활성, 앱은 계속 동작
      developer.log('push openedLinks unavailable: $error', name: 'push');
      return const Stream<Uri>.empty();
    }
  }

  static Uri? _linkOf(RemoteMessage? message) {
    final link = message?.data['link'];
    return link is String ? Uri.tryParse(link) : null;
  }
}
