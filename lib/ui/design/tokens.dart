/// 놓치지마 디자인 시스템 — 토큰.
///
/// 방향(오너 결정 2026-09-09, 2차 개정): **딥그린 × 코랄** 듀오 — 그린이 주인공,
/// 코랄이 따뜻한 강조(서두름·포인트). 라이트/다크 팔레트를 나란히 정의하고
/// ThemeExtension으로 등록해 시스템 다크 모드를 자동으로 따른다.
///
/// 규칙: 화면·컴포넌트는 `context.colors.*` 토큰만 쓴다 — Color(0x...)/fontSize
/// 하드코딩 금지. 팔레트를 갈아입힐 때는 이 파일의 light/dark 두 인스턴스만 바꾼다.
library;

import 'package:flutter/material.dart';

/// 컬러 팔레트 — 라이트/다크 인스턴스를 [light]/[dark]로 정의한다.
/// 위젯에서는 `context.colors.primary`로 접근 (테마 전환 자동 반영).
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.primary,
    required this.primaryStrong,
    required this.primarySoft,
    required this.caution,
    required this.cautionStrong,
    required this.cautionSoft,
    required this.danger,
    required this.dangerStrong,
    required this.dangerSoft,
    required this.ink,
    required this.inkMuted,
    required this.inkSubtle,
    required this.inkFaint,
    required this.surface,
    required this.background,
    required this.fill,
    required this.fillStrong,
    required this.line,
  });

  // 브랜드 — 딥그린 (주인공)
  final Color primary;

  /// 누른 상태·작은 글자 강조 — primary보다 대비가 높다
  final Color primaryStrong;

  /// 선택 배경·연한 카드
  final Color primarySoft;

  // 강조 — 코랄 (서두름·포인트, 그린의 따뜻한 짝)
  /// 서두름·강조 면/큰 글자용
  final Color caution;

  /// 서두름 글자용 — 작은 텍스트 대비 확보
  final Color cautionStrong;
  final Color cautionSoft;

  /// 놓침·오류 — 코랄보다 깊은 레드로 구분
  final Color danger;

  /// 오류 글자용
  final Color dangerStrong;
  final Color dangerSoft;

  // 중성
  /// 기본 글자
  final Color ink;

  /// 보조 글자 (부제·본문 설명)
  final Color inkMuted;

  /// 힌트·자리표시자·헬퍼
  final Color inkSubtle;

  /// 비활성 — "시간 정보 없음"처럼 죽은 정보에만 쓴다
  final Color inkFaint;

  /// 카드·시트 면
  final Color surface;

  /// 화면 바탕
  final Color background;

  /// 입력 필드·연한 채움
  final Color fill;

  /// 진한 채움 (보조 버튼)
  final Color fillStrong;

  /// 카드 테두리·구분선
  final Color line;

  /// 라이트 — 흰 바탕 + 딥그린 + 코랄
  static const AppColors light = AppColors(
    primary: Color(0xFF0E8A45),
    primaryStrong: Color(0xFF066B33),
    primarySoft: Color(0xFFE1F3E8),
    caution: Color(0xFFF2655A),
    cautionStrong: Color(0xFFD14B41),
    cautionSoft: Color(0xFFFDEAE7),
    danger: Color(0xFFB3261E),
    dangerStrong: Color(0xFF8E1B15),
    dangerSoft: Color(0xFFF9E0DE),
    ink: Color(0xFF1A1F1B),
    inkMuted: Color(0xFF4C5650),
    inkSubtle: Color(0xFF707B74),
    inkFaint: Color(0xFFA4ADA7),
    surface: Color(0xFFFFFFFF),
    background: Color(0xFFF5F7F5),
    fill: Color(0xFFEDF1EE),
    fillStrong: Color(0xFFDFE5E1),
    line: Color(0xFFE2E7E3),
  );

  /// 다크 — 그린 기 도는 근검정 바탕 + 밝힌 그린/코랄 (strong = 다크에서 더 밝게)
  static const AppColors dark = AppColors(
    primary: Color(0xFF43C17C),
    primaryStrong: Color(0xFF6CD79B),
    primarySoft: Color(0xFF17301F),
    caution: Color(0xFFFF8177),
    cautionStrong: Color(0xFFFF9C93),
    cautionSoft: Color(0xFF3A211E),
    danger: Color(0xFFE0453C),
    dangerStrong: Color(0xFFEE6A62),
    dangerSoft: Color(0xFF371E1B),
    ink: Color(0xFFECF1ED),
    inkMuted: Color(0xFFB6C0B9),
    inkSubtle: Color(0xFF8B958E),
    inkFaint: Color(0xFF5C665F),
    surface: Color(0xFF1B201D),
    background: Color(0xFF131714),
    fill: Color(0xFF222824),
    fillStrong: Color(0xFF2C332E),
    line: Color(0xFF262D28),
  );

  @override
  AppColors copyWith({
    Color? primary,
    Color? primaryStrong,
    Color? primarySoft,
    Color? caution,
    Color? cautionStrong,
    Color? cautionSoft,
    Color? danger,
    Color? dangerStrong,
    Color? dangerSoft,
    Color? ink,
    Color? inkMuted,
    Color? inkSubtle,
    Color? inkFaint,
    Color? surface,
    Color? background,
    Color? fill,
    Color? fillStrong,
    Color? line,
  }) =>
      AppColors(
        primary: primary ?? this.primary,
        primaryStrong: primaryStrong ?? this.primaryStrong,
        primarySoft: primarySoft ?? this.primarySoft,
        caution: caution ?? this.caution,
        cautionStrong: cautionStrong ?? this.cautionStrong,
        cautionSoft: cautionSoft ?? this.cautionSoft,
        danger: danger ?? this.danger,
        dangerStrong: dangerStrong ?? this.dangerStrong,
        dangerSoft: dangerSoft ?? this.dangerSoft,
        ink: ink ?? this.ink,
        inkMuted: inkMuted ?? this.inkMuted,
        inkSubtle: inkSubtle ?? this.inkSubtle,
        inkFaint: inkFaint ?? this.inkFaint,
        surface: surface ?? this.surface,
        background: background ?? this.background,
        fill: fill ?? this.fill,
        fillStrong: fillStrong ?? this.fillStrong,
        line: line ?? this.line,
      );

  @override
  AppColors lerp(AppColors? other, double t) {
    if (other == null) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppColors(
      primary: mix(primary, other.primary),
      primaryStrong: mix(primaryStrong, other.primaryStrong),
      primarySoft: mix(primarySoft, other.primarySoft),
      caution: mix(caution, other.caution),
      cautionStrong: mix(cautionStrong, other.cautionStrong),
      cautionSoft: mix(cautionSoft, other.cautionSoft),
      danger: mix(danger, other.danger),
      dangerStrong: mix(dangerStrong, other.dangerStrong),
      dangerSoft: mix(dangerSoft, other.dangerSoft),
      ink: mix(ink, other.ink),
      inkMuted: mix(inkMuted, other.inkMuted),
      inkSubtle: mix(inkSubtle, other.inkSubtle),
      inkFaint: mix(inkFaint, other.inkFaint),
      surface: mix(surface, other.surface),
      background: mix(background, other.background),
      fill: mix(fill, other.fill),
      fillStrong: mix(fillStrong, other.fillStrong),
      line: mix(line, other.line),
    );
  }
}

