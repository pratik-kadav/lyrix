package com.pratikkadav.lyrix.lyrix

import android.content.ComponentName
import android.content.Context
import android.media.MediaMetadata
import android.media.session.MediaController
import android.media.session.MediaSessionManager
import android.media.session.PlaybackState
import android.os.Handler
import android.os.Looper
import android.content.BroadcastReceiver
import android.content.Intent
import android.content.IntentFilter
import android.app.NotificationManager
import android.app.PendingIntent
import androidx.core.app.NotificationCompat
import android.provider.Settings
import android.os.Build
import android.os.SystemClock
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import io.flutter.plugin.common.EventChannel
import androidx.palette.graphics.Palette
import android.graphics.Bitmap

class LyrixNotificationService : NotificationListenerService() {

    companion object {
        var eventSink: EventChannel.EventSink? = null
        var currentInstance: LyrixNotificationService? = null

        fun setSinkAndSync(sink: EventChannel.EventSink?) {
            eventSink = sink
            if (sink != null) {
                currentInstance?.forceStatusUpdate()
            }
        }
    }

    fun forceStatusUpdate() {
        val controller = activeController ?: return
        sendUpdate(controller, controller.playbackState)
    }

    // The controller we're currently watching
    private var activeController: MediaController? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    // --------------------------------------------------------
    // MediaController.Callback — fires ONLY when something changes
    // in the active music app. No more polling every notification.
    // --------------------------------------------------------
    private val mediaCallback = object : MediaController.Callback() {

        override fun onPlaybackStateChanged(state: PlaybackState?) {
            val controller = activeController ?: return
            sendUpdate(controller, state)
        }

        override fun onMetadataChanged(metadata: MediaMetadata?) {
            val controller = activeController ?: return
            sendUpdate(controller, controller.playbackState)
        }

        override fun onSessionDestroyed() {
            // Music app closed or session ended
            activeController?.unregisterCallback(this)
            activeController = null
            mainHandler.post {
                eventSink?.success("false|||||||") // Signal Flutter to clear state
            }
        }
    }

