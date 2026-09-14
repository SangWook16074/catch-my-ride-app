/// 하차 알림 트립 시스템 표면 브리지 — MethodChannel 래퍼 (FR-705).
/// CLAUDE.md 레이어 규칙: 채널은 platform/에서만 만진다.
///
/// iOS 16.1+ = 잠금화면 Live Activity(`ios/Runner/LiveActivityBridge.swift`),
/// Android = 잠금화면 지속(ongoing) 알림(`TripNotificationBridge.kt`) — 같은 채널·계약.
/// 미지원 환경·설정 꺼짐·테스트는 조용히 무시된다 (부가 기능이 트립 본편을 막지 않는다).
/// 갱신 값은 트립 폴링(§9-3)이 공급 — 표면은 표시만 (ADR-001).
/// 한계(v1): 앱이 살아 있는 동안만 갱신된다 — 서버 푸시 갱신은 후속.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import '../domain/journey.dart';

class LiveActivityBridge {
  static const MethodChannel _channel = MethodChannel(
    'catchmyride/live_activity',
  );

  /// tripId는 Android 알림 탭 딥링크(catchmyride://trip?tripId=…)용 — iOS는 무시
  Future<void> start(String journeyLabel, {required String tripId}) =>
      _invoke('start', {'journeyLabel': journeyLabel, 'tripId': tripId});

  Future<void> update(TripStatus status) => _invoke('update', {
    'eventStop': status.eventStop,
    'remainingStops': status.remainingStops,
    'phase': status.phase.wire,
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
