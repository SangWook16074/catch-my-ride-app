import 'package:flutter/material.dart';

import '../tokens.dart';

/// 라운드 필 형태의 선택 칩 — 선택되면 세이지 소프트 배경 + 진한 그린 글자
class AppChip extends StatelessWidget {
  const AppChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? context.colors.primarySoft : context.colors.fill,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(
              color: selected ? context.colors.primary : Colors.transparent,
            ),
          ),
          child: Text(
            label,
            style: AppTypo.bodySm.copyWith(
              color: selected ? context.colors.primaryStrong : context.colors.inkMuted,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}
