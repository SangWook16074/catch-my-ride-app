package dev.hansw.catchmyride

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // 하차 알림 트립 지속 알림 브리지 (CLAUDE.md 네이티브 브리지 목록)
        TripNotificationBridge.register(applicationContext, flutterEngine)
    }
}
