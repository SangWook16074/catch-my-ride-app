/// 온보딩 위저드의 단계 진행 조건과 draft → CommuteSetting 변환.
/// 원칙(FR-302/105): 버퍼·알림 모드는 시스템이 기본값을 강제하지 않는다 — 유저가 고르기 전까지 null.
/// 미니앱 src/domain/onboarding.ts 이식 — 규칙 변경 시 양쪽을 함께 본다.
library;

import 'models.dart';

enum OnboardingStep { home, stops, walk, mode, buffer, days, label }

const List<OnboardingStep> onboardingSteps = OnboardingStep.values;

/// 경로 이름 최대 길이 — 서버 계약(API.md §1-2 label 1~16자)과 동일
const int routeLabelMaxLength = 16;

class OnboardingDraft {
  const OnboardingDraft({
    required this.home,
    required this.stops,
    required this.walkMinutes,
    required this.notificationMode,
    required this.fixedDepartureTime,
    required this.commuteWindow,
    required this.bufferMinutes,
    required this.activeDays,
    required this.label,
  });

  factory OnboardingDraft.empty() => const OnboardingDraft(
    home: null,
    stops: [],
    walkMinutes: null,
    notificationMode: null,
    fixedDepartureTime: null,
    commuteWindow: null,
    bufferMinutes: null,
    activeDays: [],
    label: '',
  );

  final GeoPoint? home;
  final List<CommuteStop> stops;
  final int? walkMinutes;
  final NotificationMode? notificationMode;
  final String? fixedDepartureTime;
  final CommuteWindow? commuteWindow;
  final int? bufferMinutes;
  final List<DayOfWeek> activeDays;

  /// 경로 이름(CommuteRoute.label) — CommuteSetting 밖의 값이라 buildSetting에는 안 들어간다
  final String label;

  /// null을 "지우기"로 써야 하는 필드(walkMinutes 등)가 있어 sentinel 방식으로 patch한다.
  OnboardingDraft copyWith({
    Object? home = _unset,
    List<CommuteStop>? stops,
    Object? walkMinutes = _unset,
    Object? notificationMode = _unset,
    Object? fixedDepartureTime = _unset,
    Object? commuteWindow = _unset,
    Object? bufferMinutes = _unset,
    List<DayOfWeek>? activeDays,
    String? label,
  }) => OnboardingDraft(
    home: home == _unset ? this.home : home as GeoPoint?,
    stops: stops ?? this.stops,
    walkMinutes: walkMinutes == _unset ? this.walkMinutes : walkMinutes as int?,
    notificationMode: notificationMode == _unset
        ? this.notificationMode
        : notificationMode as NotificationMode?,
    fixedDepartureTime: fixedDepartureTime == _unset
        ? this.fixedDepartureTime
        : fixedDepartureTime as String?,
    commuteWindow: commuteWindow == _unset
        ? this.commuteWindow
        : commuteWindow as CommuteWindow?,
    bufferMinutes: bufferMinutes == _unset
        ? this.bufferMinutes
        : bufferMinutes as int?,
    activeDays: activeDays ?? this.activeDays,
    label: label ?? this.label,
  );

  static const Object _unset = Object();
}

/// 지하철 실시간 도착 피드의 대략적 범위(분) — 근접 열차만 제공된다 (서버 S-4 배차 외삽의 전제와 동일)
const int subwayRealtimeHorizonMinutes = 10;

/// 추천 모드가 실시간 정보만으로 판단할 수 없는 조합 — 지하철 정류장 + 도보가 피드 범위 이상.
/// 서버가 배차 간격으로 출발 시각을 추정하게 되므로(정확도 하락) 모드 선택 단계에서 미리 안내한다.
bool recommendedModeIsEstimated(OnboardingDraft draft) {
  final walk = draft.walkMinutes;
  return walk != null &&
      walk >= subwayRealtimeHorizonMinutes &&
      draft.stops.any((stop) => stop.type == StopType.subway);
}

final RegExp _timePattern = RegExp(r'^([01]\d|2[0-3]):[0-5]\d$');

bool isValidTime(String time) => _timePattern.hasMatch(time);

bool _isValidWindow(CommuteWindow? window) =>
    window != null &&
    isValidTime(window.start) &&
    isValidTime(window.end) &&
    window.start.compareTo(window.end) < 0;

