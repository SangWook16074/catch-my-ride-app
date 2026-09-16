/// 탭 공통 글라스 헤더 — 바텀 글라스 네비와 같은 표현(블러+반투명, ADR-001 근사치
/// 한도)의 고정 상단 바 (오너 요구 2026-09-16: 헤더도 글라스로, 콘텐츠가 뒤로
/// 지나갈 때 글라스 이펙트가 보이게).
///
/// 사용법: 각 탭을 `Scaffold(extendBodyBehindAppBar: true, appBar: TabHeader(...))`
/// 로 감싸고, 스크롤 상단 패딩을 상태바 인셋 + [TabHeader.contentHeight]만큼 준다 —
/// 콘텐츠가 바 뒤로 흐르며 비쳐야 유리가 산다. 제목은 탭 이름(AppTypo.title),
/// 오른쪽 텍스트 액션([trailing])까지만 — 부제 등 확장은 탭 간 이질감의 원인이라
/// 두지 않는다 (오너 피드백 2026-09-16).
library;

import 'dart:ui';

import 'package:flutter/material.dart';

import '../design/tokens.dart';

class TabHeader extends StatelessWidget implements PreferredSizeWidget {
  const TabHeader({super.key, required this.title, this.trailing});

  /// 상태바 아래 헤더 본체 높이 — 스크롤 상단 패딩 계산에 같이 쓴다
  static const double contentHeight = 56;

  /// 글라스 네비와 같은 감각 — 유리 뒤 콘텐츠가 뭉개질 만큼만
  static const double _blurSigma = 20;

  final String title;

  /// 오른쪽 끝 액션(삭제·재설정 등 [TabHeaderAction]) — 없으면 생략
  final Widget? trailing;

  @override
  Size get preferredSize => const Size.fromHeight(contentHeight);

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ClipRect(
      // 블러가 바 영역 밖(콘텐츠)까지 번지지 않게 잘라낸다
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: _blurSigma, sigmaY: _blurSigma),
        child: Container(
          decoration: BoxDecoration(
            color: colors.glass,
            border: Border(bottom: BorderSide(color: colors.glassStroke)),
          ),
          child: SafeArea(
            bottom: false,
            child: SizedBox(
              height: contentHeight,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.xl),
                child: Row(
                  children: [
                    Expanded(child: Text(title, style: AppTypo.title)),
                    ?trailing,
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 헤더 오른쪽 텍스트 액션 (라이브 뷰 헤더의 삭제·재설정에서 승격)
class TabHeaderAction extends StatelessWidget {
  const TabHeaderAction({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.xs),
          child: Text(
            label,
            style: AppTypo.bodySm.copyWith(color: context.colors.inkMuted),
          ),
        ),
      ),
    );
  }
}
