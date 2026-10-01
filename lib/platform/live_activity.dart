/// 하차 알림 트립 시스템 표면 브리지 — MethodChannel 래퍼 (FR-705).
/// CLAUDE.md 레이어 규칙: 채널은 platform/에서만 만진다.
///
/// iOS 16.1+ = 잠금화면 Live Activity(`ios/Runner/LiveActivityBridge.swift`),
/// Android = 잠금화면 지속(ongoing) 알림(`TripNotificationBridge.kt`) — 같은 채널·계약.
/// 미지원 환경·설정 꺼짐·테스트는 조용히 무시된다 (부가 기능이 트립 본편을 막지 않는다).
/// 갱신 값은 트립 폴링(§9-3)이 공급 — 표면은 표시만 (ADR-001).
/// v0.12부터 서버가 상태 변화 시 직접 갱신한다(§9-5) — 클라 폴링은 앱이 앞에 있을 때의 보조로
/// 남는다. iOS는 Live Activity push token을 이 채널로 **역방향** 전달받아(네이티브 →
/// Flutter) `data/active_trip.dart`가 서버에 등록한다 — 토큰 등록 오케스트레이션은
/// data 레이어 몫이라 여기는 스트림만 내보낸다(CLAUDE.md 레이어 규칙).
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import '../domain/journey.dart';

class LiveActivityBridge {
  static const MethodChannel _channel = MethodChannel(
    'catchmyride/live_activity',
  );

  LiveActivityBridge() {
    if (Platform.isIOS) {
      _channel.setMethodCallHandler(_handleCall);
    }
  }

  final StreamController<String> _pushTokenController =
      StreamController<String>.broadcast();

  /// iOS Live Activity push token(hex) — `Activity.request(pushType: .token)` 직후,
  /// 이후 `pushTokenUpdates`(회전 포함)마다 네이티브가 `pushTokenUpdated`로 올려준다 (§9-5 v0.12).
  /// Android는 호출되지 않는다(§4-1 FCM 토큰을 그대로 쓴다)
  Stream<String> get pushTokenUpdates => _pushTokenController.stream;

  Future<dynamic> _handleCall(MethodCall call) async {
    if (call.method == 'pushTokenUpdated') {
      final token = call.arguments as String?;
      if (token != null && token.isNotEmpty) {
        _pushTokenController.add(token);
      }
    }
    return null;
  }

  /// tripId는 Android 알림 탭 딥링크(catchmyride://trip?tripId=…)용 — iOS는 무시
  Future<void> start(String journeyLabel, {required String tripId}) =>
      _invoke('start', {'journeyLabel': journeyLabel, 'tripId': tripId});

  /// currentStop = 열차 현재 위치 역명(§9-3, 모르면 null) — 잠금화면에 "현재 ○○ 부근" (오너 요청 2026-09-21)
  Future<void> update(TripStatus status) => _invoke('update', {
    'eventStop': status.eventStop,
    'remainingStops': status.remainingStops,
    'phase': status.phase.wire,
    'currentStop': status.currentStop,
  });

  Future<void> end() => _invoke('end', null);

  Future<void> _invoke(String method, Map<String, Object?>? arguments) async {
    if (!Platform.isIOS && !Platform.isAndroid) {
      return;
    }
    try {
      await _channel.invokeMethod<bool>(method, arguments);
    } catch (_) {
      // 채널 부재(테스트)·플랫폼 오류 — 부가 기능이라 조용히 무시
    }
  }
}
