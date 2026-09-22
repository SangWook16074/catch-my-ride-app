import ActivityKit
import SwiftUI
import WidgetKit

/// 하차 알림 트립 Live Activity — 잠금화면·다이나믹 아일랜드 카운트다운 (FR-705).
/// 표시 전용 — 값은 Runner(Flutter 트립 폴링)가 ActivityKit update로 공급한다 (ADR-001).
@main
struct WidgetExtensionBundle: WidgetBundle {
  var body: some Widget {
    TripLiveActivityWidget()
  }
}

struct TripLiveActivityWidget: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: TripActivityAttributes.self) { context in
      LockScreenView(context: context)
        .padding(16)
        .activityBackgroundTint(Color.black.opacity(0.8))
        .activitySystemActionForegroundColor(.white)
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          Text(context.attributes.journeyLabel)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        DynamicIslandExpandedRegion(.trailing) {
          Text(remainingText(context.state))
            .font(.headline)
            .foregroundStyle(brandGreen)
        }
        DynamicIslandExpandedRegion(.bottom) {
          VStack(alignment: .leading, spacing: 2) {
            Text(statusLine(context.state))
              .font(.subheadline)
            if let current = currentLine(context.state) {
              Text(current)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          }
        }
      } compactLeading: {
        Image(systemName: "tram.fill")
          .foregroundStyle(brandGreen)
      } compactTrailing: {
        Text(compactText(context.state))
          .font(.caption2)
          .lineLimit(1)
          .foregroundStyle(brandGreen)
      } minimal: {
        Image(systemName: "tram.fill")
          .foregroundStyle(brandGreen)
      }
    }
  }
}

private struct LockScreenView: View {
  let context: ActivityViewContext<TripActivityAttributes>

  var body: some View {
    HStack(alignment: .center) {
      VStack(alignment: .leading, spacing: 4) {
        Text(context.attributes.journeyLabel)
          .font(.caption)
          .foregroundStyle(.secondary)
        Text(statusLine(context.state))
          .font(.headline)
          .foregroundStyle(.white)
        // 열차 현재 위치 — 서버 목격 값만 (오너 요청 2026-09-21: 잠금화면에서 지금 어디쯤인지)
        if let current = currentLine(context.state) {
          Text(current)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
      Spacer()
      Text(remainingText(context.state))
        .font(.title2.bold())
        .foregroundStyle(context.state.phase == "ARRIVING" ? coral : brandGreen)
    }
  }
}

// 브랜드 그린 #42D674 × 코랄 #F2655A — lib/ui/design/tokens.dart와 동일 팔레트
private let brandGreen = Color(red: 0x42 / 255.0, green: 0xD6 / 255.0, blue: 0x74 / 255.0)
private let coral = Color(red: 0xF2 / 255.0, green: 0x65 / 255.0, blue: 0x5A / 255.0)

private func statusLine(_ state: TripActivityAttributes.ContentState) -> String {
  switch state.phase {
  case "ARRIVING": return "다음 역 \(state.eventStop)에서 내리세요"
  case "TRANSFER": return "\(state.eventStop) 도착, 갈아탈 시간이에요"
  case "DONE": return "목적지에 도착했어요"
  case "LOST": return "추적할 수 없어요. 안내방송을 확인하세요"
  default:
    return state.eventStop.isEmpty ? "위치 확인 중이에요" : "\(state.eventStop)에서 내려요"
  }
}

/// "현재 ○○ 부근" — 이동 중(추적·도착 직전)이고 위치를 알 때만, 종착·끊김 상태엔 생략 (NFR-03)
private func currentLine(_ state: TripActivityAttributes.ContentState) -> String? {
  guard state.phase == "TRACKING" || state.phase == "ARRIVING" else { return nil }
  guard let current = state.currentStop, !current.isEmpty else { return nil }
  return "현재 \(current) 부근"
}

private func remainingText(_ state: TripActivityAttributes.ContentState) -> String {
  switch state.phase {
  case "ARRIVING": return "다음 역"
  case "TRANSFER", "DONE": return "도착"
  case "LOST": return "—"
  default:
    guard let remaining = state.remainingStops else { return "…" }
    return "\(remaining)정거장"
  }
}

/// 축소 다이나믹 아일랜드는 폭이 좁다 — 남은 정거장이 우선, 아직 모르면 현재 위치 역명,
/// 둘 다 모를 때만 "…" (오너 피드백 2026-09-22: 축소 상태에 아이콘과 점만 보인다)
private func compactText(_ state: TripActivityAttributes.ContentState) -> String {
  switch state.phase {
  case "ARRIVING": return "곧"
  case "TRANSFER", "DONE": return "도착"
  case "LOST": return "—"
  default:
    if let remaining = state.remainingStops { return "\(remaining)" }
    if let current = state.currentStop, !current.isEmpty { return current }
    return "…"
  }
}
