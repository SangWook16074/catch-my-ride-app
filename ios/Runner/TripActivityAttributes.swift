import Foundation

#if canImport(ActivityKit)
import ActivityKit

/// 하차 알림 트립 Live Activity 데이터 계약 (CLAUDE.md "위젯·Live Activity 데이터 계약").
/// Runner(시작·갱신)와 WidgetExtension(표시) 두 타깃에 함께 컴파일된다 —
/// 필드를 바꾸면 lib/platform/live_activity.dart·TripLiveActivity.swift를 같은 커밋에서 갱신할 것.
@available(iOS 16.1, *)
struct TripActivityAttributes: ActivityAttributes {
  public struct ContentState: Codable, Hashable {
    /// 이번 구간의 하차/환승 역명 (API.md §9-3 eventStop)
    var eventStop: String
    /// 남은 정거장 — null = 위치 확인 중 (숫자를 지어내지 않는다, NFR-03)
    var remainingStops: Int?
    /// TRACKING / ARRIVING / TRANSFER / DONE / LOST
    var phase: String
  }

  /// 여정 라벨 — 활동 시작 시 고정
  var journeyLabel: String
}
#endif
