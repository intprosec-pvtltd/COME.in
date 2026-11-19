package com.intprosec.pg_resident

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelId = "staysync_alerts"
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(channelId, "Stay Sync alerts", NotificationManager.IMPORTANCE_HIGH)
            channel.description = "PG updates, complaints and resident activity"
            channel.enableVibration(true)
            (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).createNotificationChannel(channel)
        }
    }
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "staysync/notifications")
            .setMethodCallHandler { call, result ->
                if (call.method != "show") { result.notImplemented(); return@setMethodCallHandler }
                val title = call.argument<String>("title") ?: "Stay Sync Manage"
                val body = call.argument<String>("body") ?: "New PG update"
                val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                val intent = Intent(this, MainActivity::class.java)
                intent.flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
                val pending = PendingIntent.getActivity(this, 0, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
                val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    android.app.Notification.Builder(this, channelId)
                } else {
                    @Suppress("DEPRECATION")
                    android.app.Notification.Builder(this)
                }
                builder.setSmallIcon(R.mipmap.ic_launcher)
                    .setContentTitle(title.take(100))
                    .setContentText(body.take(150))
                    .setAutoCancel(true)
                    .setContentIntent(pending)
                    .setPriority(android.app.Notification.PRIORITY_HIGH)
                try {
                    manager.notify(System.currentTimeMillis().toInt(), builder.build())
                    result.success(true)
                } catch (_: SecurityException) { result.error("permission", "Notification permission needed", null) }
            }
    }
}
