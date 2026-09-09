import 'dart:async';

import 'package:flutter/material.dart';

import '../data/api.dart';
import '../domain/models.dart';
import '../domain/onboarding.dart';
import '../platform/location.dart';
import 'components/location_preview_map.dart';
import 'components/time_field.dart';
import 'design/components/button.dart';
import 'design/components/chip.dart';
import 'design/components/list_row.dart';
import 'design/components/text_field.dart';
import 'design/tokens.dart';

/// 온보딩 7단계 위저드 — 미니앱 OnboardingWizard.tsx 이식.
/// 단계 순서·문구·위젯 배치(단계 표시 → 제목 → 본문 → 하단 이전/다음 CTA)를 동일하게 유지한다.
class OnboardingWizard extends StatefulWidget {
  const OnboardingWizard({
    super.key,
    required this.initialDraft,
    required this.onComplete,
    this.completeLabel = '완료',
  });

  /// 재설정 프리필 — 기존 설정을 settingToDraft로 변환해 넘긴다
  final OnboardingDraft initialDraft;

  /// 완료 시 저장 — 실패(throw)하면 위저드가 에러를 표시하고 재시도할 수 있게 한다.
  /// label은 경로 이름(1~16자, trim됨)
  final Future<void> Function(CommuteSetting setting, String label) onComplete;

  /// 마지막 단계 CTA 문구 — 재설정에서는 "변경 내용 저장"으로 구분한다
  final String completeLabel;

  @override
  State<OnboardingWizard> createState() => _OnboardingWizardState();
}

const Map<OnboardingStep, String> _stepTitles = {
  OnboardingStep.home: '출발지를 등록해주세요',
  OnboardingStep.stops: '출발 정류장·역을 검색해 선택해주세요',
  OnboardingStep.walk: '출발지에서 정류장까지 도보 몇 분인가요?',
  OnboardingStep.mode: '알림을 어떻게 받을까요?',
  OnboardingStep.buffer: '여유 시간을 골라주세요',
  OnboardingStep.days: '알림 받을 요일을 골라주세요',
  OnboardingStep.label: '이 경로의 이름을 정해주세요',
};

/// 자주 쓰는 경로 이름 — 탭 한 번으로 채우는 제안일 뿐, 자유 입력이 기본이다
const List<String> _labelPresets = ['출근', '퇴근'];

const List<int> _walkPresets = [5, 8, 10, 15];

const List<({String label, int minutes})> _bufferPresets = [
  (label: '빠듯하게 (+1분)', minutes: 1),
  (label: '보통 (+2분)', minutes: 2),
  (label: '넉넉하게 (+3분)', minutes: 3),
];

const List<({DayOfWeek day, String label})> _dayLabels = [
  (day: DayOfWeek.mon, label: '월'),
  (day: DayOfWeek.tue, label: '화'),
  (day: DayOfWeek.wed, label: '수'),
  (day: DayOfWeek.thu, label: '목'),
  (day: DayOfWeek.fri, label: '금'),
  (day: DayOfWeek.sat, label: '토'),
  (day: DayOfWeek.sun, label: '일'),
];

const List<DayOfWeek> _weekdays = [
  DayOfWeek.mon,
  DayOfWeek.tue,
  DayOfWeek.wed,
  DayOfWeek.thu,
  DayOfWeek.fri,
];

class _OnboardingWizardState extends State<OnboardingWizard> {
  late OnboardingDraft _draft = widget.initialDraft;
  int _stepIndex = 0;
  bool _saving = false;
  bool _saveFailed = false;

  OnboardingStep get _step => onboardingSteps[_stepIndex];

  bool get _isLast => _stepIndex == onboardingSteps.length - 1;

  void _update(OnboardingDraft next) => setState(() => _draft = next);

