import 'package:flutter/material.dart';

import '../design/components/button.dart';
import '../design/components/sheet.dart';
import '../design/tokens.dart';

/// 알림 권한이 거부된 상태에서 "켜기"를 눌렀을 때 — 시스템은 다이얼로그를 다시 띄우지 않으므로
/// 설정 앱 경로를 안내한다. 내정보 탭 알림 행·라이브 뷰 재동의 배너 공용
Future<void> showPushSettingsSheet(BuildContext context) {
  return showAppSheet<void>(
    context: context,
    header: '알림이 꺼져 있어요',
    builder: (sheetContext) => Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.xl,
        0,
        AppSpace.xl,
        AppSpace.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '설정 앱 > 놓치지마 > 알림에서 켜주시면\n출발 타이밍 알림을 받을 수 있어요',
            style: AppTypo.bodySm.copyWith(color: sheetContext.colors.inkMuted),
          ),
          const SizedBox(height: AppSpace.md),
          AppButton(
            label: '확인',
            variant: AppButtonVariant.tonal,
            medium: true,
            block: true,
            onPressed: () => Navigator.of(sheetContext).pop(),
          ),
        ],
      ),
    ),
  );
}
