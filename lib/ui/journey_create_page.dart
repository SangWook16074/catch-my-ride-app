import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/active_trip.dart';
import '../data/api.dart';
import '../data/recent_routes_store.dart';
import '../data/trip_start.dart';
import '../domain/journey.dart';
import '../domain/models.dart';
import 'design/components/button.dart';
import 'design/components/card.dart';
import 'design/components/chip.dart';
import 'design/components/list_row.dart';
import 'design/components/sheet.dart';
import 'design/components/text_field.dart';
import 'design/tokens.dart';
import 'journey_page.dart' show journeyDayLabels;

/// 시작 모드 결과 — 시작된 트립과 구간 스냅숏 (호출자가 트립 화면으로 넘긴다).
/// 저장 스위치를 켜고 시작했으면 여정 id·라벨도 함께
class JourneyTripStarted {
  const JourneyTripStarted({
    required this.tripId,
    required this.legs,
    this.journeyId,
    this.journeyLabel,
  });

  final String tripId;
  final List<JourneyLeg> legs;
  final String? journeyId;
  final String? journeyLabel;
}

enum JourneyCreateMode {
  /// 여정 저장만 (FR-701/702) — 이름·구간·요일 입력, "저장". pop 결과 `true`
  save,

  /// 바로 시작 (FR-708, 오너 화면 재구성 2026-09-21) — 구간을 넣고 "추적 시작". 저장은
  /// 스위치 하나("경로 저장하기")로 얹는다: 켜면 이름·요일이 펼쳐지고 저장 후 시작.
  /// pop 결과 [JourneyTripStarted]
  start,
}

/// 여정 입력 화면 — 구간(탑승 역 → 노선 → 하차 역)을 이어 붙인다.
/// 역 검색은 §5-1 재사용(v1 지하철만), 방면은 서버가 역 순서로 유도(API.md §9 — 입력 없음).
class JourneyCreatePage extends StatefulWidget {
  const JourneyCreatePage({super.key, this.mode = JourneyCreateMode.save});

  final JourneyCreateMode mode;

  @override
  State<JourneyCreatePage> createState() => _JourneyCreatePageState();
}

class _JourneyCreatePageState extends State<JourneyCreatePage> {
  final TextEditingController _label = TextEditingController();
  final List<JourneyLeg> _legs = [];
  final Set<DayOfWeek> _repeatDays = {};
  String? _error;
  bool _saving = false;

  /// 시작 모드의 "경로 저장하기" 스위치 — 기본 꺼짐(1회성이 기본 동선)
  bool _saveToo = false;

  bool get _startMode => widget.mode == JourneyCreateMode.start;

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  Future<void> _addLeg() async {
    final board = await _pickStation(
      _legs.isEmpty ? '탑승 역 검색' : '환승 후 탑승 역 검색',
    );
    if (board == null || !mounted) {
      return;
    }
    final line = await _pickLine(board);
    if (line == null || !mounted) {
      return;
    }
    final alight = await _pickStation('하차 역 검색');
    if (alight == null || !mounted) {
      return;
    }
    setState(() {
      _legs.add(
        JourneyLeg(
          line: line.name,
          boardStop: board.stopId,
          alightStop: alight.stopId,
        ),
      );
      _error = null;
    });
  }

  Future<StopSearchResult?> _pickStation(String title) {
    return showAppSheet<StopSearchResult>(
      context: context,
      header: title,
      builder: (_) => const _StationSearchSheet(),
    );
  }

