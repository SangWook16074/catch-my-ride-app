/// 앱 전역 ThemeData — 디자인 토큰(tokens.dart)을 Flutter 테마로 연결한다.
/// 라이트/다크는 팔레트 인스턴스만 다르고 구조는 동일 — MaterialApp(theme/darkTheme)에
/// 둘 다 등록하면 시스템 다크 모드를 자동으로 따른다.
library;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'tokens.dart';

ThemeData buildAppTheme(Brightness brightness) {
  final palette =
      brightness == Brightness.dark ? AppColors.dark : AppColors.light;
  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: ColorScheme.fromSeed(
      brightness: brightness,
      seedColor: palette.primary,
      primary: palette.primary,
      surface: palette.surface,
      error: palette.danger,
    ),
    scaffoldBackgroundColor: palette.background,
  );
  return base.copyWith(
    extensions: [palette],
    // 적응형 UI 규칙(CLAUDE.md): iOS 스와이프 백 유지 — 플랫폼별 페이지 전환 빌더
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
      },
    ),
    cupertinoOverrideTheme: CupertinoThemeData(
      brightness: brightness,
      primaryColor: palette.primary,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: palette.background,
      foregroundColor: palette.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: palette.primary,
    ),
    // 바텀 네비게이션(루트 셸) — 면은 surface, 선택 표시는 브랜드 soft/strong
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: palette.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: palette.primarySoft,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? palette.primaryStrong
              : palette.inkSubtle,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? AppTypo.caption.copyWith(
                color: palette.ink,
                fontWeight: FontWeight.w600,
              )
            : AppTypo.caption.copyWith(color: palette.inkSubtle),
      ),
    ),
    // AppTypo는 색을 갖지 않는다 — 기본 글자색은 여기(DefaultTextStyle)서 팔레트 ink로
    textTheme: base.textTheme.apply(
      bodyColor: palette.ink,
      displayColor: palette.ink,
    ),
  );
}
