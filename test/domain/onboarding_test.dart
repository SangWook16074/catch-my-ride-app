import 'package:catch_my_ride/domain/models.dart';
import 'package:catch_my_ride/domain/onboarding.dart';
import 'package:flutter_test/flutter_test.dart';

// 미니앱 src/domain/__tests__/onboarding.test.ts 이식 — 검증 규칙이 서버·미니앱과 같아야 한다.

const _home = GeoPoint(latitude: 37.52, longitude: 126.92);

const _stop = CommuteStop(
  type: StopType.seoulBus,
  stopId: '19284',
  displayName: '여의도환승센터',
  routes: ['720'],
);

OnboardingDraft _completeDraft() => OnboardingDraft.empty().copyWith(
  home: _home,
  stops: const [_stop],
  walkMinutes: 8,
  notificationMode: NotificationMode.fixed,
  fixedDepartureTime: '07:40',
  bufferMinutes: 2,
  activeDays: const [DayOfWeek.mon, DayOfWeek.tue],
  label: '출근',
);

void main() {
  group('isValidTime', () {
    test('유효한 HH:mm을 허용한다', () {
      expect(isValidTime('00:00'), isTrue);
      expect(isValidTime('07:40'), isTrue);
      expect(isValidTime('23:59'), isTrue);
    });

    test('범위 밖·형식 오류를 거부한다', () {
      expect(isValidTime('24:00'), isFalse);
      expect(isValidTime('07:60'), isFalse);
      expect(isValidTime('7:40'), isFalse);
      expect(isValidTime('0740'), isFalse);
      expect(isValidTime(''), isFalse);
    });
  });

  group('canProceed', () {
    test('home — 집 위치가 있어야 진행', () {
      expect(canProceed(OnboardingStep.home, OnboardingDraft.empty()), isFalse);
      expect(
        canProceed(
          OnboardingStep.home,
          OnboardingDraft.empty().copyWith(home: _home),
        ),
        isTrue,
      );
    });

    test('stops — 정류장 1개 이상 + 정류장마다 노선 1개 이상', () {
      expect(
        canProceed(OnboardingStep.stops, OnboardingDraft.empty()),
        isFalse,
      );
      final routeless = OnboardingDraft.empty().copyWith(
        stops: const [
          CommuteStop(
            type: StopType.subway,
            stopId: '여의도',
            displayName: '여의도역',
            routes: [],
          ),
        ],
      );
      expect(canProceed(OnboardingStep.stops, routeless), isFalse);
      expect(
        canProceed(
          OnboardingStep.stops,
          OnboardingDraft.empty().copyWith(stops: const [_stop]),
        ),
        isTrue,
      );
    });

    test('walk — 1분 이상', () {
      expect(canProceed(OnboardingStep.walk, OnboardingDraft.empty()), isFalse);
      expect(
        canProceed(
          OnboardingStep.walk,
          OnboardingDraft.empty().copyWith(walkMinutes: 0),
        ),
        isFalse,
      );
      expect(
        canProceed(
          OnboardingStep.walk,
          OnboardingDraft.empty().copyWith(walkMinutes: 1),
        ),
        isTrue,
      );
    });

    test('mode — 모드 미선택은 진행 불가 (기본값 강제 금지, FR-302)', () {
      expect(canProceed(OnboardingStep.mode, OnboardingDraft.empty()), isFalse);
    });

    test('mode FIXED — 유효한 출발 시각 필요', () {
      final base = OnboardingDraft.empty().copyWith(
        notificationMode: NotificationMode.fixed,
      );
      expect(canProceed(OnboardingStep.mode, base), isFalse);
      expect(
        canProceed(
          OnboardingStep.mode,
          base.copyWith(fixedDepartureTime: '25:00'),
        ),
        isFalse,
      );
      expect(
        canProceed(
          OnboardingStep.mode,
          base.copyWith(fixedDepartureTime: '07:40'),
        ),
        isTrue,
      );
    });

    test('mode RECOMMENDED — start < end인 유효한 시간대 필요', () {
      final base = OnboardingDraft.empty().copyWith(
        notificationMode: NotificationMode.recommended,
      );
      expect(canProceed(OnboardingStep.mode, base), isFalse);
      expect(
        canProceed(
          OnboardingStep.mode,
          base.copyWith(
            commuteWindow: const CommuteWindow(start: '08:30', end: '07:30'),
          ),
        ),
        isFalse,
      );
      expect(
        canProceed(
          OnboardingStep.mode,
          base.copyWith(
            commuteWindow: const CommuteWindow(start: '07:30', end: '07:30'),
          ),
        ),
        isFalse,
      );
      expect(
        canProceed(
          OnboardingStep.mode,
          base.copyWith(
            commuteWindow: const CommuteWindow(start: '07:30', end: '08:30'),
          ),
        ),
        isTrue,
      );
    });

    test('buffer — 0분 이상 (0 허용)', () {
      expect(
        canProceed(OnboardingStep.buffer, OnboardingDraft.empty()),
        isFalse,
      );
      expect(
        canProceed(
          OnboardingStep.buffer,
          OnboardingDraft.empty().copyWith(bufferMinutes: -1),
        ),
        isFalse,
      );
      expect(
        canProceed(
          OnboardingStep.buffer,
          OnboardingDraft.empty().copyWith(bufferMinutes: 0),
        ),
        isTrue,
      );
    });

    test('days — 1개 이상', () {
      expect(canProceed(OnboardingStep.days, OnboardingDraft.empty()), isFalse);
      expect(
        canProceed(
          OnboardingStep.days,
          OnboardingDraft.empty().copyWith(activeDays: const [DayOfWeek.mon]),
        ),
        isTrue,
      );
    });

    test('label — trim 후 1~16자', () {
      expect(
        canProceed(OnboardingStep.label, OnboardingDraft.empty()),
        isFalse,
      );
      expect(
        canProceed(
          OnboardingStep.label,
          OnboardingDraft.empty().copyWith(label: '   '),
        ),
        isFalse,
      );
      expect(
        canProceed(
          OnboardingStep.label,
          OnboardingDraft.empty().copyWith(label: 'a' * 17),
        ),
        isFalse,
      );
      expect(
        canProceed(
          OnboardingStep.label,
          OnboardingDraft.empty().copyWith(label: 'a' * 16),
        ),
        isTrue,
      );
      expect(
        canProceed(
          OnboardingStep.label,
          OnboardingDraft.empty().copyWith(label: ' 출근 '),
        ),
        isTrue,
      );
    });
  });

  group('recommendedModeIsEstimated', () {
    test('지하철 + 도보 10분 이상이면 추정 안내', () {
      final draft = OnboardingDraft.empty().copyWith(
        walkMinutes: 10,
        stops: const [
          CommuteStop(
            type: StopType.subway,
            stopId: '여의도',
            displayName: '여의도역',
            routes: ['5호선'],
          ),
        ],
      );
      expect(recommendedModeIsEstimated(draft), isTrue);
    });

    test('도보 10분 미만이거나 버스만이면 해당 없음', () {
      final shortWalk = OnboardingDraft.empty().copyWith(
        walkMinutes: 9,
        stops: const [
          CommuteStop(
            type: StopType.subway,
            stopId: '여의도',
            displayName: '여의도역',
            routes: ['5호선'],
          ),
        ],
      );
      expect(recommendedModeIsEstimated(shortWalk), isFalse);
      final busOnly = OnboardingDraft.empty().copyWith(
        walkMinutes: 15,
        stops: const [_stop],
      );
      expect(recommendedModeIsEstimated(busOnly), isFalse);
    });
  });

  group('buildSetting', () {
    test('미완성 draft는 단계 이름과 함께 던진다 (label 단계는 제외)', () {
      expect(
        () => buildSetting(OnboardingDraft.empty()),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(contains('home'), isNot(contains('label'))),
          ),
        ),
      );
    });

    test('FIXED 모드는 commuteWindow를 null로 정리한다', () {
      final draft = _completeDraft().copyWith(
        commuteWindow: const CommuteWindow(start: '07:00', end: '08:00'),
      );
      final setting = buildSetting(draft);
      expect(setting.notificationMode, NotificationMode.fixed);
      expect(setting.fixedDepartureTime, '07:40');
      expect(setting.commuteWindow, isNull);
    });

    test('RECOMMENDED 모드는 fixedDepartureTime을 null로 정리한다', () {
      final draft = _completeDraft().copyWith(
        notificationMode: NotificationMode.recommended,
        commuteWindow: const CommuteWindow(start: '07:30', end: '08:30'),
      );
      final setting = buildSetting(draft);
      expect(setting.fixedDepartureTime, isNull);
      expect(
        setting.commuteWindow,
        const CommuteWindow(start: '07:30', end: '08:30'),
      );
    });
  });

  group('settingToDraft', () {
    test('설정을 draft로 역변환하고 라벨은 비운다 (경로 값이므로)', () {
      final setting = buildSetting(_completeDraft());
      final draft = settingToDraft(setting);
      expect(draft.home, _home);
      expect(draft.stops, setting.stops);
      expect(draft.walkMinutes, 8);
      expect(draft.label, '');
      // 깊은 복사 — draft 쪽 노선 수정이 원본 설정에 새지 않는다
      draft.stops.first.routes.add('261');
      expect(setting.stops.first.routes, ['720']);
    });
  });

  group('changedFields', () {
    test('바뀐 필드만 나열한다', () {
      final prev = buildSetting(_completeDraft());
      final next = buildSetting(
        _completeDraft().copyWith(walkMinutes: 12, bufferMinutes: 5),
      );
      expect(changedFields(prev, next), ['walkMinutes', 'bufferMinutes']);
      expect(changedFields(prev, buildSetting(_completeDraft())), isEmpty);
    });
  });

  group('nextRouteLabel', () {
    CommuteRoute route(String label) => CommuteRoute(
      id: label,
      label: label,
      enabled: true,
      setting: buildSetting(_completeDraft()),
    );

    test('미사용 프리셋 우선, 다 쓰면 "경로 N"', () {
      expect(nextRouteLabel([]), '출근');
      expect(nextRouteLabel([route('출근')]), '퇴근');
      expect(nextRouteLabel([route('출근'), route('퇴근')]), '경로 3');
      expect(
        nextRouteLabel([route('출근'), route('퇴근'), route('경로 3')]),
        '경로 4',
      );
    });
  });
}
