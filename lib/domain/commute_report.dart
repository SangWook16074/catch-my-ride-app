/// 통근 리포트 — 탑승 피드백 이력 집계 (API.md §3-2, 명세서 §9 2026-09-16).
/// 순수 Dart — 서버는 이력만 주고 성공률·스트릭 계산은 전부 여기서 한다 (단위 테스트 대상).
///
/// 스트릭은 "기록된 피드백 기준 연속 탑승 성공 횟수"다 — 달력 연속이 아니라 기록 연속.
/// 피드백이 없는 날(주말·휴가·미응답)은 스트릭을 끊지 않는다: 안 탄 날을 실패로
/// 취급하면 기록이 비난이 된다 (§9 결정: 놓침 비난 톤 금지, 성공 중심).
library;

import 'models.dart';

class CommuteReport {
  const CommuteReport({
    required this.weekBoarded,
    required this.weekTotal,
    required this.recentBoarded,
    required this.recentTotal,
    required this.currentStreak,
    required this.bestStreak,
  });

  /// 이번 주(월~오늘, Asia/Seoul 로컬 날짜 기준) 탑승 성공/기록 수
  final int weekBoarded;
  final int weekTotal;

  /// 최근 30일 탑승 성공/기록 수
  final int recentBoarded;
  final int recentTotal;

  /// 최신 기록부터 이어지는 연속 탑승 성공 횟수 (최신 기록이 놓침이면 0)
  final int currentStreak;

  /// 역대 최장 연속 탑승 성공 횟수
  final int bestStreak;

  bool get isEmpty => recentTotal == 0 && currentStreak == 0 && bestStreak == 0;

  /// 최근 30일 성공률(%, 반올림) — 기록이 없으면 null (아는 척 금지)
  int? get recentRatePercent => recentTotal == 0
      ? null
      : ((recentBoarded / recentTotal) * 100).round();
}

/// [entries]는 서버 §3-2 응답(최신순)이지만 순서에 기대지 않고 내부에서 정렬한다.
/// [today]는 로컬 날짜 기준 오늘 (시각 부분은 무시).
CommuteReport buildCommuteReport(List<FeedbackEntry> entries, DateTime today) {
  final day = DateTime(today.year, today.month, today.day);
  final weekStart = day.subtract(Duration(days: day.weekday - 1)); // 월요일
  final recentStart = day.subtract(const Duration(days: 29));

  // 형식 오류·미래 날짜는 집계하지 않는다 — 이후 모든 계산은 이 목록(최신순) 기준
  final sorted = [
    for (final entry in entries)
      if (DateTime.tryParse(entry.date) case final DateTime date
          when !date.isAfter(day))
        entry,
  ]..sort((a, b) => b.date.compareTo(a.date));

  var weekBoarded = 0, weekTotal = 0, recentBoarded = 0, recentTotal = 0;
  for (final entry in sorted) {
    final date = DateTime.parse(entry.date);
    final boarded = entry.result == BoardingResult.boarded;
    if (!date.isBefore(recentStart)) {
      recentTotal += 1;
      if (boarded) {
        recentBoarded += 1;
      }
    }
    if (!date.isBefore(weekStart)) {
      weekTotal += 1;
      if (boarded) {
        weekBoarded += 1;
      }
    }
  }

  var currentStreak = 0;
  for (final entry in sorted) {
    if (entry.result != BoardingResult.boarded) {
      break;
    }
    currentStreak += 1;
  }

  var bestStreak = 0, run = 0;
  for (final entry in sorted) {
    if (entry.result == BoardingResult.boarded) {
      run += 1;
      if (run > bestStreak) {
        bestStreak = run;
      }
    } else {
      run = 0;
    }
  }

  return CommuteReport(
    weekBoarded: weekBoarded,
    weekTotal: weekTotal,
    recentBoarded: recentBoarded,
    recentTotal: recentTotal,
    currentStreak: currentStreak,
    bestStreak: bestStreak,
  );
}

/// "2026-09-16" → "9월 16일 (수)" — 리포트 이력 행 표시용. 파싱 불가면 원본 유지
String formatReportDate(String date) {
  final parsed = DateTime.tryParse(date);
  if (parsed == null) {
    return date;
  }
  const weekdays = ['월', '화', '수', '목', '금', '토', '일'];
  return '${parsed.month}월 ${parsed.day}일 (${weekdays[parsed.weekday - 1]})';
}
