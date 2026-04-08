package com.example.memory_task_v2

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import androidx.core.app.NotificationCompat

/**
 * AlarmForegroundService — started by [AlarmReceiver] when the alarm fires.
 *
 * Runs as a foreground service so Android cannot kill it while the alarm is
 * ringing.  It plays the system alarm ringtone and shows a persistent
 * notification using a full-screen intent (alarm mode) or a plain
 * high-priority banner (notification-only mode) based on [EXTRA_USE_ALARM_SCREEN].
 *
 * The service auto-stops after [MAX_RING_MS] ms (default 60 s) or when
 * [ACTION_STOP] is broadcast to it.
 */
class AlarmForegroundService : Service() {

    companion object {
        const val ACTION_STOP          = "com.example.memory_task_v2.ALARM_STOP"
        const val EXTRA_TITLE          = "alarm_title"
        const val EXTRA_BODY           = "alarm_body"
        const val EXTRA_PAYLOAD        = "alarm_payload"
        const val EXTRA_ID             = "alarm_notif_id"
        const val EXTRA_USE_ALARM_SCREEN = "use_alarm_screen"
        // When true, skip native audio/vibration because the Flutter alarm
        // package is already handling playback on its own service.
        const val EXTRA_SKIP_AUDIO     = "skip_audio"

        private const val CHANNEL_ID  = "eldercare_alarms"
        private const val NOTIF_ID    = 9999          // foreground service notif
        private const val MAX_RING_MS = 60_000L       // auto-stop after 60 s

        /** Convenience factory — use from BroadcastReceiver. */
        fun buildIntent(
            context:        Context,
            title:          String,
            body:           String,
            payload:        String,
            notifId:        Int,
            useAlarmScreen: Boolean = true,
            skipAudio:      Boolean = false,
        ): Intent = Intent(context, AlarmForegroundService::class.java).apply {
            putExtra(EXTRA_TITLE,            title)
            putExtra(EXTRA_BODY,             body)
            putExtra(EXTRA_PAYLOAD,          payload)
            putExtra(EXTRA_ID,               notifId)
            putExtra(EXTRA_USE_ALARM_SCREEN, useAlarmScreen)
            putExtra(EXTRA_SKIP_AUDIO,       skipAudio)
        }
    }

    private var player:        MediaPlayer?        = null
    private var vibrator:      Vibrator?           = null
    private var wakeLock:      PowerManager.WakeLock? = null
    private var audioFocusReq: AudioFocusRequest?  = null
    private var stopRunnable:  Runnable?           = null
    private val handler = android.os.Handler(android.os.Looper.getMainLooper())

