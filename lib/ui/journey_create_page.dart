import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/api.dart';
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

/// 여정 만들기 (FR-701/702) — 구간(탑승 역 → 노선 → 하차 역)을 이어 붙여 여정을 구성한다.
/// 역 검색은 §5-1 재사용(v1 지하철만), 방면은 서버가 역 순서로 유도(API.md §9 — 입력 없음).
class JourneyCreatePage extends StatefulWidget {
  const JourneyCreatePage({super.key});

  @override
  State<JourneyCreatePage> createState() => _JourneyCreatePageState();
}

class _JourneyCreatePageState extends State<JourneyCreatePage> {
  final TextEditingController _label = TextEditingController();
  final List<JourneyLeg> _legs = [];
  final Set<DayOfWeek> _repeatDays = {};
  String? _error;
  bool _saving = false;

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

  Future<void> _save() async {
    final request = JourneyRequest(
      label: _label.text,
      repeatDays: [
        for (final entry in journeyDayLabels)
          if (_repeatDays.contains(entry.day)) entry.day,
      ],
      legs: List.of(_legs),
    );
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
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(title: const Text('여정 만들기', style: AppTypo.heading)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: AppSpace.lg),
          children: [
            _sectionHeader('여정 이름'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.xl),
              child: AppTextField(
                placeholder: '예: 회사, 본가',
                controller: _label,
                maxLength: journeyLabelMaxLength,
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
                label: '저장',
                block: true,
                loading: _saving,
                onPressed: _saving ? null : () => unawaited(_save()),
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
