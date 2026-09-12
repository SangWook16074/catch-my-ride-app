import 'package:flutter/material.dart';

import '../tokens.dart';

/// 헤더 + 본문을 가진 바텀시트.
/// 시트 내부 상태(저장 중·실패 문구)는 builder 쪽에서 StatefulWidget으로 관리한다.
Future<T?> showAppSheet<T>({
  required BuildContext context,
  required String header,
  required WidgetBuilder builder,
  bool isDismissible = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: context.colors.surface,
    isScrollControlled: true,
    isDismissible: isDismissible,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
    ),
    builder: (context) => Padding(
      // 키보드가 올라오면 시트도 따라 올라간다 (이름 수정 시트)
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.xl,
                AppSpace.xl,
                AppSpace.xl,
                AppSpace.sm,
              ),
              child: Text(header, style: AppTypo.heading),
            ),
            Flexible(child: SingleChildScrollView(child: builder(context))),
          ],
        ),
      ),
    ),
  );
}
