import 'package:flutter/material.dart';

import 'ui/design/theme.dart';
import 'ui/home_page.dart';

void main() {
  runApp(const CatchMyRideApp());
}

/// 놓치지마 스토어판 — 화면 플로우는 미니앱(catch_my_ride_appintoss)과 동일:
/// 메인(라이브 뷰) ↔ 온보딩 7단계 위저드.
class CatchMyRideApp extends StatelessWidget {
  const CatchMyRideApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '놓치지마',
      theme: buildAppTheme(Brightness.light),
      darkTheme: buildAppTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      home: const HomePage(),
    );
  }
}
