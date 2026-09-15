import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'design/components/glass_nav_bar.dart';
import 'design/tokens.dart';
import 'home_page.dart';
import 'journey_page.dart';
import 'main_page.dart';
import 'my_info_page.dart';

/// 루트 셸 — 메인·놓치지마·하차 알림·내정보 4개 탭을 바텀 네비게이션으로 묶는다.
/// 메인은 각 섹션의 요약(대시보드), 놓치지마가 라이브 뷰 본편(HomePage),
/// 하차 알림은 여정 추적(명세서 §3.7)이다.
/// IndexedStack으로 탭 전환 시에도 라이브 뷰의 폴링·선택 경로 상태를 유지한다.
/// 아이콘은 우선 Flutter 기본(Material) 아이콘 — 브랜드 아이콘이 나오면 교체한다.
class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _index = 0;

  void _select(int index) {
    if (index == _index) {
      return;
    }
    HapticFeedback.selectionClick();
    setState(() => _index = index);
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      MainPage(active: _index == 0, onOpenCatch: () => _select(1)),
      const HomePage(),
      JourneyPage(active: _index == 2),
      MyInfoPage(active: _index == 3),
    ];
    return Scaffold(
      backgroundColor: context.colors.background,
      // 콘텐츠가 글라스 네비 아래로 흐르게 — 각 탭은 SafeArea(bottom: false) +
      // 스크롤 하단 패딩(MediaQuery.padding.bottom)으로 마지막 항목을 피한다
      extendBody: true,
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: GlassNavBar(
        selectedIndex: _index,
        onSelect: _select,
        items: const [
          GlassNavItem(
            icon: Icons.home_outlined,
            selectedIcon: Icons.home,
            label: '메인',
          ),
          GlassNavItem(
            icon: Icons.directions_bus_outlined,
            selectedIcon: Icons.directions_bus,
            label: '놓치지마',
          ),
          GlassNavItem(
            icon: Icons.subway_outlined,
            selectedIcon: Icons.subway,
            label: '하차 알림',
          ),
          GlassNavItem(
            icon: Icons.person_outlined,
            selectedIcon: Icons.person,
            label: '내정보',
          ),
        ],
      ),
    );
  }
}
