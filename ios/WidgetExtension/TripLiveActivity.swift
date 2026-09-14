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
          Text(statusLine(context.state))
            .font(.subheadline)
        }
      } compactLeading: {
        Image(systemName: "tram.fill")
          .foregroundStyle(brandGreen)
      } compactTrailing: {
        Text(compactText(context.state))
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
  case "ARRIVING": return "다음 역에서 내리세요 — \(state.eventStop)"
  case "TRANSFER": return "\(state.eventStop) 도착 — 갈아탈 시간이에요"
  case "DONE": return "목적지에 도착했어요"
  case "LOST": return "추적할 수 없어요 — 안내방송을 확인하세요"
  default:
    return state.eventStop.isEmpty ? "위치 확인 중이에요" : "\(state.eventStop)에서 내려요"
  }
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

private func compactText(_ state: TripActivityAttributes.ContentState) -> String {
  switch state.phase {
  case "ARRIVING": return "곧"
  case "TRANSFER", "DONE": return "도착"
  case "LOST": return "—"
  default:
    guard let remaining = state.remainingStops else { return "…" }
    return "\(remaining)"
  }
}
