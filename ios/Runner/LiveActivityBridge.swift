import Flutter
import Foundation

#if canImport(ActivityKit)
import ActivityKit
#endif

/// 하차 알림 트립 Live Activity 브리지 (CLAUDE.md 네이티브 브리지 목록).
/// 위젯은 표시만 한다 — 값은 Flutter의 트립 폴링(§9-3)이 update로 공급한다 (ADR-001).
/// iOS 16.1 미만·비활성 설정에서는 조용히 false — 앱 흐름을 막지 않는다.
final class LiveActivityBridge: NSObject {

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "catchmyride/live_activity",
      binaryMessenger: registrar.messenger()
    )
    channel.setMethodCallHandler(handle)
  }

  private static func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    #if canImport(ActivityKit)
    guard #available(iOS 16.1, *) else {
      result(false)
      return
    }
    let args = call.arguments as? [String: Any]
    switch call.method {
    case "start":
      start(journeyLabel: args?["journeyLabel"] as? String ?? "하차 알림", result: result)
    case "update":
      update(
        eventStop: args?["eventStop"] as? String ?? "",
        remainingStops: args?["remainingStops"] as? Int,
        phase: args?["phase"] as? String ?? "TRACKING",
        result: result
      )
    case "end":
      end(result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
    #else
    result(false)
    #endif
  }

  #if canImport(ActivityKit)
  @available(iOS 16.1, *)
  private static func start(journeyLabel: String, result: @escaping FlutterResult) {
    guard ActivityAuthorizationInfo().areActivitiesEnabled else {
      finish(result, false)
      return
    }
    Task {
      // 트립은 동시 1개(§9-2) — 남아 있던 활동은 정리하고 시작한다
      for activity in Activity<TripActivityAttributes>.activities {
        await activity.end(dismissalPolicy: .immediate)
      }
      let attributes = TripActivityAttributes(journeyLabel: journeyLabel)
      let state = TripActivityAttributes.ContentState(
        eventStop: "", remainingStops: nil, phase: "TRACKING"
      )
      do {
        _ = try Activity.request(attributes: attributes, contentState: state)
        finish(result, true)
      } catch {
        finish(result, false)
      }
    }
  }

  @available(iOS 16.1, *)
  private static func update(
    eventStop: String, remainingStops: Int?, phase: String, result: @escaping FlutterResult
  ) {
    Task {
      let state = TripActivityAttributes.ContentState(
        eventStop: eventStop, remainingStops: remainingStops, phase: phase
      )
      for activity in Activity<TripActivityAttributes>.activities {
        await activity.update(using: state)
      }
      finish(result, true)
    }
  }

  @available(iOS 16.1, *)
  private static func end(result: @escaping FlutterResult) {
    Task {
      for activity in Activity<TripActivityAttributes>.activities {
        await activity.end(dismissalPolicy: .immediate)
      }
      finish(result, true)
    }
  }
  #endif

  private static func finish(_ result: @escaping FlutterResult, _ value: Bool) {
    DispatchQueue.main.async { result(value) }
  }
}
