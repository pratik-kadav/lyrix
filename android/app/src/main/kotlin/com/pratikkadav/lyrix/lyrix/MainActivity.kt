package com.pratikkadav.lyrix.lyrix

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.app.KeyguardManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.widget.RemoteViews
import android.os.Bundle
import android.view.WindowManager
import androidx.core.app.NotificationCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val EVENT_CHANNEL = "lyrix/nowplaying"
    private val METHOD_CHANNEL = "lyrix/control"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
            )
        }
        // Keep screen alive when on Lock Screen (will be black AMOLED mostly)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // 1. The Listener (Receives song info from Spotify)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    LyrixNotificationService.setSinkAndSync(events)
                }

                override fun onCancel(arguments: Any?) {
                    LyrixNotificationService.setSinkAndSync(null)
                }
            }
        )

        // 2. The Emitter (Updates the Notification UI)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "updateNotification") {
                // Purged old persistent notification to prevent banner/system cluttering on OnePlus!
                result.success(null)
            } else if (call.method == "checkLockState") {
                val kgm = getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
                result.success(kgm.isKeyguardLocked)
            } else if (call.method == "dropLockScreen") {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
                    setShowWhenLocked(false)
                } else {
                    window.clearFlags(WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED)
                }
                result.success(true)
            } else if (call.method == "checkOverlayPermission") {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    result.success(Settings.canDrawOverlays(this))
                } else {
                    result.success(true)
                }
            } else if (call.method == "requestOverlayPermission") {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    if (!Settings.canDrawOverlays(this)) {
                        val intent = Intent(
                            Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                            Uri.parse("package:$packageName")
                        )
                        startActivityForResult(intent, 1234)
                        result.success(true)
                    } else {
                        result.success(true)
                    }
                } else {
                    result.success(true)
                }
            } else {
                result.notImplemented()
            }
        }
    }

    override fun onResume() {
        super.onResume()
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.cancel(998)
        nm.cancel(999)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
        } else {
            window.addFlags(WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED)
        }
    }
}