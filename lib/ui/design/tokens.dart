/// 놓치지마 디자인 시스템 — 토큰.
///
/// 방향(오너 결정 2026-09-09 개정): **선명한 딥그린** — 그린 아이덴티티는 유지하되
/// 채도·대비를 올려 또렷하게. 초기 세이지 파스텔안은 "전체적으로 뿌옇다"는 오너 피드백으로
/// 폐기. TDS(토스)와는 별개의 시스템이다.
///
/// 규칙: 화면·컴포넌트는 여기 토큰만 쓴다 — Color(0x...)/fontSize 하드코딩 금지.
/// 컬러를 갈아입힐 때는 이 파일만 바꾼다.
library;

import 'package:flutter/material.dart';

abstract final class AppColors {
  // 브랜드 — 선명한 딥그린 (신선하고 또렷한 교통앱)
  static const Color primary = Color(0xFF0E8A45);

  /// 누른 상태·작은 글자 강조 — primary보다 대비가 높다
  static const Color primaryStrong = Color(0xFF066B33);

  /// 선택 배경·연한 카드 — 연하지만 채도는 살아 있게
  static const Color primarySoft = Color(0xFFE3F4EA);

  // 상태 — 경고·위험도 또렷하게 (뮤트 금지)
  /// 서두름 (또렷한 주황) — 면·큰 글자용
  static const Color caution = Color(0xFFE8730C);

  /// 서두름 글자용 — 작은 텍스트 대비 확보
  static const Color cautionStrong = Color(0xFFC25F06);
  static const Color cautionSoft = Color(0xFFFDEEDD);

  /// 놓침·오류 (선명한 레드) — 면·버튼용
  static const Color danger = Color(0xFFDC3B30);

  /// 오류 글자용
  static const Color dangerStrong = Color(0xFFB72A21);
  static const Color dangerSoft = Color(0xFFFCE8E6);

  // 중성 — 거의 검정 잉크 + 깨끗한 회백. 그린 기는 아주 옅게만
  /// 기본 글자
  static const Color ink = Color(0xFF191F1B);

  /// 보조 글자 (부제·본문 설명)
  static const Color inkMuted = Color(0xFF4A544E);

  /// 힌트·자리표시자·헬퍼
  static const Color inkSubtle = Color(0xFF6E7972);

  /// 비활성 — "시간 정보 없음"처럼 죽은 정보에만 쓴다
  static const Color inkFaint = Color(0xFFA3ACA6);

  /// 카드·시트 면
  static const Color surface = Color(0xFFFFFFFF);

  /// 화면 바탕 — 깨끗한 회백 (오프화이트보다 중립적으로)
  static const Color background = Color(0xFFF4F6F4);

  /// 입력 필드·연한 채움
  static const Color fill = Color(0xFFEEF1EF);

  /// 진한 채움 (보조 버튼)
  static const Color fillStrong = Color(0xFFE0E5E1);

  /// 카드 테두리·구분선
  static const Color line = Color(0xFFE2E6E3);
}

/// 타이포 스케일 — 역할 기반 이름 (TDS t3/t5 같은 번호 체계를 쓰지 않는다)
abstract final class AppTypo {
  /// 화면 제목 (라이브 뷰 헤드라인, 위저드 단계 제목)
  static const TextStyle title = TextStyle(
    fontSize: 22,
    height: 1.35,
    fontWeight: FontWeight.w700,
    color: AppColors.ink,
  );

  /// 강조 본문 (카드 제목, 리스트 주 텍스트 강조)
  static const TextStyle heading = TextStyle(
    fontSize: 17,
    height: 1.4,
    fontWeight: FontWeight.w600,
    color: AppColors.ink,
  );

  /// 본문 (리스트 주 텍스트, 입력값)
  static const TextStyle body = TextStyle(
    fontSize: 17,
    height: 1.4,
    color: AppColors.ink,
  );

  /// 작은 본문 (부제·안내 문구)
  static const TextStyle bodySm = TextStyle(
    fontSize: 15,
    height: 1.45,
    color: AppColors.ink,
  );

  /// 캡션 (헬퍼·보조 정보·푸터)
  static const TextStyle caption = TextStyle(
    fontSize: 13,
    height: 1.4,
    color: AppColors.ink,
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
