/// 하차 알림 트립 Live Activity 브리지 — MethodChannel 래퍼 (FR-705).
/// CLAUDE.md 레이어 규칙: 채널은 platform/에서만 만진다.
///
/// iOS 16.1+ 전용 — Android·미지원 iOS·설정 꺼짐은 조용히 false/무시된다
/// (잠금화면 표시는 부가 기능, 트립 본편 흐름을 막지 않는다).
/// 갱신 값은 트립 폴링(§9-3)이 공급 — 위젯은 표시만 (ADR-001).
/// 한계(v1): 앱이 살아 있는 동안만 갱신된다 — 서버 푸시(ActivityKit push) 갱신은 후속.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import '../domain/journey.dart';

class LiveActivityBridge {
  static const MethodChannel _channel = MethodChannel(
    'catchmyride/live_activity',
  );

  Future<void> start(String journeyLabel) => _invoke('start', {
    'journeyLabel': journeyLabel,
  });

  Future<void> update(TripStatus status) => _invoke('update', {
    'eventStop': status.eventStop,
    'remainingStops': status.remainingStops,
    'phase': status.phase.wire,
  });

  Future<void> end() => _invoke('end', null);

  Future<void> _invoke(String method, Map<String, Object?>? arguments) async {
    if (!Platform.isIOS) {
      return;
    }
    try {
      await _channel.invokeMethod<bool>(method, arguments);
    } catch (_) {
      // 채널 부재(테스트)·플랫폼 오류 — 부가 기능이라 조용히 무시
    }
  }
}