bool canProceed(OnboardingStep step, OnboardingDraft draft) {
  switch (step) {
    case OnboardingStep.home:
      return draft.home != null;
    case OnboardingStep.stops:
      return draft.stops.isNotEmpty &&
          draft.stops.every((stop) => stop.routes.isNotEmpty);
    case OnboardingStep.walk:
      final walk = draft.walkMinutes;
      return walk != null && walk >= 1;
    case OnboardingStep.mode:
      if (draft.notificationMode == NotificationMode.fixed) {
        final time = draft.fixedDepartureTime;
        return time != null && isValidTime(time);
      }
      if (draft.notificationMode == NotificationMode.recommended) {
        return _isValidWindow(draft.commuteWindow);
      }
      return false;
    case OnboardingStep.buffer:
      final buffer = draft.bufferMinutes;
      return buffer != null && buffer >= 0;
    case OnboardingStep.days:
      return draft.activeDays.isNotEmpty;
    case OnboardingStep.label:
      final label = draft.label.trim();
      return label.isNotEmpty && label.length <= routeLabelMaxLength;
  }
}

/// 재설정 프리필 — 서버 CommuteSetting을 위저드 draft로 역변환한다 (buildSetting의 역방향, 깊은 복사)
OnboardingDraft settingToDraft(CommuteSetting setting) => OnboardingDraft(
  home: setting.home,
  stops: setting.stops.map((stop) => stop.copyWith()).toList(),
  walkMinutes: setting.walkMinutes,
  notificationMode: setting.notificationMode,
  fixedDepartureTime: setting.fixedDepartureTime,
  commuteWindow: setting.commuteWindow,
  bufferMinutes: setting.bufferMinutes,
  activeDays: List.of(setting.activeDays),
  // 라벨은 CommuteRoute의 값 — 페이지가 route.label로 덮어쓴다
  label: '',
);

/// 재설정에서 실제로 바뀐 필드 목록 — changed_fields 이벤트 파라미터용
List<String> changedFields(CommuteSetting prev, CommuteSetting next) {
  final changed = <String>[];
  if (prev.home != next.home) {
    changed.add('home');
  }
  if (!listEquals(prev.stops, next.stops)) {
    changed.add('stops');
  }
  if (prev.walkMinutes != next.walkMinutes) {
    changed.add('walkMinutes');
  }
  if (prev.notificationMode != next.notificationMode) {
    changed.add('notificationMode');
  }
  if (prev.fixedDepartureTime != next.fixedDepartureTime) {
    changed.add('fixedDepartureTime');
  }
  if (prev.commuteWindow != next.commuteWindow) {
    changed.add('commuteWindow');
  }
  if (prev.bufferMinutes != next.bufferMinutes) {
    changed.add('bufferMinutes');
  }
  if (!listEquals(prev.activeDays, next.activeDays)) {
    changed.add('activeDays');
  }
  return changed;
}

/// 모든 설정 단계 조건을 만족한 draft를 API.md CommuteSetting으로 변환한다.
/// label 단계는 제외 — 라벨은 CommuteRoute의 값이라 이 변환의 산출물이 아니다 (위저드 CTA가 따로 막는다).
CommuteSetting buildSetting(OnboardingDraft draft) {
  final incomplete = onboardingSteps
      .where(
        (step) => step != OnboardingStep.label && !canProceed(step, draft),
      )
      .map((step) => step.name)
      .toList();
  if (incomplete.isNotEmpty) {
    throw StateError('미완성 단계: ${incomplete.join(', ')}');
  }
  final mode = draft.notificationMode!;
  return CommuteSetting(
    home: draft.home!,
    stops: draft.stops,
    walkMinutes: draft.walkMinutes!,
    notificationMode: mode,
    fixedDepartureTime: mode == NotificationMode.fixed
        ? draft.fixedDepartureTime
        : null,
    commuteWindow: mode == NotificationMode.recommended
        ? draft.commuteWindow
        : null,
    bufferMinutes: draft.bufferMinutes!,
    activeDays: draft.activeDays,
  );
}

/// 새 경로의 기본 라벨 제안 — 미사용 프리셋 우선, 다 쓰면 "경로 N". 유저가 위저드 라벨 단계에서 자유롭게 바꾼다
String nextRouteLabel(List<CommuteRoute> existing) {
  final used = existing.map((r) => r.label).toSet();
  for (final preset in const ['출근', '퇴근']) {
    if (!used.contains(preset)) {
      return preset;
    }
  }
  for (var n = existing.length + 1; ; n++) {
    final candidate = '경로 $n';
    if (!used.contains(candidate)) {
      return candidate;
    }
  }
}