  Future<void> _submit() async {
    setState(() {
      _saving = true;
      _saveFailed = false;
    });
    try {
      await widget.onComplete(buildSetting(_draft), _draft.label.trim());
    } catch (_) {
      // 저장 실패 — 조용히 삼키지 않고 명시하고 재시도를 허용한다 (NFR-03)
      if (mounted) {
        setState(() => _saveFailed = true);
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  void _handleNext() {
    if (!canProceed(_step, _draft) || _saving) {
      return;
    }
    if (_isLast) {
      unawaited(_submit());
    } else {
      setState(() => _stepIndex++);
    }
  }

  /// 이전 단계로 돌아가 재설정 — draft는 유지되므로 고른 값이 그대로 남아 있다
  void _handleBack() {
    if (_saving || _stepIndex == 0) {
      return;
    }
    setState(() {
      _saveFailed = false;
      _stepIndex--;
    });
  }

  @override
  Widget build(BuildContext context) {
    final proceedable = canProceed(_step, _draft);

    // 시스템 뒤로가기(내비바 백버튼·iOS 스와이프·안드로이드 하드웨어 백)도 이전 단계로 —
    // 1단계에서만 화면을 이탈한다. 저장 중에는 이벤트만 소비해 저장 중 이탈을 막는다.
    return PopScope(
      canPop: _stepIndex == 0 && !_saving,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _handleBack();
        }
      },
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${_stepIndex + 1} / ${onboardingSteps.length}',
                    style: AppTypo.bodySm.copyWith(color: context.colors.inkSubtle),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _stepTitles[_step]!,
                    style: AppTypo.title,
                  ),
                  const SizedBox(height: 20),
                  _stepBody(),
                ],
              ),
            ),
          ),
          // 하단 CTA — 저장 실패 문구 + [이전(1/3)] [다음/완료(2/3)]
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                if (_saveFailed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      '설정을 저장하지 못했어요. 네트워크를 확인하고 다시 시도해주세요',
                      textAlign: TextAlign.center,
                      style: AppTypo.bodySm.copyWith(color: context.colors.dangerStrong),
                    ),
                  ),
                Row(
                  children: [
                    if (_stepIndex > 0) ...[
                      Expanded(
                        child: AppButton(
                          label: '이전',
                          variant: AppButtonVariant.neutral,
                          block: true,
                          onPressed: _saving ? null : _handleBack,
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      flex: 2,
                      child: AppButton(
                        label: _isLast ? widget.completeLabel : '다음',
                        block: true,
                        loading: _saving,
                        onPressed: proceedable ? _handleNext : null,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _stepBody() {
    switch (_step) {
      case OnboardingStep.home:
        return _HomeStep(draft: _draft, update: _update);
      case OnboardingStep.stops:
        return _StopsStep(draft: _draft, update: _update);
      case OnboardingStep.walk:
        return _WalkStep(draft: _draft, update: _update);
      case OnboardingStep.mode:
        return _ModeStep(draft: _draft, update: _update);
      case OnboardingStep.buffer:
        return _BufferStep(draft: _draft, update: _update);
      case OnboardingStep.days:
        return _DaysStep(draft: _draft, update: _update);
      case OnboardingStep.label:
        return _LabelStep(draft: _draft, update: _update);
    }
  }
}

class _Helper extends StatelessWidget {
  const _Helper(this.text, {this.color});

  final String text;

  /// null이면 기본 힌트색(inkSubtle) — const 생성을 위해 팔레트 참조는 build에서
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Text(
        text,
        style: AppTypo.caption.copyWith(color: color ?? context.colors.inkSubtle),
      ),
    );
  }
}

/// 선택형 행 — 미니앱 SelectRow 이식
class _SelectRow extends StatelessWidget {
  const _SelectRow({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: double.infinity,
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: selected ? context.colors.primarySoft : context.colors.fill,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            label,
            style: AppTypo.body.copyWith(
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: selected ? context.colors.primaryStrong : context.colors.ink,
            ),
          ),
        ),
      ),
    );
  }
}

const Map<StopType, String> _typeLabels = {
  StopType.seoulBus: '서울 버스',
  StopType.gyeonggiBus: '경기 버스',
  StopType.subway: '지하철',
};

/// GPS(현재 위치) 또는 주소 검색으로 집 위치를 등록한다 (FR-101 + GPS 부정확 대응)
class _HomeStep extends StatefulWidget {
  const _HomeStep({required this.draft, required this.update});

  final OnboardingDraft draft;
  final ValueChanged<OnboardingDraft> update;

  @override
  State<_HomeStep> createState() => _HomeStepState();
}

class _HomeStepState extends State<_HomeStep> {
  final TextEditingController _query = TextEditingController();
  bool _locating = false;
  bool _locateFailed = false;
  bool _searching = false;
  bool _searchFailed = false;
  List<GeocodeResult>? _results;