  Future<RouteOption?> _pickLine(StopSearchResult board) async {
    final List<RouteOption> lines;
    try {
      lines = await api.getStopRoutes(StopType.subway, board.stopId);
    } catch (_) {
      if (mounted) {
        setState(() => _error = '노선을 불러오지 못했어요. 다시 시도해주세요');
      }
      return null;
    }
    if (!mounted) {
      return null;
    }
    return showAppSheet<RouteOption>(
      context: context,
      header: '${board.displayName}에서 타는 노선',
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final line in lines)
            AppListRow(
              contents: Text(line.name, style: AppTypo.body),
              right: line.isExpress == true
                  ? Text(
                      '급행',
                      style: AppTypo.caption.copyWith(
                        color: sheetContext.colors.cautionStrong,
                      ),
                    )
                  : null,
              onPressed: () => Navigator.of(sheetContext).pop(line),
            ),
          const SizedBox(height: AppSpace.lg),
        ],
      ),
    );
  }

  JourneyRequest _request() => JourneyRequest(
    label: _label.text,
    repeatDays: [
      for (final entry in journeyDayLabels)
        if (_repeatDays.contains(entry.day)) entry.day,
    ],
    legs: List.of(_legs),
  );

  /// 시작 모드 — 스위치가 꺼져 있으면 저장 없이 바로 추적(FR-708, 최근 간 길에 남긴다),
  /// 켜져 있으면 여정으로 저장한 뒤 그 여정으로 시작한다. 구간 검증은 둘 다 같은 규칙
  Future<void> _start() async {
    final legs = List.of(_legs);
    final message = _saveToo
        ? validateJourneyRequest(_request())
        : validateJourneyLegs(legs);
    if (message != null) {
      setState(() => _error = message);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final JourneyTripStarted result;
      if (_saveToo) {
        final journey = await api.createJourney(_request());
        final start = await startJourneyTrip(journey.id);
        unawaited(
          activeTrip.begin(
            tripId: start.tripId,
            label: journey.label,
            journeyId: journey.id,
          ),
        );
        result = JourneyTripStarted(
          tripId: start.tripId,
          legs: legs,
          journeyId: journey.id,
          journeyLabel: journey.label,
        );
      } else {
        final start = await startQuickTrip(legs);
        unawaited(
          activeTrip.begin(
            tripId: start.tripId,
            label: journeyPathSummary(legs),
            legs: legs,
          ),
        );
        unawaited(RecentRoutesStore().push(legs));
        result = JourneyTripStarted(tripId: start.tripId, legs: legs);
      }
      if (!mounted) {
        return;
      }
      // 햅틱: 트립 시작 = 주요 확정 액션 (CLAUDE.md 적응형 UI 규칙)
      unawaited(HapticFeedback.mediumImpact());
      Navigator.of(context).pop(result);
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _saving = false;
        _error = error.message;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _saving = false;
        _error = '시작하지 못했어요. 네트워크를 확인해주세요';
      });
    }
  }

  Future<void> _save() async {
    final request = _request();
    final message = validateJourneyRequest(request);
    if (message != null) {
      setState(() => _error = message);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await api.createJourney(request);
      if (!mounted) {
        return;
      }
      // 햅틱: 여정 저장 확정 (CLAUDE.md 적응형 UI 규칙)
      unawaited(HapticFeedback.mediumImpact());
      Navigator.of(context).pop(true);
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _saving = false;
        _error = error.message;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _saving = false;
        _error = '저장하지 못했어요. 네트워크를 확인해주세요';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final start = _startMode;
    // 저장 입력(이름·요일)은 저장 모드에선 항상, 시작 모드에선 스위치를 켰을 때만
    final showSaveFields = !start || _saveToo;
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(
        title: Text(start ? '어디까지 가세요?' : '경로 생성', style: AppTypo.heading),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: AppSpace.lg),
          children: [
            if (start)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpace.xl,
                  0,
                  AppSpace.xl,
                  AppSpace.sm,
                ),
                child: Text(
                  '탑승 역과 내릴 역만 넣으면 바로 추적해요',
                  style: AppTypo.bodySm.copyWith(
                    color: context.colors.inkMuted,
                  ),
                ),
              ),
            _sectionHeader('구간 (환승하면 이어 붙여주세요)'),
            for (final (index, leg) in _legs.indexed)
              AppCard(
                margin: const EdgeInsets.only(
                  left: AppSpace.xl,
                  right: AppSpace.xl,
                  bottom: AppSpace.sm,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${leg.boardStop} → ${leg.alightStop}',
                            style: AppTypo.body.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            leg.line,
                            style: AppTypo.caption.copyWith(
                              color: context.colors.inkSubtle,
                            ),
                          ),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: () => setState(() => _legs.removeAt(index)),
                      behavior: HitTestBehavior.opaque,
                      child: Icon(
                        Icons.close,
                        size: 20,
                        color: context.colors.inkSubtle,
                      ),
                    ),
                  ],
                ),
              ),
            if (_legs.length < maxJourneyLegs)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpace.xl,
                  AppSpace.sm,
                  AppSpace.xl,
                  0,
                ),
                child: AppButton(
                  label: '+ 구간 추가',
                  variant: AppButtonVariant.tonal,
                  medium: true,
                  block: true,
                  onPressed: () => unawaited(_addLeg()),
                ),
              ),
            if (start) ...[
              const SizedBox(height: AppSpace.lg),
              // 저장은 선택 — 스위치 하나로 얹는다 (오너 화면 재구성 2026-09-21).
              // 적응형 UI 규칙: 스위치는 .adaptive
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.xl),
                child: AppCard(
                  margin: EdgeInsets.zero,
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('경로 저장하기', style: AppTypo.body),
                            const SizedBox(height: 2),
                            Text(
                              '자주 가는 길이면 다음엔 원탭으로 시작해요',
                              style: AppTypo.caption.copyWith(
                                color: context.colors.inkSubtle,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch.adaptive(
                        value: _saveToo,
                        onChanged: (value) => setState(() {
                          _saveToo = value;
                          _error = null;
                        }),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            if (showSaveFields) ...[
              _sectionHeader('이름'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.xl),
                child: AppTextField(
                  placeholder: '예: 회사, 본가, 병원',
                  controller: _label,
                  maxLength: journeyLabelMaxLength,
                ),
              ),
              _sectionHeader('요일 반복 (선택)'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.xl),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final entry in journeyDayLabels)
                      AppChip(
                        label: entry.label,
                        selected: _repeatDays.contains(entry.day),
                        onPressed: () => setState(() {
                          if (!_repeatDays.add(entry.day)) {
                            _repeatDays.remove(entry.day);
                          }
                        }),
                      ),
                  ],
                ),
              ),
            ],
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpace.xl,
                  AppSpace.lg,
                  AppSpace.xl,
                  0,
                ),
                child: Text(
                  _error!,
                  style: AppTypo.bodySm.copyWith(
                    color: context.colors.dangerStrong,
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(AppSpace.xl),
              child: AppButton(
                label: start
                    ? (_saveToo ? '저장하고 추적 시작' : '추적 시작')
                    : '저장',
                block: true,
                loading: _saving,
                onPressed: _saving
                    ? null
                    : () => unawaited(start ? _start() : _save()),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.xl,
        AppSpace.lg,
        AppSpace.xl,
        AppSpace.sm,
      ),
      child: Text(
        title,
        style: AppTypo.caption.copyWith(color: context.colors.inkSubtle),
      ),
    );
  }
}

