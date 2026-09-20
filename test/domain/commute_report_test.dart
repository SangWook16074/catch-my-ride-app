import 'package:catch_my_ride/domain/commute_report.dart';
import 'package:catch_my_ride/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

FeedbackEntry boarded(String date) =>
    FeedbackEntry(date: date, result: BoardingResult.boarded);

FeedbackEntry missed(String date) =>
    FeedbackEntry(date: date, result: BoardingResult.missed);

void main() {
  // 2026-09-16은 수요일 — 이번 주는 09-14(월)부터
  final today = DateTime(2026, 9, 16);

  group('buildCommuteReport', () {
    test('빈 이력이면 전부 0이고 isEmpty', () {
      final report = buildCommuteReport(const [], today);
      expect(report.isEmpty, isTrue);
      expect(report.weekTotal, 0);
      expect(report.recentRatePercent, isNull);
    });

    test('이번 주(월~오늘)와 최근 30일을 따로 집계한다', () {
      final report = buildCommuteReport([
        boarded('2026-09-16'), // 수 — 이번 주
        missed('2026-09-14'), // 월 — 이번 주
        boarded('2026-09-11'), // 지난주 금 — 30일 안
        boarded('2026-08-01'), // 30일 밖
      ], today);
      expect(report.weekBoarded, 1);
      expect(report.weekTotal, 2);
      expect(report.recentBoarded, 2);
      expect(report.recentTotal, 3);
      expect(report.recentRatePercent, 67);
    });

    test('스트릭은 기록 연속 — 피드백 없는 날(주말)은 끊지 않는다', () {
      final report = buildCommuteReport([
        boarded('2026-09-16'),
        boarded('2026-09-15'),
        // 09-12·13 주말 기록 없음 — 끊기지 않아야 한다
        boarded('2026-09-11'),
        missed('2026-09-10'),
        boarded('2026-09-09'),
      ], today);
      expect(report.currentStreak, 3);
      expect(report.bestStreak, 3);
    });

    test('최신 기록이 놓침이면 현재 스트릭 0, 최고 기록은 유지', () {
      final report = buildCommuteReport([
        missed('2026-09-16'),
        boarded('2026-09-15'),
        boarded('2026-09-14'),
        boarded('2026-09-11'),
        missed('2026-09-10'),
      ], today);
      expect(report.currentStreak, 0);
      expect(report.bestStreak, 3);
    });

    test('입력 순서에 기대지 않는다 (오름차순으로 줘도 동일)', () {
      final entries = [
        boarded('2026-09-14'),
        missed('2026-09-15'),
        boarded('2026-09-16'),
      ];
      final report = buildCommuteReport(entries, today);
      expect(report.currentStreak, 1);
      expect(report.weekBoarded, 2);
      expect(report.weekTotal, 3);
    });

    test('미래 날짜·형식 오류는 집계하지 않는다', () {
      final report = buildCommuteReport([
        boarded('2026-09-17'), // 미래
        FeedbackEntry(date: 'not-a-date', result: BoardingResult.boarded),
        boarded('2026-09-16'),
      ], today);
      expect(report.weekTotal, 1);
    });
  });

  group('buildCommuteGrass', () {
    test('주×7 그리드 — 마지막 열이 이번 주, 오늘 이후 칸은 null', () {
      final grid = buildCommuteGrass(const [], today, weeks: 4);
      expect(grid.length, 4);
      expect(grid.every((week) => week.length == 7), isTrue);
      // 이번 주(09-14 월~): 수요일까지 칸, 목~일은 아직 오지 않은 날
      final thisWeek = grid.last;
      expect(thisWeek[0]!.date, DateTime(2026, 9, 14));
      expect(thisWeek[2]!.date, DateTime(2026, 9, 16));
      expect(thisWeek[3], isNull);
      expect(thisWeek[6], isNull);
      // 지난 주들은 전부 채워지고, 첫 열이 가장 오래된 주다
      expect(grid[2].every((day) => day != null), isTrue);
      expect(grid[2][0]!.date, DateTime(2026, 9, 7));
      expect(grid.first[0]!.date, DateTime(2026, 8, 24));
    });

    test('기록이 해당 날짜 칸에 매핑된다 — 기록 없는 날은 status null', () {
      final grid = buildCommuteGrass([
        boarded('2026-09-16'),
        missed('2026-09-14'),
        boarded('2026-09-11'), // 지난주 금
      ], today, weeks: 2);
      final thisWeek = grid.last;
      expect(thisWeek[0]!.status, GrassStatus.missed);
      expect(thisWeek[1]!.status, isNull);
      expect(thisWeek[2]!.status, GrassStatus.boarded);
      expect(grid.first[4]!.status, GrassStatus.boarded);
    });

    test('형식 오류·미래 날짜 기록은 무시한다', () {
      final grid = buildCommuteGrass([
        FeedbackEntry(date: 'not-a-date', result: BoardingResult.boarded),
        boarded('2026-09-17'), // 미래
      ], today, weeks: 1);
      expect(grid.last.every((day) => day == null || day.status == null),
          isTrue);
    });
  });
}
