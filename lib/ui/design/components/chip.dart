import 'package:flutter/material.dart';

import '../tokens.dart';

/// 라운드 필 형태의 선택 칩 — 선택되면 소프트 그린 배경 + 진한 그린 글자.
/// Material 위에 InkWell을 두어 하이라이트(잉크)가 칩 면과 정확히 일치한다 —
/// 불투명 Container 아래 잉크가 깔리거나 모서리 밖으로 새지 않게.
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
    final shape = StadiumBorder(
      side: BorderSide(
        color: selected ? context.colors.primary : Colors.transparent,
      ),
    );
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? context.colors.primarySoft : context.colors.fill,
        shape: shape,
        child: InkWell(
          onTap: onPressed,
          customBorder: shape,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Text(
              label,
              style: AppTypo.bodySm.copyWith(
                color: selected
                    ? context.colors.primaryStrong
                    : context.colors.inkMuted,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
