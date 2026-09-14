package dev.hansw.catchmyride

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * 하차 알림 트립 지속(ongoing) 알림 — iOS Live Activity의 안드로이드 대응 (FR-705).
 * 잠금화면·알림 셰이드에 "○○에서 내려요 · N정거장"을 고정 표시하고, 값은 Flutter의
 * 트립 폴링(§9-3)이 update로 공급한다 — 여기는 표시만 (ADR-001, CLAUDE.md 브리지 목록).
 *
 * 갱신은 무음(setOnlyAlertOnce) — 소리·진동이 나는 하차 임박 알림은 서버 FCM(§9-4)의 몫.
 * 알림 권한(Android 13+)이 없으면 조용히 표시되지 않을 뿐, 트립 흐름은 계속된다.
 * v1 한계는 iOS와 동일: 앱이 살아 있는 동안만 갱신된다.
 */
object TripNotificationBridge {

    private const val CHANNEL = "catchmyride/live_activity"
    private const val NOTIFICATION_CHANNEL_ID = "trip_tracking"
    private const val NOTIFICATION_ID = 9001

    private var journeyLabel: String = "하차 알림"
    private var tripId: String? = null

    fun register(context: Context, engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "start" -> {
                        journeyLabel = call.argument<String>("journeyLabel") ?: "하차 알림"
                        tripId = call.argument<String>("tripId")
                        show(context, title = "위치 확인 중이에요…", text = journeyLabel)
                        result.success(true)
                    }
                    "update" -> {
                        val eventStop = call.argument<String>("eventStop") ?: ""
                        val remaining = call.argument<Int>("remainingStops")
                        val phase = call.argument<String>("phase") ?: "TRACKING"
                        show(context, title = statusLine(phase, eventStop, remaining), text = journeyLabel)
                        result.success(true)
                    }
                    "end" -> {
                        manager(context).cancel(NOTIFICATION_ID)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                // 부가 기능 — 알림 실패가 트립 본편을 막지 않는다
                result.success(false)
            }
        }
    }

    private fun statusLine(phase: String, eventStop: String, remaining: Int?): String = when (phase) {
        "ARRIVING" -> "다음 역에서 내리세요 — $eventStop"
        "TRANSFER" -> "$eventStop 도착 — 갈아탈 시간이에요"
        "DONE" -> "목적지에 도착했어요"
        "LOST" -> "추적할 수 없어요 — 안내방송을 확인하세요"
        else -> when {
            eventStop.isEmpty() || remaining == null -> "위치 확인 중이에요…"
            else -> "${eventStop}에서 내려요 · ${remaining}정거장"
        }
    }

    private fun show(context: Context, title: String, text: String) {
        val manager = manager(context)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            // 무음 채널 — 갱신마다 울리면 소음 (하차 임박 경보는 FCM 채널의 몫)
            manager.createNotificationChannel(
                NotificationChannel(
                    NOTIFICATION_CHANNEL_ID,
                    "하차 알림 진행 상황",
                    NotificationManager.IMPORTANCE_LOW,
                ).apply { lockscreenVisibility = Notification.VISIBILITY_PUBLIC },
            )
        }
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, NOTIFICATION_CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context)
        }
        val notification = builder
            .setSmallIcon(context.applicationInfo.icon)
            .setContentTitle(title)
            .setContentText(text)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setContentIntent(tapIntent(context))
            .build()
        manager.notify(NOTIFICATION_ID, notification)
    }

    /** 탭 → 딥링크로 트립 진행 화면 (catchmyride://trip?tripId=…, HomePage 딥링크 핸들러 계약) */
    private fun tapIntent(context: Context): PendingIntent {
        val uri = tripId?.let { Uri.parse("catchmyride://trip?tripId=$it") }
        val intent = Intent(Intent.ACTION_VIEW).apply {
            if (uri != null) data = uri
            setPackage(context.packageName)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        return PendingIntent.getActivity(
            context, 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun manager(context: Context): NotificationManager =
        context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
}
