/// 리퀴드 글라스 근사 바텀 네비게이션 — 떠 있는 필(pill) 형태.
///
/// ADR-001 트레이드오프 준수: 인앱 글라스는 블러(BackdropFilter)+반투명(glass 토큰)
/// 근사치까지 — 진짜 리퀴드 글라스는 위젯/시스템 표면 담당.
/// 두 플랫폼 공통 형태를 쓴다(오너 결정 2026-09-15 리뉴얼): 떠 있는 필은 iOS 26
/// 글라스 내비의 인상을 주면서도, 아이콘+라벨 상시 노출·선택 필 하이라이트는
/// Material 3 관성 그대로라 안드로이드 유저에게도 낯설지 않다.
library;

import 'dart:ui';

import 'package:flutter/material.dart';

import '../tokens.dart';

class GlassNavItem {
  const GlassNavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

class GlassNavBar extends StatelessWidget {
  const GlassNavBar({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onSelect,
  });

  final List<GlassNavItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  /// 유리 뒤 콘텐츠가 뭉개질 만큼만 — 과하면 성능·가독성 둘 다 잃는다
  static const double _blurSigma = 20;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return Padding(
      // 떠 있는 필 — 좌우·아래 여백으로 화면에서 띄운다 (홈 인디케이터 위)
      padding: EdgeInsets.fromLTRB(
        AppSpace.lg,
        AppSpace.sm,
        AppSpace.lg,
        bottomInset > 0 ? bottomInset : AppSpace.lg,
      ),
      child: DecoratedBox(
        // 그림자는 클립 바깥에 — ClipRRect 안에서는 잘려 보이지 않는다
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          boxShadow: [
            BoxShadow(
              color: colors.ink.withValues(alpha: 0.10),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: _blurSigma, sigmaY: _blurSigma),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colors.glass,
                borderRadius: BorderRadius.circular(AppRadius.pill),
                border: Border.all(color: colors.glassStroke),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpace.sm,
                  vertical: AppSpace.sm,
                ),
                child: Row(
                  children: [
                    for (final (index, item) in items.indexed)
                      Expanded(
                        child: _GlassNavButton(
                          item: item,
                          selected: index == selectedIndex,
                          onTap: () => onSelect(index),
                        ),
                      ),
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

class _GlassNavButton extends StatelessWidget {
  const _GlassNavButton({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final GlassNavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final foreground = selected ? colors.primaryStrong : colors.inkMuted;
    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
          decoration: BoxDecoration(
            // 선택 필 — 유리 위에 브랜드 소프트 면이 떠오른다
            color: selected ? colors.primarySoft : null,
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                selected ? item.selectedIcon : item.icon,
                size: 24,
                color: foreground,
              ),
              const SizedBox(height: 2),
              Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypo.caption.copyWith(
                  color: foreground,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
