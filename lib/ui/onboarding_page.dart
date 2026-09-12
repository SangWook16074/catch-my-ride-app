import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/api.dart';
import '../data/push_registrar.dart';
import '../domain/models.dart';
import '../domain/onboarding.dart';
import 'design/components/button.dart';
import 'design/tokens.dart';
import 'onboarding_wizard.dart';

/// 온보딩/재설정 호스트 — 미니앱 pages/onboarding.tsx 이식.
///
/// routeId 없음(null) → 첫 경로 수정(없으면 최초 온보딩).
/// routeId='new' → 경로 추가 / routeId=실제 id → 해당 경로 수정.
///
/// 진입 시 경로 목록으로 생성/수정을 판별한다. 실패를 빈 위저드로 fallback하지 않는
/// 이유: 기존 설정을 좁은 값으로 덮어쓸 위험 (수정 모드가 생성 모드로 둔갑).
class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key, this.routeId});

  final String? routeId;

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

sealed class _SetupPhase {
  const _SetupPhase();
}

class _Loading extends _SetupPhase {
  const _Loading();
}

class _LoadFailed extends _SetupPhase {
  const _LoadFailed();
}

class _Ready extends _SetupPhase {
  const _Ready({required this.editing, required this.routes});

  /// null이면 생성 모드 — 저장 시 nextRouteLabel로 라벨을 정해 경로를 추가한다
  final CommuteRoute? editing;
  final List<CommuteRoute> routes;
}

class _OnboardingPageState extends State<OnboardingPage> {
  _SetupPhase _phase = const _Loading();

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() => _phase = const _Loading());
    try {
      final routes = await api.listCommuteRoutes();
      final requested = widget.routeId;
      final CommuteRoute? editing;
      if (requested == 'new') {
        editing = null;
      } else if (requested != null) {
        editing = routes.where((r) => r.id == requested).firstOrNull;
      } else {
        // 레거시 진입 — 첫 경로 수정, 없으면 최초 온보딩
        editing = routes.firstOrNull;
      }
      if (!mounted) {
        return;
      }
      setState(() => _phase = _Ready(editing: editing, routes: routes));
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(
        () => _phase = error.code == ApiException.settingNotFound
            ? const _Ready(editing: null, routes: [])
            : const _LoadFailed(),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _phase = const _LoadFailed());
    }
  }

  Future<void> _handleComplete(
    _Ready ready,
    CommuteSetting setting,
    String label,
  ) async {
    final editing = ready.editing;
    if (editing == null) {
      await api.createCommuteRoute(
        CommuteRouteRequest(label: label, enabled: true, setting: setting),
      );
    } else {
      await api.updateCommuteRoute(
        editing.id,
        CommuteRouteRequest(
          label: label,
          enabled: editing.enabled,
          setting: setting,
        ),
      );
    }
    // 햅틱: 경로 저장 확정 (CLAUDE.md 적응형 UI 규칙)
    unawaited(HapticFeedback.mediumImpact());
    // 알림을 받으려고 설정한 직후가 동의를 구할 가장 자연스러운 시점 (미니앱과 동일).
    // 이 화면의 다른 다이얼로그(위치 권한)는 1단계에서 끝났으므로 연속 노출이 아니다.
    // 이미 허용/거부된 상태면 시스템이 다이얼로그 없이 지나간다 — 저장마다 불러도 스팸 아님.
    // 거부·실패해도 앱 사용은 계속된다 (결과는 PushRegistrar가 로깅).
    await pushRegistrar.ensureRegistered();
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      body: SafeArea(child: _body()),
    );
  }

  Widget _body() {
    switch (_phase) {
      case _Loading():
        return Center(
          child: Text(
            '설정을 확인하고 있어요…',
            style: AppTypo.bodySm.copyWith(color: context.colors.inkSubtle),
          ),
        );
      case _LoadFailed():
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpace.xl),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  '설정을 불러오지 못했어요',
                  textAlign: TextAlign.center,
                  style: AppTypo.heading,
                ),
                const SizedBox(height: AppSpace.lg),
                Text(
                  '네트워크를 확인하고 다시 시도해주세요',
                  textAlign: TextAlign.center,
                  style: AppTypo.bodySm.copyWith(color: context.colors.inkMuted),
                ),
                const SizedBox(height: AppSpace.lg),
                AppButton(
                  label: '다시 시도',
                  onPressed: () => unawaited(_load()),
                ),
              ],
            ),
          ),
        );
      case final _Ready ready:
        final editing = ready.editing;
        final isReset = editing != null;
        return OnboardingWizard(
          initialDraft: editing == null
              ? OnboardingDraft.empty().copyWith(
                  label: nextRouteLabel(ready.routes),
                )
              : settingToDraft(editing.setting).copyWith(label: editing.label),
          completeLabel: isReset ? '변경 내용 저장' : '완료',
          onComplete: (setting, label) =>
              _handleComplete(ready, setting, label),
        );
    }
  }
}