/// §5-1 지하철역 검색 시트 — 결과를 탭하면 pop(StopSearchResult)
class _StationSearchSheet extends StatefulWidget {
  const _StationSearchSheet();

  @override
  State<_StationSearchSheet> createState() => _StationSearchSheetState();
}

class _StationSearchSheetState extends State<_StationSearchSheet> {
  final TextEditingController _query = TextEditingController();
  List<StopSearchResult> _results = [];
  bool _searched = false;
  bool _searching = false;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final query = _query.text.trim();
    if (query.length < 2) {
      return;
    }
    setState(() => _searching = true);
    try {
      final results = await api.searchStops(query);
      if (!mounted) {
        return;
      }
      setState(() {
        // v1은 지하철만 (API.md §9)
        _results = [
          for (final result in results)
            if (result.type == StopType.subway) result,
        ];
        _searched = true;
        _searching = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _results = [];
        _searched = true;
        _searching = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.xl),
            child: Row(
              children: [
                Expanded(
                  child: AppTextField(
                    placeholder: '역 이름 (2자 이상)',
                    controller: _query,
                    onSubmitted: (_) => unawaited(_search()),
                    textInputAction: TextInputAction.search,
                  ),
                ),
                const SizedBox(width: AppSpace.sm),
                AppButton(
                  label: '검색',
                  variant: AppButtonVariant.tonal,
                  medium: true,
                  loading: _searching,
                  onPressed: () => unawaited(_search()),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpace.md),
          if (_searched && _results.isEmpty)
            Padding(
              padding: const EdgeInsets.all(AppSpace.lg),
              child: Text(
                '검색 결과가 없어요. 지하철역만 지원해요',
                style: AppTypo.bodySm.copyWith(
                  color: context.colors.inkSubtle,
                ),
              ),
            )
          else
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final result in _results)
                    AppListRow(
                      contents: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(result.displayName, style: AppTypo.body),
                          if (result.subtitle.isNotEmpty)
                            Text(
                              result.subtitle,
                              style: AppTypo.caption.copyWith(
                                color: context.colors.inkSubtle,
                              ),
                            ),
                        ],
                      ),
                      onPressed: () => Navigator.of(context).pop(result),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