    // ── Lifecycle ─────────────────────────────────────────────────────────────

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            // The user tapped the native "Dismiss" action directly in the
            // notification shade (Flutter alarm screen may never have been shown).
            val dismissedTitle = intent.getStringExtra(EXTRA_TITLE) ?: ""
            // Notify Flutter so it can:
            //   1. Clear _pendingShowKey (prevent showPendingOrMissedAlarm from
            //      pushing the alarm screen behind the upcoming ScheduleScreen)
            //   2. Set _pendingAlarmHandledThisSession = true
            //   3. Call _openScheduleCallback (push ScheduleScreen)
            sendFlutterMethod("onNativeDismiss", null)
            // For the notification-only path (no Flutter activity open),
            // show the View Schedule notification after the method call.
            showViewScheduleNotification(dismissedTitle)
            stopSelf()
            return START_NOT_STICKY
        }

        val title          = intent?.getStringExtra(EXTRA_TITLE)                       ?: "Task Reminder"
        val body           = intent?.getStringExtra(EXTRA_BODY)                        ?: ""
        val payload        = intent?.getStringExtra(EXTRA_PAYLOAD)                     ?: ""
        val notifId        = intent?.getIntExtra(EXTRA_ID, 0)                          ?: 0
        val useAlarmScreen = intent?.getBooleanExtra(EXTRA_USE_ALARM_SCREEN, true)     ?: true
        // skipAudio=true when the Flutter alarm package is already playing audio.
        val skipAudio      = intent?.getBooleanExtra(EXTRA_SKIP_AUDIO, false)          ?: false

        ensureChannel()

        // Acquire a partial + screen-on wake lock.
        if (useAlarmScreen) acquireWakeLock()

        val notification = buildNotification(title, body, payload, notifId, useAlarmScreen)
        startForeground(NOTIF_ID, notification)

        if (useAlarmScreen) {
            // Immediately notify Flutter so it can push the alarm screen.
            // This is critical when app is in the foreground — Android suppresses
            // the fullScreenIntent in that case, so startActivity() from AlarmReceiver
            // may also be rate-limited.  Sending via MethodChannel is always reliable.
            sendFlutterMethod("onAlarmPayload", payload)

            if (!skipAudio) {
                startRingtone()
                startVibration()
            }
        }

        // Auto-stop after MAX_RING_MS
        stopRunnable = Runnable { stopSelf() }
        handler.postDelayed(stopRunnable!!, MAX_RING_MS)

        return START_STICKY
    }

    /**
     * Sends a MethodChannel call to the running Flutter engine, if one exists.
     * Safe to call even if Flutter is not yet started — the engine reference
     * is obtained from the Application's retained FlutterEngine pool.
     */
    private fun sendFlutterMethod(method: String, argument: String?) {
        try {
            // Use the FlutterEngineCache if your app registers engines there,
            // otherwise fall back to the default Flutter activity binding.
            val appContext = applicationContext
            // Attempt to find a live engine via reflection on FlutterActivity.
            val engineProvider = appContext
                .getSystemService("io.flutter.embedding.engine.FlutterEngineProvider")
            if (engineProvider == null) {
                // Fallback: send a broadcast that MainActivity relays to Flutter.
                val broadcast = android.content.Intent("com.example.memory_task_v2.FLUTTER_METHOD").apply {
                    setPackage(appContext.packageName)
                    putExtra("method", method)
                    putExtra("argument", argument)
                }
                appContext.sendBroadcast(broadcast)
            }
        } catch (e: Exception) {
            android.util.Log.w("AlarmFgSvc", "sendFlutterMethod($method) failed: $e")
        }
    }

    override fun onDestroy() {
        stopRunnable?.let { handler.removeCallbacks(it) }
        releasePlayer()
        releaseVibrator()
        releaseAudioFocus()
        releaseWakeLock()

        // Notify MainActivity to drop lockscreen privileges since alarm is over
        sendBroadcast(Intent("com.example.memory_task_v2.CLEAR_LOCK_FLAGS").apply {
            setPackage(packageName)
        })

        super.onDestroy()
    }

    // ── Notification ──────────────────────────────────────────────────────────

    private fun buildNotification(
        title:          String,
        body:           String,
        payload:        String,
        notifId:        Int,
        useAlarmScreen: Boolean,
    ): Notification {
        val launchIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP
            if (useAlarmScreen) {
                // Carry the payload so MainActivity can open the alarm screen.
                putExtra("alarm_payload", payload)
            }
        }
        val piFlags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        val contentPi    = PendingIntent.getActivity(this, notifId,         launchIntent, piFlags)
        val fullscreenPi = PendingIntent.getActivity(this, notifId + 70000, launchIntent, piFlags)

        // Dismiss action — stops ringing without launching the app.
        // Pass title so onStartCommand can include it in the View Schedule notification.
        val stopIntent = Intent(this, AlarmForegroundService::class.java).apply {
            action = ACTION_STOP
            putExtra(EXTRA_TITLE, title)
        }
        val stopPi = PendingIntent.getService(
            this, notifId + 80000, stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle("\u23f0 $title")
            .setContentText(body.ifEmpty { "Time for your task!" })
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setContentIntent(contentPi)
            .setOngoing(true)
            .setAutoCancel(false)

        if (useAlarmScreen) {
            builder
                .setFullScreenIntent(fullscreenPi, true)
                .addAction(android.R.drawable.ic_delete, "Dismiss", stopPi)
        }

        return builder.build()
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Schedule Alarms",
                // MAX is required for the full-screen intent to reliably bypass
                // the notification drawer on all Android ROMs (Samsung, MIUI, etc.).
                NotificationManager.IMPORTANCE_MAX
            ).apply {
                description          = "Full-screen alarm when task time is near"
                enableVibration(false)     // we handle vibration ourselves
                setSound(null, null)       // we handle audio ourselves
                lockscreenVisibility = NotificationCompat.VISIBILITY_PUBLIC
            }
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.createNotificationChannel(channel)
        }
    }

    // ── Wake lock ─────────────────────────────────────────────────────────────

    private fun acquireWakeLock() {
        try {
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            @Suppress("DEPRECATION")
            wakeLock = pm.newWakeLock(
                // Use FULL_WAKE_LOCK to ensure the screen turns on brightly
                PowerManager.FULL_WAKE_LOCK or
                PowerManager.ACQUIRE_CAUSES_WAKEUP or
                PowerManager.ON_AFTER_RELEASE,
                "eldercare:AlarmWakeLock"
            )
            wakeLock?.acquire(MAX_RING_MS + 5_000L)
        } catch (e: Exception) {
            android.util.Log.e("AlarmService", "WakeLock acquire failed: $e")
        }
    }

    private fun releaseWakeLock() {
        try {
            if (wakeLock?.isHeld == true) wakeLock?.release()
        } catch (_: Exception) {}
        wakeLock = null
    }

    // ── Audio ─────────────────────────────────────────────────────────────────

    private fun startRingtone() {
        try {
            requestAudioFocus()
            val uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
            player = MediaPlayer().apply {
                setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ALARM)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build()
                )
                setDataSource(applicationContext, uri)
                isLooping = true
                prepare()
                start()
            }
        } catch (e: Exception) {
            android.util.Log.e("AlarmService", "Could not start ringtone: $e")
        }
    }

    private fun releasePlayer() {
        try { player?.stop() } catch (_: Exception) {}
        try { player?.release() } catch (_: Exception) {}
        player = null
    }

    private fun requestAudioFocus() {
        val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            audioFocusReq = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT)
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ALARM)
                        .build()
                )
                .build()
            am.requestAudioFocus(audioFocusReq!!)
        } else {
            @Suppress("DEPRECATION")
            am.requestAudioFocus(null, AudioManager.STREAM_ALARM, AudioManager.AUDIOFOCUS_GAIN_TRANSIENT)
        }
    }

    private fun releaseAudioFocus() {
        val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && audioFocusReq != null) {
            am.abandonAudioFocusRequest(audioFocusReq!!)
        } else {
            @Suppress("DEPRECATION")
            am.abandonAudioFocus(null)
        }
    }

    // ── Vibration ─────────────────────────────────────────────────────────────

    private fun startVibration() {
        val pattern = longArrayOf(0, 500, 200, 500, 200, 500, 1000)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            vibrator = (getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager).defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            vibrator = getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            vibrator?.vibrate(VibrationEffect.createWaveform(pattern, 0))
        } else {
            @Suppress("DEPRECATION")
            vibrator?.vibrate(pattern, 0)
        }
    }

    private fun releaseVibrator() {
        try { vibrator?.cancel() } catch (_: Exception) {}
        vibrator = null
    }

    // ── Post-dismiss "View Schedule" notification ──────────────────────────────
    // Shows a notification directing the user to their schedule after the alarm
    // is dismissed via the native action button (without opening the Flutter UI).
    private fun showViewScheduleNotification(taskTitle: String) {
        try {
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                val ch = android.app.NotificationChannel(
                    "eldercare_schedule_reminders",
                    "Schedule Reminders",
                    NotificationManager.IMPORTANCE_HIGH
                ).apply {
                    description = "Your daily schedule reminders"
                    setSound(null, null)
                    enableVibration(false)
                }
                nm.createNotificationChannel(ch)
            }

            val title = if (taskTitle.isNotEmpty()) "\u2705 Done: $taskTitle" else "\u2705 Alarm dismissed"
            val body  = "Tap to view your schedule"

            // The launch intent for this notification does NOT carry any
            // alarm_payload or lock-screen flags, so MainActivity will open
            // normally (behind the device unlock screen).
            val launchIntent = Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_CLEAR_TOP or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP
                putExtra("notif_payload", "open_schedule")
            }
            val pi = PendingIntent.getActivity(
                this, 88888, launchIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            val notif = androidx.core.app.NotificationCompat.Builder(this, "eldercare_schedule_reminders")
                .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
                .setContentTitle(title)
                .setContentText(body)
                .setPriority(androidx.core.app.NotificationCompat.PRIORITY_HIGH)
                .setContentIntent(pi)
                .setAutoCancel(true)
                .build()

            nm.notify(88888, notif)
        } catch (e: Exception) {
            android.util.Log.e("AlarmService", "showViewScheduleNotification failed: $e")
        }
    }
}
