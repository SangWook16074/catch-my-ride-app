import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/api.dart';
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
    // 스토어판 푸시 수신 동의(FCM/APNs 권한)는 알림 인프라와 함께 이 시점에 붙인다.
    // ⚠️ 설계 규칙 (TODO 2026-09-09, 미니앱 실측 사고 — 연속 동의 요청을 네이티브가 삼켜
    // 리마인드 전량 미전달, 발송은 SUCCESS로 위장):
    //   1) 권한·동의 다이얼로그를 연속으로 띄우지 않는다 — 사이 간격 + 실패 시 1회 재시도
    //   2) 동의/권한 상태를 단계별로 확인하고 결과를 로깅해 조용한 실패를 남기지 않는다
    //   3) "성공 응답 ≠ 실제 전달"을 전제로 전달 실패를 관측 가능하게 만든다
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
