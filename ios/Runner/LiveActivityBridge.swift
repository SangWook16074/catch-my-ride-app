import Flutter
import Foundation

#if canImport(ActivityKit)
import ActivityKit
#endif

/// 하차 알림 트립 Live Activity 브리지 (CLAUDE.md 네이티브 브리지 목록).
/// 위젯은 표시만 한다 — 값은 Flutter의 트립 폴링(§9-3)이 update로 공급한다 (ADR-001).
/// iOS 16.1 미만·비활성 설정에서는 조용히 false — 앱 흐름을 막지 않는다.
///
/// v0.12(§9-5) — 서버가 APNs로 활동을 직접 갱신할 수 있도록 `pushType: .token`으로 시작하고,
/// `pushTokenUpdates`(회전 포함)를 구독해 받은 hex 토큰을 **이 채널로 역방향** 전달한다
/// (`pushTokenUpdated` 메서드 호출, Flutter 쪽은 `lib/platform/live_activity.dart`의
/// `pushTokenUpdates` 스트림이 받는다). Flutter가 `PUT /trips/{id}/surface-token`을 부른다.
final class LiveActivityBridge: NSObject {

  private static var channel: FlutterMethodChannel?

  /// 현재 활동의 push token 구독 — 활동을 새로 시작하면 이전 구독은 취소한다
  #if canImport(ActivityKit)
  @available(iOS 16.1, *)
  private static var tokenTask: Task<Void, Never>?
  #endif

  static func register(with registrar: FlutterPluginRegistrar) {
    let ch = FlutterMethodChannel(
      name: "catchmyride/live_activity",
      binaryMessenger: registrar.messenger()
    )
    channel = ch
    ch.setMethodCallHandler(handle)
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
        currentStop: args?["currentStop"] as? String,
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
    tokenTask?.cancel()
    tokenTask = nil
    Task {
      // 트립은 동시 1개(§9-2) — 남아 있던 활동은 정리하고 시작한다
      for activity in Activity<TripActivityAttributes>.activities {
        await activity.end(dismissalPolicy: .immediate)
      }
      let attributes = TripActivityAttributes(journeyLabel: journeyLabel)
      let state = TripActivityAttributes.ContentState(
        eventStop: "", remainingStops: nil, phase: "TRACKING", currentStop: nil
      )
      do {
        // v0.12(§9-5) — 서버 APNs 원격 갱신을 받으려면 토큰 기반으로 시작해야 한다.
        // 실패(권한·구성 문제)면 폴링만으로 동작(기존 동작으로 강등)
        let activity = try Activity.request(
          attributes: attributes,
          contentState: state,
          pushType: .token
        )
        finish(result, true)
        observePushToken(of: activity)
      } catch {
        finish(result, false)
      }
    }
  }

  /// 활동 push token(회전 포함)을 hex로 바꿔 `pushTokenUpdated`로 Flutter에 올린다.
  /// Android는 이 경로를 타지 않는다(§4-1 FCM 토큰을 그대로 쓴다)
  @available(iOS 16.1, *)
  private static func observePushToken(of activity: Activity<TripActivityAttributes>) {
    tokenTask = Task {
      for await tokenData in activity.pushTokenUpdates {
        let hex = tokenData.map { String(format: "%02x", $0) }.joined()
        await MainActor.run {
          channel?.invokeMethod("pushTokenUpdated", arguments: hex)
        }
      }
    }
  }

  @available(iOS 16.1, *)
  private static func update(
    eventStop: String, remainingStops: Int?, phase: String, currentStop: String?,
    result: @escaping FlutterResult
  ) {
    Task {
      let state = TripActivityAttributes.ContentState(
        eventStop: eventStop, remainingStops: remainingStops, phase: phase, currentStop: currentStop
      )
      for activity in Activity<TripActivityAttributes>.activities {
        await activity.update(using: state)
      }
      finish(result, true)
    }
  }

  @available(iOS 16.1, *)
  private static func end(result: @escaping FlutterResult) {
    tokenTask?.cancel()
    tokenTask = nil
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
