import 'package:flutter/material.dart';

import '../../domain/commute_report.dart';
import '../../domain/models.dart';
import '../design/tokens.dart';

/// 통근 잔디 — 깃허브 컨트리뷰션 그래프식 주×요일 그리드 (메인 '통근 기록' 섹션).
/// 성공 중심 톤(§9): 탑승은 그린, 놓침은 중립 회색 — 붉은 비난색을 쓰지 않는다.
/// 폭에 맞춰 주 수를 정하고(최대 [_maxWeeks]), 계산은 domain [buildCommuteGrass]가 한다.
class CommuteGrass extends StatelessWidget {
  const CommuteGrass({super.key, required this.entries, required this.today});

  final List<FeedbackEntry> entries;
  final DateTime today;

  static const double _gap = 3;
  static const double _cellRadius = 3;
  static const double _minCell = 12;
  static const double _labelWidth = 22;
  static const int _maxWeeks = 16;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final gridWidth = constraints.maxWidth - _labelWidth - AppSpace.sm;
        final weeks = ((gridWidth + _gap) / (_minCell + _gap)).floor().clamp(
          4,
          _maxWeeks,
        );
        final cell = (gridWidth - (weeks - 1) * _gap) / weeks;
        final grid = buildCommuteGrass(entries, today, weeks: weeks);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: _labelWidth + AppSpace.sm),
              child: _monthLabels(context, grid, cell),
            ),
            const SizedBox(height: AppSpace.xs),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: _labelWidth, child: _weekdayLabels(cell)),
                const SizedBox(width: AppSpace.sm),
                _grid(context, grid, cell),
              ],
            ),
            const SizedBox(height: AppSpace.md),
            _legend(context),
          ],
        );
      },
    );
  }

  /// 월이 바뀌는 열 위에만 라벨 — 직전 라벨과 겹칠 만큼 가까우면 건너뛴다
  Widget _monthLabels(
    BuildContext context,
    List<List<GrassDay?>> grid,
    double cell,
  ) {
    final style = AppTypo.caption.copyWith(
      color: context.colors.inkSubtle,
      height: 1.0,
    );
    final labels = <Widget>[];
    var lastEnd = double.negativeInfinity;
    int? prevMonth;
    for (var week = 0; week < grid.length; week++) {
      // 열의 월요일은 항상 오늘 이전 — 첫 칸은 null이 아니다
      final month = grid[week][0]!.date.month;
      if (prevMonth != null && month != prevMonth) {
        final x = week * (cell + _gap);
        if (x - lastEnd >= AppSpace.sm) {
          labels.add(
            Positioned(left: x, top: 0, child: Text('$month월', style: style)),
          );
          lastEnd = x + cell * 2;
        }
      }
      prevMonth = month;
    }
    return SizedBox(
      height: AppSpace.lg,
      child: Stack(clipBehavior: Clip.none, children: labels),
    );
  }

  /// 월·수·금만 표기 — 깃허브 잔디와 같은 리듬, 칸 피치에 맞춰 정렬
  Widget _weekdayLabels(double cell) {
    const names = ['월', '', '수', '', '금', '', ''];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var day = 0; day < 7; day++)
          Container(
            height: cell,
            margin: EdgeInsets.only(top: day > 0 ? _gap : 0),
            alignment: Alignment.centerLeft,
            child: names[day].isEmpty
                ? null
                : Builder(
                    builder: (context) => Text(
                      names[day],
                      style: AppTypo.caption.copyWith(
                        color: context.colors.inkSubtle,
                        height: 1.0,
                      ),
                    ),
                  ),
          ),
      ],
    );
  }

  Widget _grid(BuildContext context, List<List<GrassDay?>> grid, double cell) {
    return Row(
      children: [
        for (var week = 0; week < grid.length; week++)
          Padding(
            padding: EdgeInsets.only(left: week > 0 ? _gap : 0),
            child: Column(
              children: [
                for (var day = 0; day < 7; day++)
                  Padding(
                    padding: EdgeInsets.only(top: day > 0 ? _gap : 0),
                    child: _cellBox(context, grid[week][day], cell),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _cellBox(BuildContext context, GrassDay? grassDay, double cell) {
    // 미래 칸은 빈 자리만 차지한다 — 아직 오지 않은 날을 회색으로 그리지 않는다
    if (grassDay == null) {
      return SizedBox(width: cell, height: cell);
    }
    final color = switch (grassDay.status) {
      GrassStatus.boarded => context.colors.primary,
      GrassStatus.missed => context.colors.inkFaint,
      null => context.colors.fill,
    };
    return Container(
      width: cell,
      height: cell,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(_cellRadius),
      ),
    );
  }

  Widget _legend(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        _legendItem(context, context.colors.primary, '탔어요'),
        const SizedBox(width: AppSpace.md),
        _legendItem(context, context.colors.inkFaint, '놓쳤어요'),
        const SizedBox(width: AppSpace.md),
        _legendItem(context, context.colors.fill, '기록 없음'),
      ],
    );
  }

  Widget _legendItem(BuildContext context, Color color, String label) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(_cellRadius),
          ),
        ),
        const SizedBox(width: AppSpace.xs),
        Text(
          label,
          style: AppTypo.caption.copyWith(color: context.colors.inkSubtle),
        ),
      ],
    );
  }
}
