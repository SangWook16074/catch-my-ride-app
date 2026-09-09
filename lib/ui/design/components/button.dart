import 'package:flutter/material.dart';

import '../tokens.dart';

/// 디자인 시스템 버튼.
/// primary(세이지) / neutral(연한 채움) / tonal(진한 채움) / danger(뮤트 로즈)
enum AppButtonVariant { primary, neutral, tonal, danger }

class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = AppButtonVariant.primary,
    this.loading = false,
    this.block = false,
    this.medium = false,
  });

  final String label;

  /// null이면 비활성화
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final bool loading;

  /// 가로 꽉 채움
  final bool block;

  /// 카드 안 버튼용 축소 사이즈
  final bool medium;

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = switch (variant) {
      AppButtonVariant.primary => (
        context.colors.primary,
        context.colors.onPrimary,
      ),
      AppButtonVariant.neutral => (context.colors.fill, context.colors.ink),
      AppButtonVariant.tonal => (context.colors.fillStrong, context.colors.ink),
      AppButtonVariant.danger => (
        context.colors.danger,
        context.colors.onDanger,
      ),
    };
    final enabled = onPressed != null && !loading;

    final child = loading
        ? SizedBox(
            width: 18,
            height: 18,
            // 적응형 UI 규칙: 로딩은 .adaptive 우선
            child: CircularProgressIndicator.adaptive(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(foreground),
            ),
          )
        : Text(
            label,
            style: (medium ? AppTypo.bodySm : AppTypo.body).copyWith(
              color: foreground,
              fontWeight: FontWeight.w600,
            ),
          );

    final button = FilledButton(
      onPressed: enabled ? onPressed : null,
      style: FilledButton.styleFrom(
        backgroundColor: background,
        disabledBackgroundColor: background.withValues(alpha: 0.45),
        foregroundColor: foreground,
        padding: EdgeInsets.symmetric(
          horizontal: medium ? AppSpace.lg : 20,
          vertical: medium ? AppSpace.md : 15,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        elevation: 0,
      ),
      child: child,
    );

    return block ? SizedBox(width: double.infinity, child: button) : button;
  }
}
