import 'dart:async';
import 'dart:developer' as developer;

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'data/push_registrar.dart';
import 'firebase_options.dart';
import 'platform/ads.dart';
import 'ui/design/theme.dart';
import 'ui/startup_gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // AdMob — 시작 비차단, 실패해도 본편 동작 (광고만 안 나온다)
  unawaited(Ads.init());
  // Firebase — 푸시(FCM) 기반. 초기화 실패(설정 파일 문제 등)해도 본편(라이브 뷰)은
  // 동작해야 하므로 앱을 죽이지 않는다 — 푸시만 못 받는 상태로 강등된다.
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    // 이미 허용된 유저의 토큰 로테이션·재설치를 따라잡는다 (다이얼로그 없음, 시작 비차단)
    unawaited(pushRegistrar.syncIfAuthorized());
  } catch (error) {
    developer.log('firebase init failed: $error', name: 'push');
  }
  runApp(const CatchMyRideApp());
}

/// 놓치지마 스토어판 — 시작은 StartupGate: 첫 실행에 경로가 없으면 바로 온보딩,
/// 이후에는 바텀 네비게이션 셸(메인·놓치지마·새로운 기능·내정보).
/// 놓치지마 탭의 플로우는 미니앱(catch_my_ride_appintoss)과 동일:
/// 라이브 뷰 ↔ 온보딩 7단계 위저드. 메인 탭은 각 섹션 요약(대시보드) 자리.
class CatchMyRideApp extends StatelessWidget {
  const CatchMyRideApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '놓치지마',
      theme: buildAppTheme(Brightness.light),
      darkTheme: buildAppTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      home: const StartupGate(),
    );
  }
}
