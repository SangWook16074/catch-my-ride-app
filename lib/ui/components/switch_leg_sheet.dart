/// 구간 바꾸기 시트 (API.md §9-3 v0.10, 오너 결정 2026-10-01) — 시작 구간 자동 판정이
/// 틀렸거나 좌표 없이 0번 구간에 묶였을 때의 출구. 구간이 2개 이상인 트립에서만 보조
/// 액션으로 노출되고, 현재 구간을 표시한 목록에서 고르면 호출부가 `switch-leg`를 부른다.
library;

import 'package:flutter/material.dart';

import '../../domain/journey.dart';
import '../design/components/list_row.dart';
import '../design/components/sheet.dart';
import '../design/tokens.dart';

/// 고른 구간 인덱스를 돌려준다 — 현재 구간을 다시 고르거나 시트를 닫으면 null
Future<int?> showSwitchLegSheet(
  BuildContext context, {
  required List<JourneyLeg> legs,
  required int currentLegIndex,
}) {
  return showAppSheet<int>(
    context: context,
    header: '구간 바꾸기',
    builder: (sheetContext) => Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < legs.length; i++)
            AppListRow(
              onPressed: i == currentLegIndex
                  ? null
                  : () => Navigator.of(sheetContext).pop(i),
              contents: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${legs[i].boardStop} → ${legs[i].alightStop}',
                    style: AppTypo.body.copyWith(
                      color: i == currentLegIndex
                          ? sheetContext.colors.inkFaint
                          : sheetContext.colors.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    legs[i].line,
                    style: AppTypo.caption.copyWith(
                      color: sheetContext.colors.inkSubtle,
                    ),
                  ),
                ],
              ),
              right: i == currentLegIndex
                  ? Text(
                      '추적 중',
                      style: AppTypo.caption.copyWith(
                        color: sheetContext.colors.primaryStrong,
                      ),
                    )
                  : null,
            ),
        ],
      ),
    ),
  );
}
