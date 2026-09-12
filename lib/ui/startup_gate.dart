import 'dart:async';

import 'package:flutter/material.dart';

import '../data/api.dart';
import '../domain/models.dart';
import 'design/tokens.dart';
import 'onboarding_page.dart';
import 'root_shell.dart';

/// 첫 실행 게이트 — 통근 경로가 하나도 없으면 루트 셸 대신 온보딩부터 시작한다.
/// 온보딩을 마치면(또는 뒤로 나오면) 루트 셸로 진입한다 — 다시 가두지 않는다:
/// 미설정 상태의 안내는 놓치지마 탭의 "설정 시작하기"가 이어받는다.
class StartupGate extends StatefulWidget {
  const StartupGate({super.key});

  @override
  State<StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<StartupGate> {
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    unawaited(_decide());
  }

  Future<void> _decide() async {
    var needsOnboarding = false;
    try {
      final routes = await api.listCommuteRoutes();
      needsOnboarding = routes.isEmpty;
    } on ApiException catch (error) {
      needsOnboarding = error.code == ApiException.settingNotFound;
    } catch (_) {
      // 네트워크 실패 — 설정 여부를 알 수 없다. 셸로 들어가 본편의 재시도 흐름을 따른다
    }
    if (!mounted) {
      return;
    }
    if (needsOnboarding) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const OnboardingPage()),
      );
      if (!mounted) {
        return;
      }
    }
    setState(() => _ready = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_ready) {
      return const RootShell();
    }
    return Scaffold(
      backgroundColor: context.colors.background,
      body: Center(
        child: Text(
          '설정을 확인하고 있어요…',
          style: AppTypo.bodySm.copyWith(color: context.colors.inkSubtle),
        ),
      ),
    );
  }
}
