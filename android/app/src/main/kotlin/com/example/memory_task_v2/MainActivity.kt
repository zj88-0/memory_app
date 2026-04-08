package com.example.memory_task_v2

import android.app.Activity
import android.app.AlarmManager
import android.app.KeyguardManager
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL  = "eldercare/ringtone"
        private const val REQ_PICK = 1001
    }

    private var pendingResult: MethodChannel.Result? = null
    private var initialAlarmPayload: String? = null
    // A one-shot "navigate to schedule" flag set when the activity is started
    // by tapping the native post-dismiss "View Schedule" notification.
    private var pendingOpenSchedule: Boolean = false

    private val clearFlagsReceiver = object : android.content.BroadcastReceiver() {
        override fun onReceive(context: android.content.Context?, intent: Intent?) {
            if (intent?.action == "com.example.memory_task_v2.CLEAR_LOCK_FLAGS") {
                disableShowOverLockScreen()
            }
        }
    }

    // Receives FLUTTER_METHOD broadcasts from AlarmForegroundService and relays
    // them to the running Flutter engine via MethodChannel.
    private val flutterMethodReceiver = object : android.content.BroadcastReceiver() {
        override fun onReceive(context: android.content.Context?, intent: Intent?) {
            if (intent?.action != "com.example.memory_task_v2.FLUTTER_METHOD") return
            val method   = intent.getStringExtra("method")   ?: return
            val argument = intent.getStringExtra("argument")
            flutterEngine?.dartExecutor?.binaryMessenger?.let { messenger ->
                MethodChannel(messenger, CHANNEL).invokeMethod(method, argument)
            }
        }
    }

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        val payload = intent?.getStringExtra("alarm_payload")
        if (payload != null) {
            initialAlarmPayload = payload
            enableShowOverLockScreen()
        }
        // Native "View Schedule" notification carries notif_payload = open_schedule.
        // CRITICAL: Always strip lock-screen bypass flags first so the ScheduleScreen
        // can NEVER appear over the lock screen — only the alarm screen is permitted to.
        if (intent?.getStringExtra("notif_payload") == "open_schedule") {
            disableShowOverLockScreen()
            pendingOpenSchedule = true
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(clearFlagsReceiver, android.content.IntentFilter("com.example.memory_task_v2.CLEAR_LOCK_FLAGS"), android.content.Context.RECEIVER_NOT_EXPORTED)
            registerReceiver(flutterMethodReceiver, android.content.IntentFilter("com.example.memory_task_v2.FLUTTER_METHOD"), android.content.Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(clearFlagsReceiver, android.content.IntentFilter("com.example.memory_task_v2.CLEAR_LOCK_FLAGS"))
            registerReceiver(flutterMethodReceiver, android.content.IntentFilter("com.example.memory_task_v2.FLUTTER_METHOD"))
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        unregisterReceiver(clearFlagsReceiver)
        unregisterReceiver(flutterMethodReceiver)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        val payload = intent.getStringExtra("alarm_payload")
        if (payload != null) {
            initialAlarmPayload = payload
            // Signal the running Dart/Flutter isolate directly so it can
            // push the alarm screen IMMEDIATELY without waiting for a
            // notification tap.  This fires the handler registered in
            // AlarmService.init() via _channel.setMethodCallHandler.
            flutterEngine?.dartExecutor?.binaryMessenger?.let { messenger ->
                MethodChannel(messenger, "eldercare/ringtone")
                    .invokeMethod("onAlarmPayload", payload)
            }
            // Only re-apply lock-screen flags for genuine alarm intents.
            enableShowOverLockScreen()
        }
        // Native "View Schedule" notification: signal Flutter to open ScheduleScreen.
        // CRITICAL: Strip any lingering lock-screen flags first so the schedule page
        // is never shown over the lock screen.  Also guard the Flutter callback behind
        // an isDeviceLocked() check — if the phone is still locked the OS will show
        // the unlock UI and the user must authenticate before the schedule appears.
        if (intent.getStringExtra("notif_payload") == "open_schedule") {
            disableShowOverLockScreen()
            if (!isDeviceLocked()) {
                flutterEngine?.dartExecutor?.binaryMessenger?.let { messenger ->
                    MethodChannel(messenger, "eldercare/ringtone")
                        .invokeMethod("onOpenSchedule", null)
                }
            }
        }
    }

    private fun enableShowOverLockScreen() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
            )
        }
    }

    private fun disableShowOverLockScreen() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(false)
            setTurnScreenOn(false)
        } else {
            @Suppress("DEPRECATION")
            window.clearFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
            )
        }
    }

    /** Returns true if the device is currently locked (keyguard active). */
    private fun isDeviceLocked(): Boolean {
        val km = getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
        return km.isKeyguardLocked
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
                flutterEngine.dartExecutor.binaryMessenger,
                CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {

                // ── Open the system ringtone picker ────────────────────────
                "pickRingtone" -> {
                    val currentUri = call.argument<String>("currentUri")
                    pendingResult = result

                    val intent = Intent(RingtoneManager.ACTION_RINGTONE_PICKER).apply {
                        putExtra(RingtoneManager.EXTRA_RINGTONE_TYPE,
                                RingtoneManager.TYPE_ALARM)
                        putExtra(RingtoneManager.EXTRA_RINGTONE_SHOW_DEFAULT, true)
                        putExtra(RingtoneManager.EXTRA_RINGTONE_SHOW_SILENT,  false)
                        putExtra(RingtoneManager.EXTRA_RINGTONE_TITLE,
                                "Choose alarm sound")
                        if (currentUri != null) {
                            putExtra(RingtoneManager.EXTRA_RINGTONE_EXISTING_URI,
                                    Uri.parse(currentUri))
                        }
                    }
                    startActivityForResult(intent, REQ_PICK)
                    // result is returned in onActivityResult
                }

                // ── Get human-readable name for a URI ─────────────────────
                "getRingtoneName" -> {
                    val uriStr = call.argument<String>("uri")
                    if (uriStr == null) { result.success(null); return@setMethodCallHandler }
                    val name = runCatching {
                        val uri = Uri.parse(uriStr)
                        val ringtone = RingtoneManager.getRingtone(context, uri)
                        ringtone?.getTitle(context)
                    }.getOrNull()
                    result.success(name)
                }

                // ── Get default alarm ringtone URI ────────────────────────
                "getDefaultAlarmUri" -> {
                    val uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                    result.success(uri?.toString())
                }

                // ── Get device IANA timezone name (for Flutter zonedSchedule) ─
                "getTimezone" -> {
                    result.success(java.util.TimeZone.getDefault().id)
                }

                // ── Get natively passed alarm payload ─────────────────────────
                "getInitialAlarmPayload" -> {
                    result.success(initialAlarmPayload)
                    initialAlarmPayload = null // Consume it
                }

                // ── Get and consume the pending "open schedule" flag ───────────
                // Set when app cold-starts via the "View Schedule" notification.
                // SECURITY: isDeviceLocked() guard in onCreate means this is only
                // ever true when the phone was already unlocked upon notification tap.
                "getPendingOpenSchedule" -> {
                    result.success(pendingOpenSchedule)
                    pendingOpenSchedule = false // Consume it
                }

                // ── Check if the device keyguard (lock screen) is active ────────
                // Used by Flutter to guard schedule navigation behind unlock.
                "isDeviceLocked" -> {
                    result.success(isDeviceLocked())
                }

                // ── Battery optimization exclusion ──────────────────────────
                // Shows the system dialog asking the user to exempt this app
                // from battery optimization — required for reliable wake-up
                // alarms on all Android devices, especially MIUI / ColorOS.
                "requestIgnoreBatteryOptimizations" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                        if (!pm.isIgnoringBatteryOptimizations(packageName)) {
                            val intent = Intent(
                                Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS
                            ).apply {
                                data = Uri.parse("package:$packageName")
                            }
                            startActivity(intent)
                        }
                    }
                    result.success(null)
                }

                "closeAlarmWindow" -> {
                    disableShowOverLockScreen()
                    finish() // Close the activity completely
                    result.success(null)
                }

                "isIgnoringBatteryOptimizations" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                        result.success(pm.isIgnoringBatteryOptimizations(packageName))
                    } else {
                        result.success(true) // Pre-M: no restrictions
                    }
                }

                // ── Native AlarmManager.setAlarmClock() scheduling ──────────────
                // setAlarmClock is the same type used by Android Clock.
                // It is Doze-exempt and fires at EXACT time regardless of battery
                // saver, app state (killed), or manufacturer ROM restrictions.
                "scheduleNativeAlarm" -> {
                    val id = call.argument<Int>("id") ?: 0
                    // Dart's int is 64-bit; Flutter codec boxes it as Long when
                    // the value exceeds Int.MAX_VALUE, otherwise as Int. Handle
                    // both to avoid a silent null / ClassCastException.
                    val rawMs = call.argument<Any>("triggerAtMs")
                    val triggerAtMs: Long = when (rawMs) {
                        is Long -> rawMs
                        is Int  -> rawMs.toLong()
                        else    -> 0L
                    }
                    val title          = call.argument<String>("title")          ?: ""
                    val body           = call.argument<String>("body")           ?: ""
                    val payload        = call.argument<String>("payload")        ?: ""
                    val useAlarmScreen = call.argument<Boolean>("useAlarmScreen") ?: true
                    // skipAudio=true: Flutter alarm package handles audio; native
                    // service only does the full-screen overlay + startActivity.
                    val skipAudio      = call.argument<Boolean>("skipAudio")      ?: false

                    val alarmIntent = Intent(this, AlarmReceiver::class.java).apply {
                        putExtra(AlarmReceiver.EXTRA_TITLE,            title)
                        putExtra(AlarmReceiver.EXTRA_BODY,             body)
                        putExtra(AlarmReceiver.EXTRA_ID,               id)
                        putExtra(AlarmReceiver.EXTRA_PAYLOAD,          payload)
                        putExtra(AlarmReceiver.EXTRA_USE_ALARM_SCREEN, useAlarmScreen)
                        putExtra(AlarmReceiver.EXTRA_SKIP_AUDIO,       skipAudio)
                    }
                    val piFlags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                    val pi = PendingIntent.getBroadcast(this, id, alarmIntent, piFlags)

                    val am = getSystemService(Context.ALARM_SERVICE) as AlarmManager
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        if (am.canScheduleExactAlarms()) {
                            am.setAlarmClock(AlarmManager.AlarmClockInfo(triggerAtMs, pi), pi)
                        } else {
                            am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAtMs, pi)
                        }
                    } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAtMs, pi)
                    } else {
                        am.setExact(AlarmManager.RTC_WAKEUP, triggerAtMs, pi)
                    }
                    result.success(null)
                }

                "cancelNativeAlarm" -> {
                    val id = call.argument<Int>("id") ?: 0
                    // Cancel pending AlarmManager delivery
                    val alarmIntent = Intent(this, AlarmReceiver::class.java)
                    val piFlags = PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE
                    val pi = PendingIntent.getBroadcast(this, id, alarmIntent, piFlags)
                    if (pi != null) {
                        val am = getSystemService(Context.ALARM_SERVICE) as AlarmManager
                        am.cancel(pi)
                        pi.cancel()
                    }
                    // Stop the foreground service if it is currently ringing
                    val stopIntent = Intent(this, AlarmForegroundService::class.java).apply {
                        action = AlarmForegroundService.ACTION_STOP
                    }
                    stopService(stopIntent)
                    // Explicitly remove the notification from the drawer so
                    // tapping its remnant can never re-open the alarm screen.
                    (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
                        .cancel(9999)
                    result.success(null)
                }

                // Stop native foreground alarm service (called by AlarmService.stopAlarm)
                "stopNativeAlarm" -> {
                    val stopIntent = Intent(this, AlarmForegroundService::class.java).apply {
                        action = AlarmForegroundService.ACTION_STOP
                    }
                    stopService(stopIntent)
                    // Explicitly cancel notification 9999 from the notification drawer.
                    // This is critical: if we only stop the service, the foreground
                    // notification may linger on some ROMs.  Tapping that lingering
                    // notification would re-open the alarm screen even after dismiss.
                    (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
                        .cancel(9999)
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQ_PICK) return

        val res = pendingResult
        pendingResult = null

        if (resultCode != Activity.RESULT_OK || data == null) {
            res?.success(null)   // user cancelled
            return
        }

        val uri: Uri? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            data.getParcelableExtra(RingtoneManager.EXTRA_RINGTONE_PICKED_URI, Uri::class.java)
        } else {
            @Suppress("DEPRECATION")
            data.getParcelableExtra(RingtoneManager.EXTRA_RINGTONE_PICKED_URI)
        }
        if (uri == null) { res?.success(null); return }

        val name = runCatching {
            val ringtone = RingtoneManager.getRingtone(context, uri)
            ringtone?.getTitle(context)
        }.getOrNull() ?: "Custom ringtone"

        res?.success(mapOf("uri" to uri.toString(), "name" to name))
    }
}