  /// 확인 문구에 쓸 주소 — 주소 검색으로 골랐거나, GPS 등록 직후 역지오코딩(§7-1)이 채운다.
  /// GPS로 재등록하면 일단 비우고 역지오코딩 결과로 다시 채운다
  String? _selectedAddress;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  bool get _searchable => _query.text.trim().length >= 2; // §7: 2자 미만은 400

  Future<void> _locate() async {
    setState(() {
      _locating = true;
      _locateFailed = false;
    });
    try {
      final home = await requestCurrentLocation();
      if (!mounted) {
        return;
      }
      widget.update(widget.draft.copyWith(home: home));
      setState(() => _selectedAddress = null);
      // "어떤 주소로 잡혔는지" 확인 문구 (TODO 2026-09-09) — 표시 전용이라 기다리지 않는다
      unawaited(_confirmAddress(home));
    } catch (_) {
      // 권한 거부·GPS 실패 — 아는 척하지 않고 실패를 명시한다 (NFR-03 원칙 동일 적용)
      if (mounted) {
        setState(() => _locateFailed = true);
      }
    } finally {
      if (mounted) {
        setState(() => _locating = false);
      }
    }
  }

  /// GPS 좌표가 어떤 주소로 잡혔는지 역지오코딩(§7-1)으로 확인시킨다.
  /// 실패(503 등)해도 등록 흐름은 계속 — 일반 안내 문구로 강등될 뿐이다.
  Future<void> _confirmAddress(GeoPoint home) async {
    try {
      final result = await api.reverseGeocode(home.latitude, home.longitude);
      final address = result.displayAddress;
      if (mounted && address != null) {
        setState(() => _selectedAddress = address);
      }
    } catch (_) {
      // 표시 전용 — 조용히 일반 문구를 유지한다
    }
  }

  Future<void> _search() async {
    if (!_searchable || _searching) {
      return;
    }
    setState(() {
      _searching = true;
      _searchFailed = false;
    });
    try {
      final results = await api.geocode(_query.text.trim());
      if (mounted) {
        setState(() => _results = results);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _results = null;
          _searchFailed = true;
        });
      }
    } finally {
      if (mounted) {
        setState(() => _searching = false);
      }
    }
  }

  void _selectAddress(GeocodeResult result) {
    widget.update(
      widget.draft.copyWith(
        home: GeoPoint(latitude: result.latitude, longitude: result.longitude),
      ),
    );
    setState(() {
      _selectedAddress = result.roadAddress.isNotEmpty
          ? result.roadAddress
          : result.jibunAddress;
      _results = null;
      _query.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final home = widget.draft.home;
    final results = _results;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 지도를 맨 위에 — 등록·검색 버튼은 아래쪽이 엄지로 누르기 편하다
        if (home != null) ...[
          LocationPreviewMap(point: home),
          _Helper(
            _selectedAddress != null
                ? '$_selectedAddress 기준으로 등록됐어요'
                : '출발지가 등록됐어요. 지도에서 위치를 확인해주세요',
            color: context.colors.primaryStrong,
          ),
          const SizedBox(height: 12),
        ],
        AppButton(
          label: '현재 위치로 등록',
          block: true,
          loading: _locating,
          onPressed: _locating ? null : () => unawaited(_locate()),
        ),
        if (_locateFailed)
          _Helper(
            '위치를 가져오지 못했어요. 다시 시도하거나 아래에서 주소로 등록해주세요',
            color: context.colors.dangerStrong,
          ),
        const SizedBox(height: 24),
        Text(
          '현재 위치가 부정확하면 주소로 등록하세요',
          style: AppTypo.bodySm.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: AppTextField(
                placeholder: '도로명·지번 주소 (2자 이상)',
                controller: _query,
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => unawaited(_search()),
                textInputAction: TextInputAction.search,
              ),
            ),
            const SizedBox(width: 8),
            AppButton(
              label: '검색',
              loading: _searching,
              onPressed: _searchable ? () => unawaited(_search()) : null,
            ),
          ],
        ),
        if (_searchFailed)
          _Helper(
            '주소를 검색하지 못했어요. 네트워크를 확인하고 다시 시도해주세요',
            color: context.colors.dangerStrong,
          ),
        if (results != null && results.isEmpty)
          _Helper('검색 결과가 없어요. 주소를 다시 확인해주세요', color: context.colors.inkMuted),
        if (results != null)
          for (final result in results)
            AppListRow(
              horizontalPadding: 0,
              onPressed: () => _selectAddress(result),
              contents: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(result.roadAddress, style: AppTypo.body),
                  Text(
                    result.jibunAddress,
                    style: AppTypo.caption.copyWith(color: context.colors.inkSubtle),
                  ),
                ],
              ),
            ),
      ],
    );
  }
}

