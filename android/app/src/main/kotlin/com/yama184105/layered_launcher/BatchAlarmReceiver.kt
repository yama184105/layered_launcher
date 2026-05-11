package com.yama184105.layered_launcher

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import org.json.JSONArray
import org.json.JSONObject

/**
 * Fires when AlarmManager wakes us at a batch group's scheduled time.
 *
 * Reads the saved (intercepted) notifications for this group from
 * SharedPreferences, re-posts each one through NotificationManager so the
 * user finally sees them, clears the storage, then re-arms the next alarm
 * for the group.
 */
class BatchAlarmReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "BatchAlarmReceiver"
        private const val CHANNEL_ID = "batch_replay_channel"
        private const val CHANNEL_NAME = "Batched notifications"
    }

    override fun onReceive(context: Context, intent: Intent) {
        val groupId = intent.getStringExtra(BatchAlarms.EXTRA_GROUP_ID) ?: return
        Log.d(TAG, "Firing group $groupId")

        ensureChannel(context)

        val sp = context.getSharedPreferences(
            NotificationService.PREFS_NAME,
            Context.MODE_PRIVATE,
        )
        val savedKey = NotificationService.savedNotifsKeyFor(groupId)
        val raw = sp.getString(savedKey, null)

        if (!raw.isNullOrEmpty()) {
            try {
                val arr = JSONArray(raw)
                replayNotifications(context, groupId, arr)
            } catch (e: Exception) {
                Log.w(TAG, "Replay failed for $groupId", e)
            }
            // Clear storage regardless — these are now "delivered" and we
            // don't want them to re-fire next time.
            sp.edit().remove(savedKey).apply()
        }

        // Re-arm the next alarm for this group based on its schedule.
        val groupsJson = sp.getString(NotificationService.KEY_BATCH_GROUPS, null) ?: return
        try {
            val groups = JSONArray(groupsJson)
            for (i in 0 until groups.length()) {
                val g = groups.getJSONObject(i)
                if (g.optString("id") == groupId) {
                    BatchAlarms.scheduleGroup(context, g)
                    break
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "Reschedule failed for $groupId", e)
        }
    }

    /**
     * Re-posts the saved notifications. We post one per source app (merging
     * multiple notifications from the same app into a count), labelled with
     * the source app name. Tapping opens the source app.
     */
    private fun replayNotifications(
        context: Context,
        groupId: String,
        arr: JSONArray,
    ) {
        val nm = ContextCompat.getSystemService(context, NotificationManager::class.java)
            ?: return
        val pm = context.packageManager

        // Group entries by package so we don't spam the user.
        val byPkg = mutableMapOf<String, MutableList<JSONObject>>()
        for (i in 0 until arr.length()) {
            val obj = arr.optJSONObject(i) ?: continue
            val pkg = obj.optString("pkg", "")
            if (pkg.isEmpty()) continue
            byPkg.getOrPut(pkg) { mutableListOf() }.add(obj)
        }

        for ((pkg, entries) in byPkg) {
            val appLabel = try {
                pm.getApplicationLabel(pm.getApplicationInfo(pkg, 0)).toString()
            } catch (_: Exception) {
                pkg
            }

            // Build the launch intent so the user can tap into the source app.
            val launch = pm.getLaunchIntentForPackage(pkg)
            val contentIntent = if (launch != null) {
                PendingIntent.getActivity(
                    context,
                    pkg.hashCode(),
                    launch,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                )
            } else null

            val largeIcon = try {
                drawableToBitmap(pm.getApplicationIcon(pkg))
            } catch (_: Exception) { null }

            // Posting strategy: one notification per app per fire, with
            // either the latest title/body (single) or a "+N more" body
            // (multiple). Inline preview shows the latest entry.
            if (entries.size == 1) {
                val e = entries[0]
                val title = e.optString("title", appLabel)
                val text = e.optString("text", "")
                val builder = NotificationCompat.Builder(context, CHANNEL_ID)
                    .setSmallIcon(R.mipmap.ic_launcher)
                    .setContentTitle(title)
                    .setContentText(text)
                    .setSubText(appLabel)
                    .setStyle(NotificationCompat.BigTextStyle().bigText(text))
                    .setAutoCancel(true)
                    .setPriority(NotificationCompat.PRIORITY_DEFAULT)
                if (largeIcon != null) builder.setLargeIcon(largeIcon)
                if (contentIntent != null) builder.setContentIntent(contentIntent)
                nm.notify(replayId(groupId, pkg), builder.build())
            } else {
                // Multi: latest entry as headline, all titles as inbox style.
                val sorted = entries.sortedByDescending { it.optLong("postedAt", 0) }
                val latest = sorted[0]
                val latestTitle = latest.optString("title", appLabel)
                val latestText = latest.optString("text", "")
                val inbox = NotificationCompat.InboxStyle()
                    .setBigContentTitle("$appLabel · ${entries.size} 件")
                for (e in sorted.take(8)) {
                    val t = e.optString("title", "")
                    val b = e.optString("text", "")
                    val line = if (t.isNotEmpty() && b.isNotEmpty()) "$t  $b"
                        else (t.ifEmpty { b })
                    inbox.addLine(line)
                }
                val builder = NotificationCompat.Builder(context, CHANNEL_ID)
                    .setSmallIcon(R.mipmap.ic_launcher)
                    .setContentTitle("$appLabel · ${entries.size} 件")
                    .setContentText("$latestTitle  $latestText")
                    .setSubText(appLabel)
                    .setStyle(inbox)
                    .setNumber(entries.size)
                    .setAutoCancel(true)
                    .setPriority(NotificationCompat.PRIORITY_DEFAULT)
                if (largeIcon != null) builder.setLargeIcon(largeIcon)
                if (contentIntent != null) builder.setContentIntent(contentIntent)
                nm.notify(replayId(groupId, pkg), builder.build())
            }
        }
    }

    private fun replayId(groupId: String, pkg: String): Int =
        ("replay:$groupId:$pkg").hashCode()

    private fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = ContextCompat.getSystemService(context, NotificationManager::class.java)
            ?: return
        if (nm.getNotificationChannel(CHANNEL_ID) == null) {
            val ch = NotificationChannel(
                CHANNEL_ID,
                CHANNEL_NAME,
                NotificationManager.IMPORTANCE_DEFAULT,
            )
            ch.description = "Layered Launcher のバッチグループでまとめた通知を配信します"
            nm.createNotificationChannel(ch)
        }
    }

    private fun drawableToBitmap(drawable: Drawable): Bitmap? {
        if (drawable is BitmapDrawable) return drawable.bitmap
        val w = drawable.intrinsicWidth.takeIf { it > 0 } ?: 96
        val h = drawable.intrinsicHeight.takeIf { it > 0 } ?: 96
        val bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bmp)
        drawable.setBounds(0, 0, canvas.width, canvas.height)
        drawable.draw(canvas)
        return bmp
    }
}
