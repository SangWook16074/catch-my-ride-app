package dev.hansw.catchmyride

import com.google.firebase.messaging.RemoteMessage
import io.flutter.plugins.firebase.messaging.FlutterFirebaseMessagingService

/**
 * 진행 표면 원격 갱신(§9-5 v0.12) — 서버가 데이터 전용 고우선 FCM
 * `{ "type": "TRIP_SURFACE", "tripId", "phase", "legIndex", "remainingStops", "currentStop",
 * "eventStop" }`을 보내면 [TripNotificationBridge]로 같은 지속 알림을 **Flutter 엔진을
 * 깨우지 않고** 그 자리에서 갱신한다 (CLAUDE.md 네이티브 브리지 목록, FR-705).
 *
 * 왜 `FlutterFirebaseMessagingService`를 상속하는가 (2026-10-01, firebase_messaging 플러그인
 * 소스 검토): 플러그인은 포그라운드 스트림(`FirebaseMessaging.onMessage`)·백그라운드 처리
 * (`onBackgroundMessage`)를 이 서비스의 `onMessageReceived`가 아니라 **별도로 등록한
 * `FlutterFirebaseMessagingReceiver`(c2dm 브로드캐스트 수신자)**로 처리한다 — 플러그인 자신의
 * `onMessageReceived`도 "리시버에서 이미 처리하니 여기서는 중복 처리하지 않는다"고 되어 있다.
 * 즉 **`FirebaseMessagingService`를 독립적으로 새로 선언하면 안 된다** — 앱마다
 * `FirebaseMessagingService`는 하나만 바인딩되므로 플러그인 것과 충돌해 토큰 갱신(`onNewToken`)
 * ·다른 알림(§9-4 하차·환승)이 플러그인 쪽으로 더는 가지 않을 수 있다. 대신 플러그인 서비스를
 * **상속**해 매니페스트에서 `tools:node="replace"`로 교체하고, 내 타입이 아닌 메시지는
 * `super.onMessageReceived`로 넘겨 기존 처리(사실상 no-op이지만 플러그인 쪽 로직을 그대로 둔다)를
 * 보존한다. `onNewToken`은 오버라이드하지 않으므로 플러그인 기본 동작(§4-1 토큰 등록) 그대로다.
 *
 * 한계(정직하게 밝힘): 플러그인의 `FlutterFirebaseMessagingReceiver`는 이 서비스와 **별개
 * 컴포넌트**라 내가 메시지를 "가로채도" 그 리시버는 같은 메시지를 독립적으로 또 받는다. 이
 * 앱은 현재 `FirebaseMessaging.onBackgroundMessage` 콜백을 등록하지 않았으므로(기존부터 그렇다 —
 * 이 변경으로 새로 생긴 문제가 아니다) 백그라운드 전용 Flutter 엔진이 일시적으로 뜨더라도 할 일이
 * 없어 바로 끝난다. 포그라운드(이 서비스의 `onMessageReceived`가 사실상 유일하게 즉시 불리는
 * 경로)에서는 완전히 네이티브로만 처리된다. 완벽히 "절대 안 깨운다"를 보장하려면 플러그인
 * 리시버까지 손대야 하는데, 그건 이 저장소가 건드리지 않는 서드파티 플러그인 내부라 위험이 더
 * 크다고 판단했다 — 오너 검토 필요.
 */
class TripSurfaceFcmService : FlutterFirebaseMessagingService() {

    override fun onMessageReceived(remoteMessage: RemoteMessage) {
        val data = remoteMessage.data
        if (data["type"] == "TRIP_SURFACE") {
            TripNotificationBridge.updateFromPush(
                context = applicationContext,
                tripId = data["tripId"],
                phase = data["phase"] ?: "TRACKING",
                eventStop = data["eventStop"] ?: "",
                remainingStops = data["remainingStops"]?.toIntOrNull(),
                currentStop = data["currentStop"],
            )
            return
        }
        // TRIP_SURFACE가 아니면(§9-4 하차·환승 알림 등) 플러그인 기본 처리로 넘긴다
        super.onMessageReceived(remoteMessage)
    }
}