/// 검색으로 고른 정류장/역 + 경유 노선 로딩 상태. draft.stops에는 노선을 1개 이상 고른 것만 들어간다
class _StopCandidate {
  _StopCandidate({
    required this.type,
    required this.stopId,
    required this.displayName,
    required this.subtitle,
  });

  final StopType type;
  final String stopId;
  final String displayName;
  final String subtitle;
  List<RouteOption> routes = const [];
  _RoutesStatus routesStatus = _RoutesStatus.loading;

  String get key => '${type.wire}:$stopId';
}

enum _RoutesStatus { loading, ready, error }

class _StopsStep extends StatefulWidget {
  const _StopsStep({required this.draft, required this.update});

  final OnboardingDraft draft;
  final ValueChanged<OnboardingDraft> update;

  @override
  State<_StopsStep> createState() => _StopsStepState();
}

class _StopsStepState extends State<_StopsStep> {
  final TextEditingController _query = TextEditingController();
  bool _searching = false;
  bool _searchFailed = false;
  List<StopSearchResult>? _results;

  // 재설정 프리필 — draft에 이미 있는 정류장을 후보로 복원한다.
  // 원본 subtitle은 저장되지 않으므로 유형 라벨로 대체
  late final List<_StopCandidate> _candidates = [
    for (final stop in widget.draft.stops)
      _StopCandidate(
        type: stop.type,
        stopId: stop.stopId,
        displayName: stop.displayName,
        subtitle: _typeLabels[stop.type]!,
      ),
  ];

