import 'package:flutter/material.dart';

import '../tokens.dart';

/// 카드 톤 — 화면 바탕(오프화이트) 위에 얹는 면
enum AppCardTone {
  /// 흰 면 + 테두리 (기본 정보 카드)
  neutral,

  /// 세이지 소프트 (긍정 제안·확인)
  brand,

  /// 뮤트 암버 소프트 (주의 안내)
  caution,
}

class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.tone = AppCardTone.neutral,
    this.margin = const EdgeInsets.only(
      left: AppSpace.xl,
      right: AppSpace.xl,
      bottom: AppSpace.lg,
    ),
  });

  final Widget child;
  final AppCardTone tone;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    final (background, border) = switch (tone) {
      AppCardTone.neutral => (context.colors.surface, context.colors.line),
      AppCardTone.brand => (context.colors.primarySoft, Colors.transparent),
      AppCardTone.caution => (context.colors.cautionSoft, Colors.transparent),
    };
    return Container(
      margin: margin,
      padding: const EdgeInsets.all(AppSpace.lg),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: border),
      ),
      child: child,
    );
  }
}
