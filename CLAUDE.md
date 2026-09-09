# 놓치지마 스토어판 — 하네스 엔지니어링 문서

> 이 문서는 `catch_my_ride/`(Flutter 스토어 앱)에서 작업하는 모든 에이전트·개발자의 실행 규칙이다.
> **아키텍처 "왜"는 [docs/ADR-001-플랫폼-아키텍처.md](docs/ADR-001-플랫폼-아키텍처.md)가 원본**이고,
> 이 문서는 그 결정을 "어떻게"로 번역한다. 둘이 충돌하면 ADR이 이기고, 이 문서를 고친다.

## 프로젝트 정의

- 앱인토스 미니앱(catch-my-ride-appintoss)으로 검증된 **놓치지마**의 iOS·Android 스토어 출시판.
- 기능 명세는 [../PRD.md](../PRD.md)·[../docs/요구사항명세서.md](../docs/요구사항명세서.md),
  서버 계약은 [../API.md](../API.md) (기존 catch-my-ride-server 재사용, Base URL 동일).
- 미니앱 코드는 참고용 선행 구현이다 — 화면 흐름·문구·도메인 규칙을 이식하되, React 코드를
  기계적으로 번역하지 말 것.

## 아키텍처 경계 (ADR-001의 집행 규칙)

### 하드 룰 — 위반 시 ADR 개정 없이는 머지 금지

1. **앱 내부 화면은 Flutter로만 만든다.** "iOS답게"가 이유라면 답은 적응형 위젯이지
   Platform View가 아니다.
2. **Platform View 허용 목록**: 지도 · 웹뷰 · 광고 (네이티브 SDK가 뷰를 그리는 임베드).
   목록 밖 사용은 ADR-001 "재검토 트리거" 절차를 먼저 밟는다.
3. **네이티브 코드(Swift/Kotlin)가 사는 곳은 시스템 서비스뿐**:
   - `ios/WidgetExtension/` — WidgetKit 위젯 + Live Activity (SwiftUI)
   - `android/` Glance 위젯
   - 푸시·백그라운드·App Group 브리지
   네이티브 쪽에 비즈니스 로직(출발 시각 계산 등)을 두지 않는다 — 위젯은 Flutter/서버가
   계산해 공유 저장소에 넣어준 값을 "표시"만 한다.
4. **MethodChannel/Pigeon 브리지는 서비스 경계에만** 만든다. 새 브리지를 추가할 때는
   이 문서의 "네이티브 브리지 목록" 절에 등록한다.

### 레이어 규칙

```
lib/
  ui/        # 화면·위젯 — 적응형 규칙 적용, domain만 안다
  domain/    # 순수 Dart 비즈니스 로직 — Flutter import 금지, 전부 단위 테스트 대상
  data/      # API 클라이언트(../API.md 계약)·로컬 저장소 — domain 모델로 변환해서 넘긴다
  platform/  # 네이티브 브리지 래퍼 (home_widget, 알림 등) — 유일하게 채널을 만지는 곳
```

- 의존 방향: `ui → domain ← data`, `platform`은 ui/data에서만 호출.
- 미니앱에서 검증된 도메인 규칙(발송 2회, 버퍼, 요일·공휴일, 라벨 1~16자 중복 불가 등)은
  `domain/`에 이식하고 반드시 테스트를 같이 옮긴다.

### 디자인 시스템 (TDS를 쓰지 않는다)

- 스토어판은 미니앱의 TDS(토스 디자인 시스템)와 **별개의 자체 디자인 시스템**을 쓴다
  (오너 결정 2026-09-09, 같은 날 2차 개정). 방향: **딥그린 × 코랄** — 그린이 주인공,
  코랄이 따뜻한 강조(서두름·포인트). 세이지 파스텔안("뿌옇다")·주황 경고안을 거쳐 확정.
- **라이트/다크 필수**: 팔레트는 `AppColors.light`/`AppColors.dark` 두 인스턴스
  (ThemeExtension). 위젯에서는 반드시 `context.colors.*`로 접근 — AppColors를 static으로
  참조하는 코드는 다크 모드가 깨지므로 금지. 타이포(AppTypo)는 색을 갖지 않는다 —
  기본 글자색은 테마 DefaultTextStyle(ink), 다른 색은 copyWith로.