  @override
  void initState() {
    super.initState();
    // 프리필된 후보의 노선 목록 로딩 — 마운트 시 1회
    // (실패해도 이미 고른 노선으로 진행 가능, 후보별 재시도 제공)
    for (final candidate in _candidates) {
      unawaited(_loadRoutes(candidate));
    }
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  bool get _searchable => _query.text.trim().length >= 2; // §5-1: 2자 미만은 400

  String _stopKey(StopSearchResult result) => '${result.type.wire}:${result.stopId}';

  String _draftStopKey(CommuteStop stop) => '${stop.type.wire}:${stop.stopId}';

  Future<void> _search() async {
    if (!_searchable || _searching) {
      return;
    }
    setState(() {
      _searching = true;
      _searchFailed = false;
    });
    try {
      final results = await api.searchStops(_query.text.trim());
      if (mounted) {
        setState(() => _results = results);
      }
    } catch (_) {
      // 서버 장애·네트워크 실패 — 아는 척하지 않고 실패를 명시한다 (NFR-03)
      if (mounted) {
        setState(() {
          _results = null;
          _searchFailed = true;
        });
      }
    } finally {
      if (mounted) {
        setState(() => _searching = false);
      }
    }
  }

  Future<void> _loadRoutes(_StopCandidate candidate) async {
    setState(() => candidate.routesStatus = _RoutesStatus.loading);
    try {
      final routes = await api.getStopRoutes(candidate.type, candidate.stopId);
      if (mounted) {
        setState(() {
          candidate.routes = routes;
          candidate.routesStatus = _RoutesStatus.ready;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => candidate.routesStatus = _RoutesStatus.error);
      }
    }
  }

  void _selectResult(StopSearchResult result) {
    if (_candidates.any((c) => c.key == _stopKey(result))) {
      return;
    }
    // 검색 결과를 접고 새 후보를 맨 위로 — 노선 선택 UI가 검색창 바로 아래에 보이게 한다
    final candidate = _StopCandidate(
      type: result.type,
      stopId: result.stopId,
      displayName: result.displayName,
      subtitle: result.subtitle,
    );
    setState(() {
      _candidates.insert(0, candidate);
      _results = null;
      _query.clear();
    });
    unawaited(_loadRoutes(candidate));
  }

  void _removeCandidate(_StopCandidate candidate) {
    setState(() => _candidates.removeWhere((c) => c.key == candidate.key));
    widget.update(
      widget.draft.copyWith(
        stops: widget.draft.stops
            .where((s) => _draftStopKey(s) != candidate.key)
            .toList(),
      ),
    );
  }

  void _toggleRoute(_StopCandidate candidate, String route) {
    final draft = widget.draft;
    final existing = draft.stops
        .where((s) => _draftStopKey(s) == candidate.key)
        .firstOrNull;
    List<CommuteStop> stops;
    if (existing == null) {
      stops = [
        ...draft.stops,
        CommuteStop(
          type: candidate.type,
          stopId: candidate.stopId,
          displayName: candidate.displayName,
          routes: [route],
        ),
      ];
    } else {
      final has = existing.routes.contains(route);
      final routes = has
          ? existing.routes.where((r) => r != route).toList()
          : [...existing.routes, route];
      stops = routes.isEmpty
          ? draft.stops
                .where((s) => _draftStopKey(s) != candidate.key)
                .toList()
          : draft.stops
                .map(
                  (s) => _draftStopKey(s) == candidate.key
                      ? s.copyWith(routes: routes)
                      : s,
                )
                .toList();
    }
    widget.update(draft.copyWith(stops: stops));
  }

  @override
  Widget build(BuildContext context) {
    final results = _results;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: AppTextField(
                placeholder: '정류장·역 이름 (2자 이상)',
                controller: _query,
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => unawaited(_search()),
                textInputAction: TextInputAction.search,
              ),
            ),
            const SizedBox(width: 8),
            AppButton(
              label: '검색',
              loading: _searching,
              onPressed: _searchable ? () => unawaited(_search()) : null,
            ),
          ],
        ),
        if (_searchFailed)
          _Helper(
            '검색하지 못했어요. 네트워크를 확인하고 다시 시도해주세요',
            color: context.colors.dangerStrong,
          ),
        if (results != null && results.isEmpty)
          _Helper(
            '검색 결과가 없어요. 정류장·역 이름을 다시 확인해주세요',
            color: context.colors.inkMuted,
          ),
        if (results != null)
          for (final result in results)
            AppListRow(
              horizontalPadding: 0,
              onPressed: () => _selectResult(result),
              contents: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(result.displayName, style: AppTypo.body),
                  Text(
                    result.subtitle,
                    style: AppTypo.caption.copyWith(color: context.colors.inkSubtle),
                  ),
                ],
              ),
              right: Text(
                _candidates.any((c) => c.key == _stopKey(result))
                    ? '선택됨'
                    : _typeLabels[result.type]!,
                style: AppTypo.caption.copyWith(
                  color: _candidates.any((c) => c.key == _stopKey(result))
                      ? context.colors.primaryStrong
                      : context.colors.inkSubtle,
                ),
              ),
            ),
        if (_candidates.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 24, bottom: 4),
            child: Text(
              '선택한 정류장·역에서 탈 노선을 골라주세요',
              style: AppTypo.bodySm.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        for (final candidate in _candidates) _candidateSection(candidate),
        const _Helper('서울·경기 버스 정류소와 수도권 지하철역 전체에서 검색할 수 있어요'),
      ],
    );
  }

  Widget _candidateSection(_StopCandidate candidate) {
    final selected = widget.draft.stops
        .where((s) => _draftStopKey(s) == candidate.key)
        .firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppListRow(
          horizontalPadding: 0,
          contents: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                candidate.displayName,
                style: AppTypo.body.copyWith(fontWeight: FontWeight.w600),
              ),
              Text(
                candidate.subtitle,
                style: AppTypo.caption.copyWith(color: context.colors.inkSubtle),
              ),
            ],
          ),
          right: Semantics(
            button: true,
            label: '${candidate.displayName} 삭제',
            child: InkWell(
              onTap: () => _removeCandidate(candidate),
              child: Text(
                '삭제',
                style: AppTypo.caption.copyWith(color: context.colors.inkSubtle),
              ),
            ),
          ),
        ),
        switch (candidate.routesStatus) {
          _RoutesStatus.loading => Text(
            '노선을 불러오는 중이에요…',
            style: AppTypo.caption.copyWith(color: context.colors.inkSubtle),
          ),
          _RoutesStatus.error => InkWell(
            onTap: () => unawaited(_loadRoutes(candidate)),
            child: Text(
              '노선을 불러오지 못했어요. 다시 시도',
              style: AppTypo.caption.copyWith(color: context.colors.dangerStrong),
            ),
          ),
          _RoutesStatus.ready => Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final route in candidate.routes)
                  AppChip(
                    label: route.name,
                    selected: selected?.routes.contains(route.name) ?? false,
                    onPressed: () => _toggleRoute(candidate, route.name),
                  ),
              ],
            ),
          ),
        },
      ],
    );
  }
}

