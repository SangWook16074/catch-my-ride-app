import 'dart:async';

import 'package:flutter/material.dart';

import '../data/api.dart';
import '../data/push_registrar.dart';
import '../domain/models.dart';
import '../domain/time_format.dart';
import '../platform/app_info.dart';
import '../platform/push.dart';
import 'design/components/button.dart';
import 'design/components/card.dart';
import 'design/components/list_row.dart';
import 'design/components/sheet.dart';
import 'design/tokens.dart';
import 'onboarding_page.dart';

/// 내정보 탭 — 계정이 없는 앱(익명 키)이라 "내 것"의 관리가 곧 내정보다:
/// 통근 경로 관리 · 푸시 알림 상태 · 앱 정보.
class MyInfoPage extends StatefulWidget {
  const MyInfoPage({super.key, required this.active});

  /// 이 탭이 현재 보이는지 — 보이게 되는 순간 목록·권한 상태를 새로 불러온다
  final bool active;

  @override
  State<MyInfoPage> createState() => _MyInfoPageState();
}

class _MyInfoPageState extends State<MyInfoPage> {
  final PushBridge _push = PushBridge();
  final AppInfo _appInfo = AppInfo();

  List<CommuteRoute>? _routes;
  bool _loadFailed = false;
  bool _pushAuthorized = false;
  String? _version;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    unawaited(_loadVersion());
  }

  @override
  void didUpdateWidget(MyInfoPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 다른 탭·온보딩에서 바뀐 경로와 시스템 설정에서 바뀐 권한을 따라잡는다
    if (widget.active && !oldWidget.active) {
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    List<CommuteRoute>? routes;
    var failed = false;
    try {
      routes = await api.listCommuteRoutes();
    } on ApiException catch (error) {
      if (error.code == ApiException.settingNotFound) {
        routes = const [];
      } else {
        failed = true;
      }
    } catch (_) {
      failed = true;
    }
    final authorized = await _push.isAuthorized();
    if (!mounted) {
      return;
    }
    setState(() {
      if (routes != null) {
        _routes = routes;
      }
      _loadFailed = failed;
      _pushAuthorized = authorized;
    });
  }

  Future<void> _loadVersion() async {
    final version = await _appInfo.version();
    if (!mounted) {
      return;
    }
    setState(() => _version = version);
  }

  Future<void> _openOnboarding(String? routeId) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => OnboardingPage(routeId: routeId),
      ),
    );
    unawaited(_load());
  }

  /// 권한 다이얼로그는 이 탭에서 유저가 직접 눌렀을 때만 — 연속 요청 금지 규칙과 무관한
  /// 단독 노출이다. 허용되면 토큰 등록까지, 거부 상태면 시스템 설정 안내를 띄운다
  Future<void> _handlePushRow() async {
    await pushRegistrar.ensureRegistered();
    final authorized = await _push.isAuthorized();
    if (!mounted) {
      return;
    }
    setState(() => _pushAuthorized = authorized);
    if (!authorized) {
      unawaited(
        showAppSheet<void>(
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
                  style: AppTypo.bodySm.copyWith(
                    color: sheetContext.colors.inkMuted,
                  ),
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
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false, // 콘텐츠가 글라스 네비 밑으로 흐른다 — 하단 여백은 ListView padding이 담당
      child: RefreshIndicator.adaptive(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.only(
            top: AppSpace.md,
            bottom: MediaQuery.paddingOf(context).bottom + AppSpace.lg,
          ),
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(
                AppSpace.xl,
                AppSpace.lg,
                AppSpace.xl,
                AppSpace.lg,
              ),
              child: Text('내정보', style: AppTypo.title),
            ),
            _sectionHeader(context, '통근 경로'),
            AppCard(child: _routesSection()),
            _sectionHeader(context, '알림'),
            AppCard(
              child: AppListRow(
                horizontalPadding: 0,
                contents: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('푸시 알림', style: AppTypo.body),
                    Text(
                      '권장 출발 타이밍을 알려드려요',
                      style: AppTypo.caption.copyWith(
                        color: context.colors.inkSubtle,
                      ),
                    ),
                  ],
                ),
                right: Text(
                  _pushAuthorized ? '허용됨' : '꺼짐',
                  style: AppTypo.bodySm.copyWith(
                    color: _pushAuthorized
                        ? context.colors.primaryStrong
                        : context.colors.inkSubtle,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onPressed: () => unawaited(_handlePushRow()),
              ),
            ),
            _sectionHeader(context, '앱 정보'),
            AppCard(
              child: AppListRow(
                horizontalPadding: 0,
                contents: const Text('버전', style: AppTypo.body),
                right: Text(
                  _version ?? '—',
                  style: AppTypo.bodySm.copyWith(
                    color: context.colors.inkMuted,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.xl,
        AppSpace.md,
        AppSpace.xl,
        AppSpace.sm,
      ),
      child: Text(
        title,
        style: AppTypo.caption.copyWith(color: context.colors.inkSubtle),
      ),
    );
  }

  Widget _routesSection() {
    final routes = _routes;
    if (_loadFailed && routes == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '경로를 불러오지 못했어요',
            style: AppTypo.bodySm.copyWith(color: context.colors.inkMuted),
          ),
          const SizedBox(height: AppSpace.md),
          AppButton(
            label: '다시 시도',
            variant: AppButtonVariant.tonal,
            medium: true,
            onPressed: () => unawaited(_load()),
          ),
        ],
      );
    }
    if (routes == null) {
      return Text(
        '불러오는 중…',
        style: AppTypo.bodySm.copyWith(color: context.colors.inkSubtle),
      );
    }
    return Column(
      children: [
        if (routes.isEmpty)
          AppListRow(
            horizontalPadding: 0,
            contents: Text(
              '아직 경로가 없어요',
              style: AppTypo.bodySm.copyWith(color: context.colors.inkMuted),
            ),
          ),
        for (final route in routes)
          AppListRow(
            horizontalPadding: 0,
            contents: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  route.label,
                  style: AppTypo.body.copyWith(fontWeight: FontWeight.w600),
                ),
                Text(
                  _routeSummary(route.setting),
                  style: AppTypo.caption.copyWith(
                    color: context.colors.inkSubtle,
                  ),
                ),
              ],
            ),
            right: Icon(
              Icons.chevron_right,
              size: 20,
              color: context.colors.inkSubtle,
            ),
            onPressed: () => unawaited(_openOnboarding(route.id)),
          ),
        if (routes.length < maxCommuteRoutes)
          AppListRow(
            horizontalPadding: 0,
            contents: Text(
              '+ 경로 추가',
              style: AppTypo.bodySm.copyWith(
                color: context.colors.primaryStrong,
                fontWeight: FontWeight.w600,
              ),
            ),
            onPressed: () => unawaited(_openOnboarding('new')),
          ),
      ],
    );
  }

  String _routeSummary(CommuteSetting setting) {
    final mode = setting.notificationMode == NotificationMode.fixed
        ? '정시 ${formatKoreanTime(setting.fixedDepartureTime ?? '')}'
        : '추천 ${setting.commuteWindow?.start}~${setting.commuteWindow?.end}';
    return '정류장 ${setting.stops.length} · $mode';
  }
}