    // --------------------------------------------------------
    // Called whenever ANY notification is posted/removed.
    // We use this only to find and ATTACH to the music session,
    // not to read data from it directly.
    // --------------------------------------------------------
    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        attachToMusicSession()
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification?) {
        attachToMusicSession()
    }

    override fun onListenerConnected() {
        super.onListenerConnected()
        currentInstance = this
        attachToMusicSession()
    }

    // --------------------------------------------------------
    // Finds the active music session and registers our callback.
    // If we're already watching the right controller, does nothing.
    // --------------------------------------------------------
    private fun attachToMusicSession() {
        try {
            val manager = getSystemService(Context.MEDIA_SESSION_SERVICE) as MediaSessionManager
            val componentName = ComponentName(this, LyrixNotificationService::class.java)
            val controllers = manager.getActiveSessions(componentName)

            val musicController = controllers.firstOrNull { isMusicApp(it.packageName) }

            if (musicController == null) {
                // No music app active
                if (activeController != null) {
                    activeController?.unregisterCallback(mediaCallback)
                    activeController = null
                }
                return
            }

            // Already watching this exact session — do nothing
            if (activeController?.sessionToken == musicController.sessionToken) return

            // New session found — unregister old, register new
            activeController?.unregisterCallback(mediaCallback)
            activeController = musicController
            activeController?.registerCallback(mediaCallback)

            // Immediately send current state so Flutter doesn't wait
            sendUpdate(musicController, musicController.playbackState)

        } catch (e: Exception) {
            // Permission not granted yet — user hasn't enabled notification access
        }
    }

    // --------------------------------------------------------
    // Sends data to Flutter via EventChannel.
    // Format: "isPlaying|||title|||artist|||positionMs|||durationMs"
    // positionMs = real elapsed position in the song (fixes sync drift!)
    // --------------------------------------------------------

    private fun sendUpdate(controller: MediaController, state: PlaybackState?) {
        val metadata = controller.metadata ?: return

        val isPlaying = state?.state == PlaybackState.STATE_PLAYING

        val reportedPosition = state?.position ?: 0L
        val positionMs = if (isPlaying && state != null) {
            val lastUpdateTime = state.lastPositionUpdateTime
            val elapsedSinceUpdate = SystemClock.elapsedRealtime() - lastUpdateTime
            reportedPosition + elapsedSinceUpdate.coerceAtLeast(0L)
        } else {
            reportedPosition
        }

        val durationMs = metadata.getLong(MediaMetadata.METADATA_KEY_DURATION)
        val title = metadata.getString(MediaMetadata.METADATA_KEY_TITLE) ?: return
        val artist = metadata.getString(MediaMetadata.METADATA_KEY_ARTIST) ?: "Unknown"
        val album = metadata.getString(MediaMetadata.METADATA_KEY_ALBUM) ?: ""

        // --- NATIVE COLOR EXTRACTION ---
        val bitmap = metadata.getBitmap(MediaMetadata.METADATA_KEY_ALBUM_ART)
            ?: metadata.getBitmap(MediaMetadata.METADATA_KEY_ART)

        var colorHex = "#FFFFFF" // Fallback to pure white

        if (bitmap != null) {
            try {
                // Generate palette (synchronously is fine here because bitmaps from MediaSession are usually tiny thumbnails)
                val palette = Palette.from(bitmap).generate()

                // Grab the most vibrant color, fallback to the dominant color
                val swatch = palette.vibrantSwatch ?: palette.dominantSwatch
                if (swatch != null) {
                    // Convert integer color to clean Hex String (e.g., #FF7B4F)
                    colorHex = String.format("#%06X", 0xFFFFFF and swatch.rgb)
                }
            } catch (e: Exception) {
                // If extraction fails, it defaults to white
            }
        }

        // New Payload includes the color string at the end!
        val data = "$isPlaying|||$title|||$artist|||$positionMs|||$durationMs|||$album|||$colorHex"
        _lastKnownIsPlaying = isPlaying

        mainHandler.post {
            eventSink?.success(data)
        }
    }
    private fun isMusicApp(pkg: String): Boolean {
        val p = pkg.lowercase()
        return p.contains("spotify") ||
               p.contains("music") ||
               p.contains("soundcloud") ||
               p.contains("musicolet") ||
               p.contains("poweramp") ||
               p.contains("jiosaavn") ||
               p.contains("saavn") ||
               p.contains("youtube") ||
               p.contains("wynk") ||
               p.contains("gaana") ||
               p.contains("amazon") ||
               p.contains("apple") ||
               p.contains("tidal") ||
               p.contains("pandora") ||
               p.contains("player")
    }

    private var _lastKnownIsPlaying = false

    private val screenReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == Intent.ACTION_SCREEN_OFF && _lastKnownIsPlaying) {
                mainHandler.postDelayed({
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && Settings.canDrawOverlays(this@LyrixNotificationService)) {
                        launchLockscreen()
                    } else if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
                        launchLockscreen()
                    }
                }, 500)
            }
        }
    }

    private fun launchLockscreen() {
        val launchIntent = Intent(this, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }
        
        val options = android.app.ActivityOptions.makeCustomAnimation(this, android.R.anim.fade_in, android.R.anim.fade_out).toBundle()

        val pendingIntent = PendingIntent.getActivity(
            this, 202, launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            options
        )

        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        
        val title = activeController?.metadata?.getString(MediaMetadata.METADATA_KEY_TITLE) ?: "Lyrix"
        val artist = activeController?.metadata?.getString(MediaMetadata.METADATA_KEY_ARTIST) ?: ""
        val content = if (artist.isNotEmpty()) "$title  |  $artist" else title

        val builder = NotificationCompat.Builder(this, "lyrix_custom_channel")
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setColor(0xFF7B4FD8.toInt())
            .setContentTitle("Tap to sync")
            .setContentText(content)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setFullScreenIntent(pendingIntent, true)
            .setContentIntent(pendingIntent)
            .setAutoCancel(true)

        notificationManager.notify(998, builder.build())
    }

    override fun onCreate() {
        super.onCreate()
        val filter = IntentFilter(Intent.ACTION_SCREEN_OFF)
        registerReceiver(screenReceiver, filter)
    }

    override fun onDestroy() {
        currentInstance = null
        unregisterReceiver(screenReceiver)
        super.onDestroy()
    }
}