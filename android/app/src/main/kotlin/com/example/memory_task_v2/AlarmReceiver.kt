package com.example.memory_task_v2

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.PowerManager

/**
 * Pure-native BroadcastReceiver that fires when an AlarmManager.setAlarmClock()
 * alarm triggers.  Starts [AlarmForegroundService] which handles audio playback,
 * vibration, and the full-screen notification.
 *
 * Using a foreground service (rather than posting a notification from the
 * receiver directly) is the only way to reliably play audio when the app is
 * killed, because BroadcastReceivers are killed after ~10 s.
 */
class AlarmReceiver : BroadcastReceiver() {

    companion object {
        const val EXTRA_TITLE            = "alarm_title"
        const val EXTRA_BODY             = "alarm_body"
        const val EXTRA_ID               = "alarm_notif_id"
        const val EXTRA_PAYLOAD          = "alarm_payload"
        const val EXTRA_USE_ALARM_SCREEN = "use_alarm_screen"
        const val EXTRA_SKIP_AUDIO       = "skip_audio"
    }

    override fun onReceive(context: Context, intent: Intent) {
        val title          = intent.getStringExtra(EXTRA_TITLE)                  ?: "Task Reminder"
        val body           = intent.getStringExtra(EXTRA_BODY)                   ?: ""
        val payload        = intent.getStringExtra(EXTRA_PAYLOAD)                ?: ""
        val notifId        = intent.getIntExtra(EXTRA_ID, 0)
        val useAlarmScreen = intent.getBooleanExtra(EXTRA_USE_ALARM_SCREEN, true)
        val skipAudio      = intent.getBooleanExtra(EXTRA_SKIP_AUDIO, false)

        // Start the foreground service — it plays audio, vibrates, and posts
        // the high-priority notification with a fullScreenIntent for the
        // lock-screen (screen-off) case.
        val serviceIntent = AlarmForegroundService.buildIntent(
            context        = context,
            title          = title,
            body           = body,
            payload        = payload,
            notifId        = notifId,
            useAlarmScreen = useAlarmScreen,
            skipAudio      = skipAudio,
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(serviceIntent)
        } else {
            context.startService(serviceIntent)
        }

        if (useAlarmScreen) {
            // When the screen is already ON (interactive), Android's fullScreenIntent
            // only shows a heads-up banner — it does NOT force the alarm screen to
            // appear.  We detect this and call startActivity() directly instead.
            // AlarmManager.setAlarmClock() grants BroadcastReceivers the privilege
            // to start activities from background, so this is always allowed.
            val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
            if (pm.isInteractive) {
                try {
                    val launchIntent = Intent(context, MainActivity::class.java).apply {
                        addFlags(
                            Intent.FLAG_ACTIVITY_NEW_TASK or
                            Intent.FLAG_ACTIVITY_SINGLE_TOP or
                            Intent.FLAG_ACTIVITY_CLEAR_TOP
                        )
                        putExtra("alarm_payload", payload)
                    }
                    context.startActivity(launchIntent)
                } catch (e: Exception) {
                    android.util.Log.e("AlarmReceiver", "startActivity failed (phone ON): $e")
                }
            }
            // When screen is OFF/locked: the fullScreenIntent in the foreground
            // service notification launches MainActivity over the lock screen.
        }
    }
}
