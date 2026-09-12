import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'design/tokens.dart';
import 'home_page.dart';

/// 루트 셸 — 메인·놓치지마·새로운 기능·내정보 4개 탭을 바텀 네비게이션으로 묶는다.
/// IndexedStack으로 탭 전환 시에도 메인(라이브 뷰)의 폴링·선택 경로 상태를 유지한다.
/// 아이콘은 우선 Flutter 기본(Material) 아이콘 — 브랜드 아이콘이 나오면 교체한다.
class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _index = 0;

  static const List<Widget> _pages = [
    HomePage(),
    _PlaceholderPage(
      icon: Icons.directions_bus_outlined,
      title: '놓치지마',
      subtitle: '놓치지마 화면을 준비하고 있어요',
    ),
    _PlaceholderPage(
      icon: Icons.auto_awesome_outlined,
      title: '새로운 기능',
      subtitle: '새로운 기능이 들어올 자리예요',
    ),
    _PlaceholderPage(
      icon: Icons.person_outlined,
      title: '내정보',
      subtitle: '내 정보 화면을 준비하고 있어요',
    ),
  ];

  void _select(int index) {
    if (index == _index) {
      return;
    }
    HapticFeedback.selectionClick();
    setState(() => _index = index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: context.colors.line)),
        ),
        child: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: _select,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: '메인',
            ),
            NavigationDestination(
              icon: Icon(Icons.directions_bus_outlined),
              selectedIcon: Icon(Icons.directions_bus),
              label: '놓치지마',
            ),
            NavigationDestination(
              icon: Icon(Icons.auto_awesome_outlined),
              selectedIcon: Icon(Icons.auto_awesome),
              label: '새로운 기능',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outlined),
              selectedIcon: Icon(Icons.person),
              label: '내정보',
            ),
          ],
        ),
      ),
    );
  }
}

/// 아직 내용이 없는 탭의 자리 화면 — 실제 화면이 생기면 _pages에서 교체한다
class _PlaceholderPage extends StatelessWidget {
  const _PlaceholderPage({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 48, color: context.colors.inkFaint),
            const SizedBox(height: AppSpace.lg),
            Text(title, style: AppTypo.heading),
            const SizedBox(height: AppSpace.sm),
            Text(
              subtitle,
              style: AppTypo.bodySm.copyWith(color: context.colors.inkMuted),
            ),
          ],
        ),
      ),
    );
  }
}