class _WalkStep extends StatelessWidget {
  const _WalkStep({required this.draft, required this.update});

  final OnboardingDraft draft;
  final ValueChanged<OnboardingDraft> update;

  @override
  Widget build(BuildContext context) {
    final walk = draft.walkMinutes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final minutes in _walkPresets)
              AppChip(
                label: '$minutes분',
                selected: walk == minutes,
                onPressed: () =>
                    update(draft.copyWith(walkMinutes: minutes)),
              ),
          ],
        ),
        const SizedBox(height: 12),
        _DirectMinutesField(
          value: walk != null && !_walkPresets.contains(walk) ? walk : null,
          onChanged: (minutes) => update(draft.copyWith(walkMinutes: minutes)),
        ),
        const _Helper('지도 추정이 아니라 직접 입력한 값을 사용해요'),
      ],
    );
  }
}

/// "직접 입력 (분)" 숫자 필드 — walk/buffer 단계 공용
class _DirectMinutesField extends StatefulWidget {
  const _DirectMinutesField({required this.value, required this.onChanged});

  final int? value;
  final ValueChanged<int?> onChanged;

  @override
  State<_DirectMinutesField> createState() => _DirectMinutesFieldState();
}

class _DirectMinutesFieldState extends State<_DirectMinutesField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value?.toString() ?? '',
  );

  @override
  void didUpdateWidget(_DirectMinutesField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 프리셋 칩을 고르면 직접 입력값을 비운다 (미니앱과 동일: 프리셋 외 값만 필드에 남는다)
    if (widget.value == null && _controller.text.isNotEmpty) {
      _controller.clear();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppTextField(
      placeholder: '직접 입력 (분)',
      controller: _controller,
      numberOnly: true,
      onChanged: (text) => widget.onChanged(int.tryParse(text)),
    );
  }
}

class _ModeStep extends StatelessWidget {
  const _ModeStep({required this.draft, required this.update});

  final OnboardingDraft draft;
  final ValueChanged<OnboardingDraft> update;

