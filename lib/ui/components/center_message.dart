/// 화면 한가운데 안내 — 타이틀·서브타이틀·버튼 (놓치지마 탭 초기 화면에서 시작한
/// 패턴을 탭 공통으로 통일, 오너 결정 2026-09-16). 빈 상태·오류 안내 공용.
library;

import 'package:flutter/material.dart';

import '../design/components/button.dart';
import '../design/tokens.dart';

class CenterMessage extends StatelessWidget {
  const CenterMessage({
    super.key,
    required this.title,
    required this.subtitle,
    required this.buttonLabel,
    required this.onPressed,
    this.titleLarge = false,
  });

  final String title;
  final String subtitle;
  final String buttonLabel;
  final VoidCallback onPressed;

  /// 온보딩류 초대 문구는 크게(AppTypo.title), 오류 안내는 기본(heading)
  final bool titleLarge;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        // 하단은 배너·글라스 네비가 덮는다(루트 셸 extendBody → padding.bottom에 포함) —
        // 그만큼 밀어 올려 "보이는 영역" 기준 정중앙에 놓는다
        padding: EdgeInsets.fromLTRB(
          AppSpace.xl,
          AppSpace.xl,
          AppSpace.xl,
          AppSpace.xl + MediaQuery.paddingOf(context).bottom,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: titleLarge ? AppTypo.title : AppTypo.heading,
            ),
            const SizedBox(height: AppSpace.lg),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: AppTypo.bodySm.copyWith(color: context.colors.inkMuted),
            ),
            const SizedBox(height: AppSpace.lg),
            AppButton(label: buttonLabel, onPressed: onPressed),
          ],
        ),
      ),
    );
  }
}
