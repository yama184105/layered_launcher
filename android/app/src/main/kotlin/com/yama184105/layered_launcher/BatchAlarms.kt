package com.yama184105.layered_launcher

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.util.Calendar

/**
 * Helper functions shared between MainActivity, BatchAlarmReceiver, and
 * BatchBootReceiver for scheduling AlarmManager wake-ups for each batch
 * group's next delivery time.
 *
 * Batch groups are persisted as JSON in SharedPreferences (see
 * NotificationService.PREFS_NAME / KEY_BATCH_GROUPS) so we can recover
 * after reboot or after Flutter is killed.
 */
object BatchAlarms {

    private const val TAG = "BatchAlarms"
    private const val ACTION_FIRE = "com.yama184105.layered_launcher.BATCH_FIRE"
    const val EXTRA_GROUP_ID = "groupId"

    /** Builds the PendingIntent that BatchAlarmReceiver will receive. */
    private fun pendingIntentFor(context: Context, groupId: String): PendingIntent {
        val intent = Intent(context, BatchAlarmReceiver::class.java).apply {
            action = ACTION_FIRE
            putExtra(EXTRA_GROUP_ID, groupId)
        }
        return PendingIntent.getBroadcast(
            context,
            groupId.hashCode(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    /** Schedules the next firing for [group] (and only the next — we
     *  re-schedule from BatchAlarmReceiver after each fire). */
    fun scheduleGroup(context: Context, group: JSONObject) {
        val groupId = group.optString("id", "")
        if (groupId.isEmpty()) return
        val nextMs = computeNextFireTimeMs(group, System.currentTimeMillis()) ?: return
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val pi = pendingIntentFor(context, groupId)
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                if (am.canScheduleExactAlarms()) {
                    am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, nextMs, pi)
                } else {
                    // Fallback: less precise (~9-15 min window during Doze) but
                    // doesn't need SCHEDULE_EXACT_ALARM permission.
                    am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, nextMs, pi)
                }
            } else {
                am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, nextMs, pi)
            }
            Log.d(TAG, "Scheduled $groupId at ${java.util.Date(nextMs)}")
        } catch (e: SecurityException) {
            // SCHEDULE_EXACT_ALARM might be revoked — fall through to inexact.
            am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, nextMs, pi)
        }
    }

    fun cancelGroup(context: Context, groupId: String) {
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        am.cancel(pendingIntentFor(context, groupId))
    }

    /** Re-reads the persisted group list and re-arms an alarm for each.
     *  Called from BatchBootReceiver and after MainActivity.setBatchGroups. */
    fun rescheduleAll(context: Context) {
        val sp = context.getSharedPreferences(
            NotificationService.PREFS_NAME,
            Context.MODE_PRIVATE,
        )
        val raw = sp.getString(NotificationService.KEY_BATCH_GROUPS, null) ?: return
        try {
            val arr = JSONArray(raw)
            for (i in 0 until arr.length()) {
                scheduleGroup(context, arr.getJSONObject(i))
            }
        } catch (e: Exception) {
            Log.w(TAG, "rescheduleAll: bad JSON", e)
        }
    }

    /**
     * Computes the next fire time for a group based on its schedule type,
     * weekday filter, and the current epoch [fromMs]. Returns null if the
     * schedule is empty (e.g. 'fixed' with zero times).
     */
    fun computeNextFireTimeMs(group: JSONObject, fromMs: Long): Long? {
        val type = group.optString("scheduleType", "interval")
        val weekdaysArr = group.optJSONArray("weekdays") ?: JSONArray("[1,2,3,4,5,6,7]")
        val weekdays = HashSet<Int>()
        for (i in 0 until weekdaysArr.length()) weekdays.add(weekdaysArr.optInt(i))
        if (weekdays.isEmpty()) return null

        when (type) {
            "interval" -> {
                val mins = group.optInt("intervalMinutes", 240)
                val cand = Calendar.getInstance().apply {
                    timeInMillis = fromMs
                    add(Calendar.MINUTE, mins)
                    set(Calendar.SECOND, 0)
                    set(Calendar.MILLISECOND, 0)
                }
                // Walk forward up to 7 days to land on an enabled weekday.
                var safety = 0
                while (!weekdays.contains(dartWeekday(cand)) && safety < 8) {
                    cand.add(Calendar.DAY_OF_MONTH, 1)
                    cand.set(Calendar.HOUR_OF_DAY, 0)
                    cand.set(Calendar.MINUTE, 0)
                    safety++
                }
                return cand.timeInMillis
            }
            "fixed", "dailyOnce" -> {
                val times = collectTimes(group, type)
                if (times.isEmpty()) return null
                val from = Calendar.getInstance().apply { timeInMillis = fromMs }
                // Search up to 8 days ahead; we always find a match if at
                // least one weekday is enabled.
                for (dayOffset in 0..8) {
                    val day = from.clone() as Calendar
                    day.add(Calendar.DAY_OF_MONTH, dayOffset)
                    if (!weekdays.contains(dartWeekday(day))) continue
                    val sorted = times.sortedBy { it.first * 60 + it.second }
                    for ((h, m) in sorted) {
                        val candidate = day.clone() as Calendar
                        candidate.set(Calendar.HOUR_OF_DAY, h)
                        candidate.set(Calendar.MINUTE, m)
                        candidate.set(Calendar.SECOND, 0)
                        candidate.set(Calendar.MILLISECOND, 0)
                        if (candidate.timeInMillis > fromMs) {
                            return candidate.timeInMillis
                        }
                    }
                }
            }
        }
        return null
    }

    private fun collectTimes(group: JSONObject, type: String): List<Pair<Int, Int>> {
        val out = mutableListOf<Pair<Int, Int>>()
        if (type == "fixed") {
            val arr = group.optJSONArray("times") ?: return emptyList()
            for (i in 0 until arr.length()) {
                val t = arr.optJSONObject(i) ?: continue
                out.add(Pair(t.optInt("h", 0), t.optInt("m", 0)))
            }
        } else if (type == "dailyOnce") {
            val t = group.optJSONObject("time") ?: return emptyList()
            out.add(Pair(t.optInt("h", 7), t.optInt("m", 0)))
        }
        return out
    }

    /**
     * Java Calendar uses SUNDAY=1..SATURDAY=7, but our app stores Dart-style
     * weekdays (MONDAY=1..SUNDAY=7). Translate so set membership works.
     */
    private fun dartWeekday(cal: Calendar): Int = when (cal.get(Calendar.DAY_OF_WEEK)) {
        Calendar.MONDAY -> 1
        Calendar.TUESDAY -> 2
        Calendar.WEDNESDAY -> 3
        Calendar.THURSDAY -> 4
        Calendar.FRIDAY -> 5
        Calendar.SATURDAY -> 6
        Calendar.SUNDAY -> 7
        else -> 1
    }
}
