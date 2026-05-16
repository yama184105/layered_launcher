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
 * Persistent notification with an expandable app list. The collapsed view
 * just shows "Layered Launcher". Expanding reveals one row per app from
 * the user-chosen source (favorites / floor1 / custom). Tapping a row
 * launches that app.
 *
 * Two channels back the notification so the user can switch between a
 * quiet (LOW) display and a prominent (DEFAULT) one that briefly shows as
 * heads-up — Android's only public lever to influence whether the shade
 * shows the notification in expanded form.
 */
object QuickLauncherNotification {
    private const val TAG = "QuickLauncherNotif"

    const val CHANNEL_ID_SILENT = "quick_launcher"
    const val CHANNEL_ID_PROMINENT = "quick_launcher_prominent"
    const val NOTIFICATION_ID = 9001

    /** Cap how many apps we put in the expanded RemoteViews. The
     *  notification panel clips long lists anyway and each row keeps a
     *  PendingIntent alive, so we limit to a sane number. */
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

    /** Post or cancel the persistent notification based on [enabled]. */
    fun update(
        ctx: Context,
        enabled: Boolean,
        apps: List<App>,
        prominent: Boolean = false,
    ) {
        if (!enabled) {
            try {
                NotificationManagerCompat.from(ctx).cancel(NOTIFICATION_ID)
            } catch (_: Exception) {}
            return
        }
        try {
            ensureChannels(ctx)
            val notification = buildNotification(ctx, apps.take(MAX_APPS), prominent)
            NotificationManagerCompat.from(ctx).notify(NOTIFICATION_ID, notification)
        } catch (e: Exception) {
            Log.w(TAG, "failed to post quick launcher notification", e)
        }
    }

    private fun buildNotification(
        ctx: Context,
        apps: List<App>,
        prominent: Boolean,
    ): android.app.Notification {
        val collapsed = RemoteViews(ctx.packageName, R.layout.quick_launcher_collapsed)

        val expanded = RemoteViews(ctx.packageName, R.layout.quick_launcher_expanded)
        expanded.removeAllViews(R.id.app_list)

        for ((index, app) in apps.withIndex()) {
            val row = buildRow(ctx, app, index) ?: continue
            expanded.addView(R.id.app_list, row)
        }

        // Tap the notification body itself opens our launcher app.
        val openLauncherIntent = Intent(ctx, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT
        }
        val openLauncherPi = PendingIntent.getActivity(
            ctx,
            0,
            openLauncherIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val channel = if (prominent) CHANNEL_ID_PROMINENT else CHANNEL_ID_SILENT
        val priority = if (prominent) {
            NotificationCompat.PRIORITY_DEFAULT
        } else {
            NotificationCompat.PRIORITY_LOW
        }

        return NotificationCompat.Builder(ctx, channel)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setOngoing(true)
            // setOnlyAlertOnce(false) when prominent so re-posts after
            // app list change also surface as heads-up. The user can
            // still swipe the heads-up away or mute the channel.
            .setOnlyAlertOnce(!prominent)
            .setPriority(priority)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setStyle(NotificationCompat.DecoratedCustomViewStyle())
            .setCustomContentView(collapsed)
            .setCustomBigContentView(expanded)
            .setContentIntent(openLauncherPi)
            .build()
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
}
