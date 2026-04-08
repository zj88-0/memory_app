package com.example.memory_task_v2

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import org.json.JSONArray

/**
 * BootReceiver — reschedules native AlarmManager alarms after device reboot.
 *
 * Android clears all AlarmManager alarms when the device shuts down.  This
 * receiver fires on BOOT_COMPLETED and re-schedules every alarm whose data
 * was persisted by AlarmService into Flutter's SharedPreferences.
 *
 * Note: Flutter's shared_preferences plugin stores all keys with a
 *       "flutter." prefix inside the "{packageName}_preferences" file.
 *       We replicate that prefix here so reads match what Dart wrote.
 *
 * The alarm package (Layer 1) handles its own boot rescheduling internally.
 * This receiver only handles the native Layer 2 alarms.
 */
class BootReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        if (action != Intent.ACTION_BOOT_COMPLETED &&
            action != "android.intent.action.QUICKBOOT_POWERON" &&
            action != "com.htc.intent.action.QUICKBOOT_POWERON"
        ) return

        // Flutter's SharedPreferences file & key prefix.
        val prefs = context.getSharedPreferences(
            "${context.packageName}_preferences", Context.MODE_PRIVATE
        )
        val idsJson = prefs.getString("flutter.alarm_active_ids", null) ?: return

        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val nowMs = System.currentTimeMillis()

        try {
            val idsArray = JSONArray(idsJson)
            for (i in 0 until idsArray.length()) {
                val alarmId = idsArray.getInt(i)

                // Read alarm data (all keys are "flutter.<key>" on Android).
                val title      = prefs.getString("flutter.alarm_title_$alarmId",   "Task Reminder") ?: "Task Reminder"
                val body       = prefs.getString("flutter.alarm_body_$alarmId",    "")              ?: ""
                val payload    = prefs.getString("flutter.alarm_payload_$alarmId", "")              ?: ""
                val triggerMs  = prefs.getLong("flutter.alarm_trigger_ms_$alarmId", 0L)

                // Skip past-due alarms; they will be shown by showPendingOrMissedAlarm().
                if (triggerMs <= nowMs) continue

                val alarmIntent = Intent(context, AlarmReceiver::class.java).apply {
                    putExtra(AlarmReceiver.EXTRA_TITLE,            title)
                    putExtra(AlarmReceiver.EXTRA_BODY,             body)
                    putExtra(AlarmReceiver.EXTRA_ID,               alarmId)
                    putExtra(AlarmReceiver.EXTRA_PAYLOAD,          payload)
                    putExtra(AlarmReceiver.EXTRA_USE_ALARM_SCREEN, true)
                    // skipAudio=true: Flutter alarm package handles audio.
                    putExtra(AlarmReceiver.EXTRA_SKIP_AUDIO,       true)
                }
                val piFlags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                val pi = PendingIntent.getBroadcast(context, alarmId, alarmIntent, piFlags)

                when {
                    Build.VERSION.SDK_INT >= Build.VERSION_CODES.S -> {
                        if (am.canScheduleExactAlarms()) {
                            am.setAlarmClock(AlarmManager.AlarmClockInfo(triggerMs, pi), pi)
                        } else {
                            am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerMs, pi)
                        }
                    }
                    Build.VERSION.SDK_INT >= Build.VERSION_CODES.M ->
                        am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerMs, pi)
                    else ->
                        am.setExact(AlarmManager.RTC_WAKEUP, triggerMs, pi)
                }

                android.util.Log.d("BootReceiver",
                    "Rescheduled alarm #$alarmId \"$title\" at $triggerMs")
            }
        } catch (e: Exception) {
            android.util.Log.e("BootReceiver", "Error rescheduling alarms after boot: $e")
        }
    }
}