  @override
  Widget build(BuildContext context) {
    final window = draft.commuteWindow;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SelectRow(
          label: '정시 알림. 출발 시각을 직접 정할게요',
          selected: draft.notificationMode == NotificationMode.fixed,
          onPressed: () => update(
            draft.copyWith(notificationMode: NotificationMode.fixed),
          ),
        ),
        if (draft.notificationMode == NotificationMode.fixed)
          TimeField(
            label: '출발 시각',
            placeholder: '07:40',
            value: draft.fixedDepartureTime,
            onChanged: (time) =>
                update(draft.copyWith(fixedDepartureTime: time)),
          ),
        _SelectRow(
          label: '추천 출발. 시간대만 정하면 알아서 알려줘요',
          selected: draft.notificationMode == NotificationMode.recommended,
          onPressed: () => update(
            draft.copyWith(notificationMode: NotificationMode.recommended),
          ),
        ),
        if (recommendedModeIsEstimated(draft))
          _Helper(
            '도보 ${draft.walkMinutes}분은 지하철 실시간 정보 범위(약 10분)보다 길어요. '
            '열차 배차 간격으로 출발 시각을 추정해 알려드려요. '
            '정확한 시각을 원하면 출발 시각을 직접 정하는 방식이 좋아요',
            color: context.colors.inkMuted,
          ),
        if (draft.notificationMode == NotificationMode.recommended)
          Row(
            children: [
              Expanded(
                child: TimeField(
                  label: '시작 시각',
                  placeholder: '07:30',
                  value: window != null && window.start.isNotEmpty
                      ? window.start
                      : null,
                  onChanged: (time) => update(
                    draft.copyWith(
                      commuteWindow: CommuteWindow(
                        start: time,
                        end: window?.end ?? '',
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  '~',
                  style: AppTypo.body.copyWith(color: context.colors.inkSubtle),
                ),
              ),
              Expanded(
                child: TimeField(
                  label: '끝 시각',
                  placeholder: '08:30',
                  value: window != null && window.end.isNotEmpty
                      ? window.end
                      : null,
                  onChanged: (time) => update(
                    draft.copyWith(
                      commuteWindow: CommuteWindow(
                        start: window?.start ?? '',
                        end: time,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }
}

class _BufferStep extends StatelessWidget {
  const _BufferStep({required this.draft, required this.update});

  final OnboardingDraft draft;
  final ValueChanged<OnboardingDraft> update;

  @override
  Widget build(BuildContext context) {
    final buffer = draft.bufferMinutes;
    final isPreset = _bufferPresets.any((p) => p.minutes == buffer);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final preset in _bufferPresets)
          _SelectRow(
            label: preset.label,
            selected: buffer == preset.minutes,
            onPressed: () =>
                update(draft.copyWith(bufferMinutes: preset.minutes)),
          ),
        const SizedBox(height: 12),
        _DirectMinutesField(
          value: buffer != null && !isPreset ? buffer : null,
          onChanged: (minutes) =>
              update(draft.copyWith(bufferMinutes: minutes)),
        ),
        const _Helper('1차 알림은 출발 시각에서 여유 시간만큼 먼저 와요'),
      ],
    );
  }
}

class _DaysStep extends StatelessWidget {
  const _DaysStep({required this.draft, required this.update});

  final OnboardingDraft draft;
  final ValueChanged<OnboardingDraft> update;

  @override
  Widget build(BuildContext context) {
    final activeDays = draft.activeDays;
    final weekdaysOnly =
        activeDays.length == 5 && _weekdays.every(activeDays.contains);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            AppChip(
              label: '평일',
              selected: weekdaysOnly,
              onPressed: () =>
                  update(draft.copyWith(activeDays: List.of(_weekdays))),
            ),
            for (final entry in _dayLabels)
              AppChip(
                label: entry.label,
                selected: activeDays.contains(entry.day),
                onPressed: () {
                  final has = activeDays.contains(entry.day);
                  final nextDays = has
                      ? activeDays.where((d) => d != entry.day).toList()
                      : [...activeDays, entry.day];
                  // 요일 순서 유지 (월→일)
                  update(
                    draft.copyWith(
                      activeDays: [
                        for (final e in _dayLabels)
                          if (nextDays.contains(e.day)) e.day,
                      ],
                    ),
                  );
                },
              ),
          ],
        ),
        const _Helper('평일만 고르면 공휴일 아침에는 알림을 쉬어요'),
      ],
    );
  }
}

class _LabelStep extends StatefulWidget {
  const _LabelStep({required this.draft, required this.update});

  final OnboardingDraft draft;
  final ValueChanged<OnboardingDraft> update;

  @override
  State<_LabelStep> createState() => _LabelStepState();
}

class _LabelStepState extends State<_LabelStep> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.draft.label,
  );

  @override
  void didUpdateWidget(_LabelStep oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 프리셋 칩으로 채웠을 때 필드에도 반영한다
    if (widget.draft.label != _controller.text) {
      _controller.text = widget.draft.label;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final preset in _labelPresets)
              AppChip(
                label: preset,
                selected: widget.draft.label == preset,
                onPressed: () =>
                    widget.update(widget.draft.copyWith(label: preset)),
              ),
          ],
        ),
        const SizedBox(height: 12),
        AppTextField(
          placeholder: '예: 출근, 학원, 마을버스',
          controller: _controller,
          maxLength: routeLabelMaxLength,
          onChanged: (text) => widget.update(widget.draft.copyWith(label: text)),
        ),
        const _Helper('목록에서 경로를 구분하는 이름이에요 (같은 이름은 쓸 수 없어요)'),
      ],
    );
  }
}