/// 위젯에서 팔레트 접근: `context.colors.primary`
extension AppColorsX on BuildContext {
  AppColors get colors => Theme.of(this).extension<AppColors>()!;
}

/// 타이포 스케일 — 역할 기반 이름 (TDS t3/t5 같은 번호 체계를 쓰지 않는다).
/// 색은 넣지 않는다 — DefaultTextStyle(테마의 ink)을 상속하고, 다른 색은 copyWith로 입힌다.
abstract final class AppTypo {
  /// 화면 제목 (라이브 뷰 헤드라인, 위저드 단계 제목)
  static const TextStyle title = TextStyle(
    fontSize: 22,
    height: 1.35,
    fontWeight: FontWeight.w700,
  );

  /// 강조 본문 (카드 제목, 리스트 주 텍스트 강조)
  static const TextStyle heading = TextStyle(
    fontSize: 17,
    height: 1.4,
    fontWeight: FontWeight.w600,
  );

  /// 본문 (리스트 주 텍스트, 입력값)
  static const TextStyle body = TextStyle(
    fontSize: 17,
    height: 1.4,
  );

  /// 작은 본문 (부제·안내 문구)
  static const TextStyle bodySm = TextStyle(
    fontSize: 15,
    height: 1.45,
  );

  /// 캡션 (헬퍼·보조 정보·푸터)
  static const TextStyle caption = TextStyle(
    fontSize: 13,
    height: 1.4,
  );
}

/// 간격 스케일 — 화면 여백은 xl(24), 요소 사이는 sm~lg
abstract final class AppSpace {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
}

/// 모서리 스케일 — 부드러운 인상을 위해 카드·시트는 lg 이상
abstract final class AppRadius {
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double pill = 999;
}
