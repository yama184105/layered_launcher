package com.yama184105.layered_launcher

import android.app.AppOpsManager
import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.ContentUris
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.location.LocationManager
import android.net.Uri
import android.os.BatteryManager
import android.os.Build
import android.os.Bundle
import android.provider.CalendarContract
import android.provider.Settings
import android.app.usage.UsageStatsManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.Calendar

class MainActivity : FlutterActivity() {

    private val CHANNEL = "com.yama184105.layered_launcher/native"
    private var homeChannel: MethodChannel? = null

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (intent.hasCategory(Intent.CATEGORY_HOME) ||
            (intent.action == Intent.ACTION_MAIN && intent.categories?.contains(Intent.CATEGORY_HOME) == true)) {
            homeChannel?.invokeMethod("onHomePressed", null)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        homeChannel = channel
        channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "getBatteryLevel" -> {
                        val bm = getSystemService(Context.BATTERY_SERVICE) as BatteryManager
                        val level = bm.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
                        result.success(level)
                    }
                    "getTodayScreenTime" -> {
                        result.success(getTodayScreenTimeMinutes())
                    }
                    "getCalendarEvents" -> {
                        result.success(getCalendarEvents())
                    }
                    "getNotificationCounts" -> {
                        result.success(NotificationService.counts.toMap())
                    }
                    "setOffPackages" -> {
                        // Persist the list of OFF-mode packages where
                        // NotificationService can read it on each posted
                        // notification. Stored in SharedPreferences so it
                        // survives even if the Flutter engine is killed.
                        val pkgs = (call.arguments as? List<*>)
                            ?.filterIsInstance<String>()
                            ?.toSet()
                            ?: emptySet()
                        val sp = getSharedPreferences(
                            NotificationService.PREFS_NAME,
                            Context.MODE_PRIVATE,
                        )
                        sp.edit()
                            .putStringSet(NotificationService.KEY_OFF_PACKAGES, pkgs)
                            .apply()
                        // Sweep currently-active notifications too, so apps
                        // moved into OFF after they posted get cleared.
                        try {
                            val service = NotificationService.instance
                            service?.activeNotifications?.forEach { sbn ->
                                if (pkgs.contains(sbn.packageName)) {
                                    try { service.cancelNotification(sbn.key) } catch (_: Exception) {}
                                }
                            }
                        } catch (_: Exception) {}
                        result.success(null)
                    }
                    "isNotificationServiceEnabled" -> {
                        val enabled = Settings.Secure.getString(
                            contentResolver,
                            "enabled_notification_listeners"
                        )?.contains(packageName) == true
                        result.success(enabled)
                    }
                    "openNotificationAccessSettings" -> {
                        startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
                        result.success(null)
                    }
                    "lockScreen" -> {
                        val dpm = getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
                        val admin = ComponentName(this, DeviceAdminReceiver::class.java)
                        return@setMethodCallHandler if (dpm.isAdminActive(admin)) {
                            dpm.lockNow()
                            result.success(true)
                        } else {
                            result.success(false)
                        }
                    }
                    "isDeviceAdminEnabled" -> {
                        val dpm = getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
                        val admin = ComponentName(this, DeviceAdminReceiver::class.java)
                        result.success(dpm.isAdminActive(admin))
                    }
                    "openDeviceAdminSettings" -> {
                        val admin = ComponentName(this, DeviceAdminReceiver::class.java)
                        val intent = Intent(DevicePolicyManager.ACTION_ADD_DEVICE_ADMIN).apply {
                            putExtra(DevicePolicyManager.EXTRA_DEVICE_ADMIN, admin)
                        }
                        startActivity(intent)
                        result.success(null)
                    }
                    "isUsageStatsPermissionGranted" -> {
                        result.success(isUsageStatsGranted())
                    }
                    "openUsageStatsSettings" -> {
                        startActivity(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS))
                        result.success(null)
                    }
                    "getUsageStats30Days" -> {
                        result.success(getUsageStats30Days())
                    }
                    "getLastTimeUsedMap" -> {
                        result.success(getLastTimeUsedMap())
                    }
                    "getLastKnownLocation" -> {
                        result.success(getLastKnownLocation())
                    }
                    "openDial" -> {
                        startActivity(Intent(Intent.ACTION_DIAL))
                        result.success(null)
                    }
                    "openCamera" -> {
                        startActivity(Intent(android.provider.MediaStore.ACTION_IMAGE_CAPTURE))
                        result.success(null)
                    }
                    "openAlarmClock" -> {
                        startActivity(Intent(android.provider.AlarmClock.ACTION_SHOW_ALARMS))
                        result.success(null)
                    }
                    "openDeviceSettings" -> {
                        startActivity(Intent(Settings.ACTION_SETTINGS))
                        result.success(null)
                    }
                    "isCharging" -> {
                        val filter = IntentFilter(Intent.ACTION_BATTERY_CHANGED)
                        val battery = registerReceiver(null, filter)
                        val status = battery?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1
                        result.success(status == BatteryManager.BATTERY_STATUS_CHARGING || status == BatteryManager.BATTERY_STATUS_FULL)
                    }
                    "uninstallApp" -> {
                        val pkg = call.argument<String>("packageName") ?: ""
                        val intent = Intent(Intent.ACTION_DELETE, Uri.parse("package:$pkg"))
                        startActivity(intent)
                        result.success(null)
                    }
                    "sendEmail" -> {
                        val to = call.argument<String>("to") ?: ""
                        val subject = call.argument<String>("subject") ?: ""
                        val body = call.argument<String>("body") ?: ""
                        val intent = Intent(Intent.ACTION_SEND).apply {
                            type = "message/rfc822"
                            putExtra(Intent.EXTRA_EMAIL, arrayOf(to))
                            putExtra(Intent.EXTRA_SUBJECT, subject)
                            putExtra(Intent.EXTRA_TEXT, body)
                        }
                        startActivity(Intent.createChooser(intent, "メールアプリを選択"))
                        result.success(null)
                    }
                    "expandNotificationPanel" -> {
                        try {
                            val sbService = getSystemService("statusbar")
                            val sbClass = Class.forName("android.app.StatusBarManager")
                            val method = sbClass.getMethod("expandNotificationsPanel")
                            method.invoke(sbService)
                            result.success(true)
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun getTodayScreenTimeMinutes(): Int {
        if (!isUsageStatsGranted()) return -1
        val usm = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val cal = Calendar.getInstance()
        cal.set(Calendar.HOUR_OF_DAY, 0)
        cal.set(Calendar.MINUTE, 0)
        cal.set(Calendar.SECOND, 0)
        cal.set(Calendar.MILLISECOND, 0)
        val startTime = cal.timeInMillis
        val endTime = System.currentTimeMillis()
        val stats = usm.queryUsageStats(UsageStatsManager.INTERVAL_DAILY, startTime, endTime)
        var totalMs = 0L
        for (s in stats) {
            if (s.totalTimeInForeground > 0) totalMs += s.totalTimeInForeground
        }
        return (totalMs / 60000).toInt()
    }

    private fun getCalendarEvents(): List<Map<String, Any?>> {
        val events = mutableListOf<Map<String, Any?>>()
        try {
            val cal = Calendar.getInstance()
            cal.set(Calendar.HOUR_OF_DAY, 0)
            cal.set(Calendar.MINUTE, 0)
            cal.set(Calendar.SECOND, 0)
            cal.set(Calendar.MILLISECOND, 0)
            val startMs = cal.timeInMillis
            val endMs = startMs + 2 * 24 * 60 * 60 * 1000L

            val uri = CalendarContract.Events.CONTENT_URI
            val projection = arrayOf(
                CalendarContract.Events._ID,
                CalendarContract.Events.TITLE,
                CalendarContract.Events.DTSTART,
                CalendarContract.Events.DTEND,
                CalendarContract.Events.ALL_DAY
            )
            val selection =
                "${CalendarContract.Events.DTSTART} >= ? AND ${CalendarContract.Events.DTSTART} < ?"
            val selArgs = arrayOf(startMs.toString(), endMs.toString())
            val cursor = contentResolver.query(uri, projection, selection, selArgs, "${CalendarContract.Events.DTSTART} ASC")
            cursor?.use {
                while (it.moveToNext()) {
                    events.add(mapOf(
                        "title" to it.getString(1),
                        "dtstart" to it.getLong(2),
                        "dtend" to it.getLong(3),
                        "allDay" to (it.getInt(4) == 1)
                    ))
                }
            }
        } catch (_: Exception) {}
        return events
    }

    private fun isUsageStatsGranted(): Boolean {
        val appOps = getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            appOps.unsafeCheckOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                android.os.Process.myUid(),
                packageName
            )
        } else {
            @Suppress("DEPRECATION")
            appOps.checkOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                android.os.Process.myUid(),
                packageName
            )
        }
        return mode == AppOpsManager.MODE_ALLOWED
    }

    private fun getUsageStats30Days(): Map<String, Int> {
        if (!isUsageStatsGranted()) return emptyMap()
        val usm = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val endTime = System.currentTimeMillis()
        val startTime = endTime - 30L * 24 * 60 * 60 * 1000
        val stats = usm.queryUsageStats(UsageStatsManager.INTERVAL_MONTHLY, startTime, endTime)
        val result = mutableMapOf<String, Int>()
        for (s in stats) {
            if (s.totalTimeInForeground > 0) {
                val minutes = (s.totalTimeInForeground / 60000).toInt()
                result[s.packageName] = (result[s.packageName] ?: 0) + minutes
            }
        }
        return result
    }

    /// Returns a map of packageName -> lastTimeUsed (epoch ms) for apps used in
    /// the past 30 days. Empty map if usage-stats permission is not granted.
    private fun getLastTimeUsedMap(): Map<String, Long> {
        if (!isUsageStatsGranted()) return emptyMap()
        val usm = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val endTime = System.currentTimeMillis()
        val startTime = endTime - 30L * 24 * 60 * 60 * 1000
        val stats = usm.queryUsageStats(UsageStatsManager.INTERVAL_BEST, startTime, endTime)
        val result = mutableMapOf<String, Long>()
        for (s in stats) {
            val t = s.lastTimeUsed
            if (t <= 0) continue
            val prev = result[s.packageName] ?: 0L
            if (t > prev) result[s.packageName] = t
        }
        return result
    }

    private fun getLastKnownLocation(): Map<String, Double>? {
        return try {
            val lm = getSystemService(Context.LOCATION_SERVICE) as LocationManager
            val providers = listOf(LocationManager.NETWORK_PROVIDER, LocationManager.GPS_PROVIDER)
            for (provider in providers) {
                @Suppress("MissingPermission")
                val loc = lm.getLastKnownLocation(provider)
                if (loc != null) {
                    return mapOf("lat" to loc.latitude, "lon" to loc.longitude)
                }
            }
            null
        } catch (_: Exception) {
            null
        }
    }
}
