/// AdMob 초기화·광고 단위 ID — ADR-001 Platform View 허용 목록(광고) 안의 브리지.
///
/// ⚠️ 지금은 **구글 공식 테스트 ID**다 — 실수익은 오너가 AdMob 계정에서 앱·광고 단위를
/// 발급해 이 파일(과 AndroidManifest/Info.plist의 앱 ID)을 교체해야 시작된다.
/// 교체 지점은 이 파일 하나 + 플랫폼 설정 두 파일뿐이어야 한다.
library;

import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

class Ads {
  /// `--dart-define=DISABLE_ADS=true` — 광고 SDK를 아예 켜지 않는 개발·데모 플래그.
  /// AdMob의 WebView 초기화가 SIGSEGV로 죽는 에뮬레이터 이미지에서 릴리즈 실행용
  /// (2026-09-16 실측: android-VanillaIceCream + GMS 25.22 조합). 기본값 false — 실빌드 무관
  static const bool disabled = bool.fromEnvironment('DISABLE_ADS');

  /// 앱 시작 시 1회 — 실패해도 본편은 동작해야 하므로 삼킨다 (광고만 안 나오는 강등)
  static Future<void> init() async {
    if (disabled) {
      return;
    }
    try {
      await MobileAds.instance.initialize();
    } catch (error) {
      developer.log('admob init failed: $error', name: 'ads');
    }
  }

  /// 배너 광고 단위 — TODO(오너): AdMob 발급 후 실ID로 교체
  static String get bannerUnitId => switch (defaultTargetPlatform) {
    TargetPlatform.iOS => 'ca-app-pub-3940256099942544/2934735716',
    _ => 'ca-app-pub-3940256099942544/6300978111',
  };
}
