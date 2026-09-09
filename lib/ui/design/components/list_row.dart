import 'package:flutter/material.dart';

import '../tokens.dart';

/// 좌측 contents + 우측 right 슬롯을 가진 리스트 행
class AppListRow extends StatelessWidget {
  const AppListRow({
    super.key,
    required this.contents,
    this.right,
    this.onPressed,
    this.horizontalPadding = AppSpace.xl,
  });

  final Widget contents;
  final Widget? right;
  final VoidCallback? onPressed;
  final double horizontalPadding;

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: EdgeInsets.symmetric(
        horizontal: horizontalPadding,
        vertical: 10,
      ),
      child: Row(
        children: [
          Expanded(child: contents),
          if (right != null) ...[const SizedBox(width: AppSpace.md), right!],
        ],
      ),
    );
    if (onPressed == null) {
      return row;
    }
    return InkWell(onTap: onPressed, child: row);
  }
}
