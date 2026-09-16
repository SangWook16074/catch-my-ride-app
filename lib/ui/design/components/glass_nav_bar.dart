/// 리퀴드 글라스 근사 바텀 네비게이션 — 떠 있는 필(pill) 형태.
///
/// ADR-001 트레이드오프 준수: 인앱 글라스는 블러(BackdropFilter)+반투명(glass 토큰)
/// 근사치까지 — 진짜 리퀴드 글라스는 위젯/시스템 표면 담당.
/// 두 플랫폼 공통 형태를 쓴다(오너 결정 2026-09-15 리뉴얼): 떠 있는 필은 iOS 26
/// 글라스 내비의 인상을 주면서도, 아이콘+라벨 상시 노출·선택 필 하이라이트는
/// Material 3 관성 그대로라 안드로이드 유저에게도 낯설지 않다.
///
/// 상호작용: 탭 = 즉시 선택, 가로 스와이프 = 선택 필이 손가락을 따라오고 놓으면
/// 가까운 탭에 스냅 (오너 요구 2026-09-15). 경계를 넘을 때 selection 햅틱.
/// 손가락이 닿아 있는 동안 바 전체가 아주 살짝 확대된다 — 유리가 손끝에 반응하는
/// 인상 (오너 요구 2026-09-16).
library;

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

class GlassNavBar extends StatefulWidget {
  const GlassNavBar({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onSelect,
  });

  final List<GlassNavItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  @override
  State<GlassNavBar> createState() => _GlassNavBarState();
}

class _GlassNavBarState extends State<GlassNavBar> {
  /// 유리 뒤 콘텐츠가 뭉개질 만큼만 — 과하면 성능·가독성 둘 다 잃는다
  static const double _blurSigma = 20;

  /// 눌림 확대 배율 — "아주 살짝"이 요점: 이보다 크면 장난감 같아진다
  static const double _pressedScale = 1.03;

  /// 드래그 중 선택 필의 연속 위치(칸 단위) — null이면 selectedIndex에 정착 상태
  double? _dragPosition;

  /// 손가락이 바에 닿아 있는 동안 true — 바 전체 확대의 근거
  bool _pressed = false;

  int get _activeIndex => _dragPosition?.round() ?? widget.selectedIndex;

  void _dragTo(double localX, double slotWidth) {
    final next = (localX / slotWidth - 0.5).clamp(
      0.0,
      (widget.items.length - 1).toDouble(),
    );
    final crossed =
        _dragPosition != null && _dragPosition!.round() != next.round();
    setState(() => _dragPosition = next);
    if (crossed) {
      HapticFeedback.selectionClick(); // 경계 통과 — 칸이 넘어갔음을 손끝으로
    }
  }

  void _endDrag() {
    final position = _dragPosition;
    if (position == null) {
      return;
    }
    final snapped = position.round();
    setState(() => _dragPosition = null);
    if (snapped != widget.selectedIndex) {
      widget.onSelect(snapped);
    }
  }

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
      // Listener: 탭·스와이프 제스처와 경합하지 않고 "닿음" 자체만 감지한다
      child: Listener(
        onPointerDown: (_) => setState(() => _pressed = true),
        onPointerUp: (_) => setState(() => _pressed = false),
        onPointerCancel: (_) => setState(() => _pressed = false),
        child: AnimatedScale(
          scale: _pressed ? _pressedScale : 1.0,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
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
                filter: ImageFilter.blur(
                  sigmaX: _blurSigma,
                  sigmaY: _blurSigma,
                ),
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
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final slotWidth =
                            constraints.maxWidth / widget.items.length;
                        final position =
                            _dragPosition ?? widget.selectedIndex.toDouble();
                        final dragging = _dragPosition != null;
                        return GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onHorizontalDragStart: (details) =>
                              _dragTo(details.localPosition.dx, slotWidth),
                          onHorizontalDragUpdate: (details) =>
                              _dragTo(details.localPosition.dx, slotWidth),
                          onHorizontalDragEnd: (_) => _endDrag(),
                          onHorizontalDragCancel: _endDrag,
                          child: Stack(
                            children: [
                              // 선택 필 — 드래그 중엔 손가락을 따라오고, 놓으면 스냅 애니메이션
                              AnimatedPositioned(
                                duration: dragging
                                    ? Duration.zero
                                    : const Duration(milliseconds: 250),
                                curve: Curves.easeOutCubic,
                                left: position * slotWidth,
                                top: 0,
                                bottom: 0,
                                width: slotWidth,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: colors.primarySoft,
                                    borderRadius: BorderRadius.circular(
                                      AppRadius.pill,
                                    ),
                                  ),
                                ),
                              ),
                              Row(
                                children: [
                                  for (final (index, item)
                                      in widget.items.indexed)
                                    Expanded(
                                      child: _GlassNavButton(
                                        item: item,
                                        selected: index == _activeIndex,
                                        onTap: () => widget.onSelect(index),
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
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
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
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