- 원본은 `lib/ui/design/` — `tokens.dart`(컬러·타이포·간격·라운드)와
  `components/`(버튼·칩·카드·시트·입력·리스트 행 프리미티브).
- 화면·컴포넌트는 **토큰만 쓴다**: `Color(0x...)`/`fontSize` 하드코딩 금지, 컬러 교체는
  `tokens.dart` 한 파일로 끝나야 한다. 타이포는 역할 이름(title/body/caption) — TDS의
  t3/t5 번호 체계를 들여오지 않는다.
- 미니앱에서 이식하는 화면은 **배치·플로우는 동일하게, 스타일은 이 시스템으로** 옮긴다.

### 적응형 UI 규칙 (플랫폼다움은 여기서 만든다)

- 스위치·피커·다이얼로그·로딩은 `.adaptive` 생성자 우선. 없으면 `Theme.platform` 분기.
- 페이지 전환: iOS 스와이프 백 유지 (`CupertinoPageTransitionsBuilder` 등 플랫폼별 빌더).
- 햅틱: 주요 확정 액션(경로 저장, 알림 동의)에 `HapticFeedback` — iOS 체감 요소.
- 인앱 글라스 표현은 블러+반투명 근사치까지만 — 진짜 리퀴드 글라스는 위젯/시스템 표면 담당
  (ADR-001 트레이드오프).

## 네이티브 브리지 목록

새 채널·브리지를 만들면 여기 한 줄 추가한다. 목록에 없는 채널이 코드에 있으면 그게 버그다.

| 브리지 | 방향 | 용도 |
|---|---|---|
| geolocator 플러그인 (`lib/platform/location.dart`) | Flutter → OS | 온보딩 집 위치 1회 등록 (FR-101). 상시 추적 금지(NFR-05) |
| shared_preferences 플러그인 (`lib/data/suggestion_store.dart`) | Flutter → OS | 버퍼 추천 처리 시각 등 경량 로컬 저장 |

## 위젯·Live Activity 데이터 계약

- 공유 저장소: iOS App Group `group.dev.hansw.catchmyride` (가칭) / Android SharedPreferences.
- Flutter가 쓰고 위젯이 읽는 값: 다음 도착 노선·분, 권장 출발 시각, 경로 라벨. 위젯 쪽 계산 금지.
- 필드를 바꾸면 이 절과 Extension 코드를 같은 커밋에서 갱신한다.

## 명령어

```bash
flutter analyze              # 린트 — 경고 0 유지
flutter test                 # 단위·위젯 테스트
flutter run                  # 개발 실행
flutter build ipa / appbundle  # 배포 빌드
```

## 작업 규칙

- **테스트**: `domain/`은 로직 추가와 같은 커밋에 테스트 필수. UI는 흐름이 굳은 화면부터
  위젯 테스트. 머지 전 `flutter analyze` + `flutter test` 통과.
- **커밋**: 한국어 주제 커밋 (기존 저장소 스타일 — "온보딩: …", "위젯: …").
  근거가 되는 문서 절(§)을 메시지에 인용.
- **의사결정**: 아키텍처 경계를 바꾸는 결정은 코드보다 ADR 개정이 먼저다. 새 ADR은
  `docs/ADR-NNN-*.md`로 추가하고 이 문서의 해당 절을 갱신한다.
- **문서 동기화**: 서버 계약이 바뀌면 [../API.md](../API.md)가 원본 — 이 저장소에 사본을
  만들지 않는다.

## 에이전트 지침

- 막히면 이 문서 → ADR → PRD 순으로 근거를 찾고, 그래도 결정이 필요하면 코드를 먼저 쓰지
  말고 오너에게 옵션을 제시한다.
- 미니앱·서버 저장소의 실측 기록(푸시 동의는 발송 코드 단위, mTLS 스펙 등)은 스토어판에도
  유효한 사실이다 — 재검증 전에 뒤집지 말 것.
- 이 문서가 실제 코드와 어긋난 걸 발견하면 코드를 문서에 맞추는 게 기본, 문서가 낡았으면
  같은 커밋에서 문서를 고친다.
