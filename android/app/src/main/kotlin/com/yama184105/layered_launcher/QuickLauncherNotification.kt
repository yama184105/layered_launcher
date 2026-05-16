package com.yama184105.layered_launcher

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import android.widget.RemoteViews
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat

/**
 * Persistent notification for quick app launch from the shade.
 *
 * Single consolidated notification with a custom expandable list of
 * apps. Optional thin dividers between rows for visual separation.
 *
 * Two channels back the notification so the user can pick between a
 * quiet (LOW) display and a prominent (DEFAULT) one that briefly
 * shows as heads-up.
 */
object QuickLauncherNotification {
    private const val TAG = "QuickLauncherNotif"

    const val CHANNEL_ID_SILENT = "quick_launcher"
    const val CHANNEL_ID_PROMINENT = "quick_launcher_prominent"

    private const val NOTIFICATION_ID = 9001

    /** Stale notification ids from prior per-app implementation. Kept
     *  here so cancelAll() can wipe ghosts after upgrade. */
    private const val NOTIFICATION_ID_STALE_SUMMARY = 9099
    private const val NOTIFICATION_ID_PER_APP_BASE = 9100

    /** Cap how many apps appear in the expanded list. */
    private const val MAX_APPS = 12

    data class App(val packageName: String, val label: String)

    fun ensureChannels(ctx: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        if (nm.getNotificationChannel(CHANNEL_ID_SILENT) == null) {
            val ch = NotificationChannel(
                CHANNEL_ID_SILENT,
                "クイック起動 (静か)",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "シェード内で折りたたみ表示する常駐通知"
                setShowBadge(false)
                enableLights(false)
                enableVibration(false)
                setSound(null, null)
            }
            nm.createNotificationChannel(ch)
        }

        if (nm.getNotificationChannel(CHANNEL_ID_PROMINENT) == null) {
            val ch = NotificationChannel(
                CHANNEL_ID_PROMINENT,
                "クイック起動 (目立つ)",
                NotificationManager.IMPORTANCE_DEFAULT,
            ).apply {
                description = "投稿時にヘッズアップ表示する常駐通知"
                setShowBadge(false)
                enableLights(false)
                enableVibration(false)
                setSound(null, null)
            }
            nm.createNotificationChannel(ch)
        }
    }

    fun update(
        ctx: Context,
        enabled: Boolean,
        apps: List<App>,
        prominent: Boolean = false,
        showDividers: Boolean = false,
    ) {
        cancelAll(ctx)
        if (!enabled) return
        try {
            ensureChannels(ctx)
            postConsolidated(ctx, apps.take(MAX_APPS), prominent, showDividers)
        } catch (e: Exception) {
            Log.w(TAG, "failed to post quick launcher notification", e)
        }
    }

    private fun cancelAll(ctx: Context) {
        try {
            val nm = NotificationManagerCompat.from(ctx)
            nm.cancel(NOTIFICATION_ID)
            // Wipe leftovers from previous per-app implementation so
            // they don't linger after upgrade.
            nm.cancel(NOTIFICATION_ID_STALE_SUMMARY)
            for (i in 0 until MAX_APPS) {
                nm.cancel(NOTIFICATION_ID_PER_APP_BASE + i)
            }
        } catch (_: Exception) {}
    }

    private fun postConsolidated(
        ctx: Context,
        apps: List<App>,
        prominent: Boolean,
        showDividers: Boolean,
    ) {
        val collapsed = RemoteViews(ctx.packageName, R.layout.quick_launcher_collapsed)

        val expanded = RemoteViews(ctx.packageName, R.layout.quick_launcher_expanded)
        expanded.removeAllViews(R.id.app_list)

        for ((index, app) in apps.withIndex()) {
            val row = buildRow(ctx, app, index) ?: continue
            expanded.addView(R.id.app_list, row)
            if (showDividers && index < apps.size - 1) {
                val divider = RemoteViews(ctx.packageName, R.layout.quick_launcher_divider)
                expanded.addView(R.id.app_list, divider)
            }
        }

        val openLauncherPi = openLauncherPendingIntent(ctx)
        val (channel, priority) = channelAndPriority(prominent)

        val notification = NotificationCompat.Builder(ctx, channel)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setOngoing(true)
            .setOnlyAlertOnce(!prominent)
            .setPriority(priority)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setStyle(NotificationCompat.DecoratedCustomViewStyle())
            .setCustomContentView(collapsed)
            .setCustomBigContentView(expanded)
            .setContentIntent(openLauncherPi)
            .build()

        NotificationManagerCompat.from(ctx).notify(NOTIFICATION_ID, notification)
    }

    private fun buildRow(ctx: Context, app: App, index: Int): RemoteViews? {
        val launchIntent = ctx.packageManager.getLaunchIntentForPackage(app.packageName)
            ?: return null

        val row = RemoteViews(ctx.packageName, R.layout.quick_launcher_app_row)
        row.setTextViewText(R.id.app_name, app.label)

        val normalIntent = Intent(launchIntent).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK
        }
        val normalPi = PendingIntent.getActivity(
            ctx,
            10000 + index,
            normalIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        row.setOnClickPendingIntent(R.id.app_name, normalPi)

        return row
    }

    private fun channelAndPriority(prominent: Boolean): Pair<String, Int> {
        return if (prominent) {
            CHANNEL_ID_PROMINENT to NotificationCompat.PRIORITY_DEFAULT
        } else {
            CHANNEL_ID_SILENT to NotificationCompat.PRIORITY_LOW
        }
    }

    private fun openLauncherPendingIntent(ctx: Context): PendingIntent {
        val intent = Intent(ctx, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT
        }
        return PendingIntent.getActivity(
            ctx,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }
}
