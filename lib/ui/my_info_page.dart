import 'dart:async';

import 'package:flutter/material.dart';

import '../data/api.dart';
import '../data/push_registrar.dart';
import '../domain/journey.dart';
import '../domain/models.dart';
import '../domain/time_format.dart';
import '../platform/app_info.dart';
import '../platform/push.dart';
import 'components/fade_route.dart';
import 'components/push_settings_sheet.dart';
import 'components/tab_header.dart';
import 'design/components/button.dart';
import 'design/components/card.dart';
import 'design/components/list_row.dart';
import 'design/components/sheet.dart';
import 'design/tokens.dart';
import 'journey_create_page.dart';
import 'onboarding_page.dart';

/// §3-2·§9 기반 섹션의 로드 상태 — 미배포 서버(404)는 "준비 중"으로 강등
enum _SectionPhase { loading, unavailable, failed, ready }

/// 내정보 탭 — 계정이 없는 앱(익명 키)이라 "내 것"의 관리가 곧 내정보다 (개편 2026-09-16, 명세서 §9):
/// 통근 경로 · 여정 관리 · 알림(상태+정책) · 앱 정보.
/// 통근 기록(잔디)은 메인 탭이 뎁스 없이 노출한다 (오너 결정 2026-09-19 — 리포트 화면 제거).
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

  _SectionPhase _journeyPhase = _SectionPhase.loading;
  List<Journey> _journeys = [];

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
    unawaited(_loadJourneys());
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

  Future<void> _loadJourneys() async {
    try {
      final journeys = await api.listJourneys();
      if (!mounted) {
        return;
      }
      setState(() {
        _journeys = journeys;
        _journeyPhase = _SectionPhase.ready;
      });
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(
        () => _journeyPhase = error.status == 404
            ? _SectionPhase.unavailable
            : _SectionPhase.failed,
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _journeyPhase = _SectionPhase.failed);
    }
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
      MaterialPageRoute<void>(builder: (_) => OnboardingPage(routeId: routeId)),
    );
    unawaited(_load());
  }

  Future<void> _openJourneyCreate() async {
    final created = await Navigator.of(
      context,
    ).push<bool>(fadeRoute(const JourneyCreatePage()));
    if (created == true) {
      unawaited(_load());
    }
  }

  Future<void> _deleteJourney(Journey journey) async {
    // 하차 알림 탭과 같은 확인 시트 — 관리 진입점이 늘어도 규칙은 하나
    final confirmed = await showAppSheet<bool>(
      context: context,
      header: '"${journey.label}" 여정을 삭제할까요?',
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpace.xl,
          0,
          AppSpace.xl,
          AppSpace.lg,
        ),
        child: AppButton(
          label: '삭제',
          variant: AppButtonVariant.danger,
          block: true,
          onPressed: () => Navigator.of(sheetContext).pop(true),
        ),
      ),
    );
    if (confirmed != true) {
      return;
    }
    try {
      await api.deleteJourney(journey.id);
    } on ApiException catch (error) {
      // 이미 없는 여정은 목적 달성 — 목록 갱신으로 정리
      if (error.code != ApiException.settingNotFound && error.status != 404) {
        return;
      }
    } catch (_) {
      return;
    }
    unawaited(_loadJourneys());
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
      unawaited(showPushSettingsSheet(context));
    }
  }

  /// 알림 정책 안내 — "알림이 똑똑하다"는 신뢰가 이 앱의 핵심 (FR-403·405, 명세서 §9)
  void _showPolicySheet() {
    unawaited(
      showAppSheet<void>(
        context: context,
        header: '알림, 꼭 필요한 만큼만 보내요',
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
                '· 출근 1번에 최대 2번이에요. 출발 전 사전 알림과 1분 전 리마인드예요\n'
                '· 주말·미적용 요일, 공휴일(평일 경로)에는 보내지 않아요\n'
                '· 그날 "탔어요"를 누르면 더 보내지 않아요',
                style: AppTypo.bodySm.copyWith(
                  color: sheetContext.colors.inkMuted,
                  height: 1.6,
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

  @override
  Widget build(BuildContext context) {
    // 콘텐츠가 글라스 헤더·네비 뒤로 흐른다 — 상하 여백은 ListView padding이 담당
    final headerBottom =
        MediaQuery.paddingOf(context).top + TabHeader.contentHeight;
    return Scaffold(
      backgroundColor: context.colors.background,
      extendBodyBehindAppBar: true,
      appBar: const TabHeader(title: '내정보'),
      body: RefreshIndicator.adaptive(
        edgeOffset: headerBottom,
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.only(
            top: headerBottom + AppSpace.md,
            bottom: MediaQuery.paddingOf(context).bottom + AppSpace.lg,
          ),
          children: [
            _sectionHeader(context, '통근 경로'),
            AppCard(child: _routesSection()),
            _sectionHeader(context, '여정 관리'),
            AppCard(child: _journeySection()),
            _sectionHeader(context, '알림'),
            AppCard(
              child: Column(
                children: [
                  AppListRow(
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
                  AppListRow(
                    horizontalPadding: 0,
                    contents: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('알림 정책', style: AppTypo.body),
                        Text(
                          '출근 1번에 최대 2번만 보내드려요',
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
                    onPressed: _showPolicySheet,
                  ),
                ],
              ),
            ),
            _sectionHeader(context, '앱 정보'),
            AppCard(
              child: AppListRow(
                horizontalPadding: 0,
                contents: const Text('버전', style: AppTypo.body),
                right: Text(
                  _version ?? '확인 중',
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

  /// 섹션 헤더 — 헤더 영역 타이틀(AppTypo.title)과 같은 폰트, 메인 탭과 동일
  /// (오너 피드백 2026-09-19: 캡션은 눈에 안 들어온다)
  Widget _sectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.xl,
        AppSpace.md,
        AppSpace.xl,
        AppSpace.sm,
      ),
      child: Text(title, style: AppTypo.title),
    );
  }

  /// 여정 관리 — 하차 알림 여정도 내정보에서 관리한다 (경로와의 비대칭 해소, §9 2026-09-16)
  Widget _journeySection() {
    switch (_journeyPhase) {
      case _SectionPhase.loading:
        return Text(
          '불러오는 중…',
          style: AppTypo.bodySm.copyWith(color: context.colors.inkSubtle),
        );
      case _SectionPhase.unavailable:
        return Text(
          '하차 알림은 서버 업데이트 후 이용할 수 있어요',
          style: AppTypo.bodySm.copyWith(color: context.colors.inkMuted),
        );
      case _SectionPhase.failed:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '여정을 불러오지 못했어요',
              style: AppTypo.bodySm.copyWith(color: context.colors.inkMuted),
            ),
            const SizedBox(height: AppSpace.md),
            AppButton(
              label: '다시 시도',
              variant: AppButtonVariant.tonal,
              medium: true,
              onPressed: () => unawaited(_loadJourneys()),
            ),
          ],
        );
      case _SectionPhase.ready:
        return Column(
          children: [
            if (_journeys.isEmpty)
              AppListRow(
                horizontalPadding: 0,
                contents: Text(
                  '아직 여정이 없어요',
                  style: AppTypo.bodySm.copyWith(
                    color: context.colors.inkMuted,
                  ),
                ),
              ),
            for (final journey in _journeys)
              AppListRow(
                horizontalPadding: 0,
                contents: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      journey.label,
                      style: AppTypo.body.copyWith(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      journeyPathSummary(journey.legs),
                      style: AppTypo.caption.copyWith(
                        color: context.colors.inkSubtle,
                      ),
                    ),
                  ],
                ),
                right: GestureDetector(
                  onTap: () => unawaited(_deleteJourney(journey)),
                  behavior: HitTestBehavior.opaque,
                  child: Icon(
                    Icons.delete_outline,
                    size: 20,
                    color: context.colors.inkSubtle,
                  ),
                ),
              ),
            if (_journeys.length < maxJourneys)
              AppListRow(
                horizontalPadding: 0,
                contents: Text(
                  '+ 여정 만들기',
                  style: AppTypo.bodySm.copyWith(
                    color: context.colors.primaryStrong,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onPressed: () => unawaited(_openJourneyCreate()),
              ),
          ],
        );
    }
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
