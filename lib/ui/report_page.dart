import 'dart:async';

import 'package:flutter/material.dart';

import '../data/api.dart';
import '../domain/commute_report.dart';
import '../domain/models.dart';
import 'design/components/button.dart';
import 'design/components/card.dart';
import 'design/components/list_row.dart';
import 'design/tokens.dart';

enum _ReportPhase { loading, unavailable, failed, ready }

/// 나의 통근 리포트 — 피드백 이력 집계 화면 (명세서 §9 2026-09-16, API.md §3-2).
/// 리텐션 장치: 쌓인 기록이 곧 이탈 비용. 성공 중심 톤 — 놓침을 비난하는 표현 금지.
class ReportPage extends StatefulWidget {
  const ReportPage({super.key});

  @override
  State<ReportPage> createState() => _ReportPageState();
}

class _ReportPageState extends State<ReportPage> {
  _ReportPhase _phase = _ReportPhase.loading;
  List<FeedbackEntry> _entries = [];

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final entries = await api.getFeedbackHistory();
      if (!mounted) {
        return;
      }
      setState(() {
        _entries = entries;
        _phase = _ReportPhase.ready;
      });
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      // §3-2 미배포 서버는 404 — "준비 중"으로 강등 (하차 알림과 같은 태도)
      setState(
        () => _phase = error.status == 404
            ? _ReportPhase.unavailable
            : _ReportPhase.failed,
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _phase = _ReportPhase.failed);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(title: const Text('나의 통근', style: AppTypo.heading)),
      body: SafeArea(child: _body()),
    );
  }

  Widget _body() {
    switch (_phase) {
      case _ReportPhase.loading:
        return const Center(child: CircularProgressIndicator.adaptive());
      case _ReportPhase.unavailable:
        return _centerMessage(
          title: '통근 기록을 준비하고 있어요',
          subtitle: '서버 업데이트 후 이용할 수 있어요. 조금만 기다려주세요',
        );
      case _ReportPhase.failed:
        return _centerMessage(
          title: '기록을 불러오지 못했어요',
          subtitle: '네트워크를 확인하고 다시 시도해주세요',
          button: AppButton(
            label: '다시 시도',
            variant: AppButtonVariant.tonal,
            medium: true,
            onPressed: () => unawaited(_load()),
          ),
        );
      case _ReportPhase.ready:
        final report = buildCommuteReport(_entries, DateTime.now());
        if (_entries.isEmpty) {
          return _centerMessage(
            title: '아직 기록이 없어요',
            subtitle: '아침에 "탔어요/놓쳤어요"를 누르면\n여기에 통근 기록이 쌓여요',
          );
        }
        return _report(report);
    }
  }

  Widget _centerMessage({
    required String title,
    required String subtitle,
    Widget? button,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: AppTypo.heading, textAlign: TextAlign.center),
            const SizedBox(height: AppSpace.xs),
            Text(
              subtitle,
              style: AppTypo.caption.copyWith(color: context.colors.inkMuted),
              textAlign: TextAlign.center,
            ),
            if (button != null) ...[
              const SizedBox(height: AppSpace.md),
              button,
            ],
          ],
        ),
      ),
    );
  }

  Widget _report(CommuteReport report) {
    return RefreshIndicator.adaptive(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(top: AppSpace.md, bottom: AppSpace.xl),
        children: [
          AppCard(
            tone: AppCardTone.brand,
            child: Column(
              children: [
                Row(
                  children: [
                    _stat('이번 주 탑승', '${report.weekBoarded}/${report.weekTotal}회'),
                    _stat('연속 성공', '${report.currentStreak}회'),
                  ],
                ),
                const SizedBox(height: AppSpace.lg),
                Row(
                  children: [
                    _stat(
                      '최근 30일 성공률',
                      report.recentRatePercent == null
                          ? '—'
                          : '${report.recentRatePercent}%',
                    ),
                    _stat('최고 연속 기록', '${report.bestStreak}회'),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpace.xl,
              AppSpace.md,
              AppSpace.xl,
              AppSpace.sm,
            ),
            child: Text(
              '최근 기록',
              style: AppTypo.caption.copyWith(color: context.colors.inkSubtle),
            ),
          ),
          AppCard(
            child: Column(
              children: [
                for (final entry in _entries) _entryRow(entry),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _stat(String label, String value) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppTypo.caption.copyWith(color: context.colors.inkMuted),
          ),
          const SizedBox(height: AppSpace.xs),
          Text(
            value,
            style: AppTypo.title.copyWith(color: context.colors.primaryStrong),
          ),
        ],
      ),
    );
  }

  Widget _entryRow(FeedbackEntry entry) {
    final boarded = entry.result == BoardingResult.boarded;
    return AppListRow(
      horizontalPadding: 0,
      contents: Text(formatReportDate(entry.date), style: AppTypo.body),
      right: Text(
        boarded ? '탔어요' : '놓쳤어요',
        style: AppTypo.bodySm.copyWith(
          color: boarded
              ? context.colors.primaryStrong
              : context.colors.inkSubtle,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
