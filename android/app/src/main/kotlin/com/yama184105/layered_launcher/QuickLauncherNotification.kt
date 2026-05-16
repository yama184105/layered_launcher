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
 * Persistent notification(s) for quick app launch from the shade.
 *
 * Two presentation styles:
 *   - "consolidated": one notification with a custom expandable list
 *   - "perApp":       one notification per app, visually grouped via
 *                     setGroup()/setGroupSummary() so the shade still
 *                     shows them as a collapsible cluster
 *
 * Two channels back both styles so the user can pick between a quiet
 * (LOW) display and a prominent (DEFAULT) one that briefly shows as
 * heads-up.
 */
object QuickLauncherNotification {
    private const val TAG = "QuickLauncherNotif"

    const val CHANNEL_ID_SILENT = "quick_launcher"
    const val CHANNEL_ID_PROMINENT = "quick_launcher_prominent"

    /** Single consolidated notification id. */
    private const val NOTIFICATION_ID_CONSOLIDATED = 9001
    /** Group summary id when in per-app mode. */
    private const val NOTIFICATION_ID_SUMMARY = 9099
    /** Per-app notification id base (9100 + index). */
    private const val NOTIFICATION_ID_PER_APP_BASE = 9100

    /** Group key used to cluster per-app notifications in the shade. */
    private const val GROUP_KEY = "com.yama184105.layered_launcher.QUICK_LAUNCHER"

    /** Cap how many apps we expose. Determines per-app notification id
     *  range and consolidated row count. */
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

    /** Post or cancel the quick-launcher notification(s) based on
     *  [enabled] and [style] ('consolidated' or 'perApp'). Always
     *  cancels stale notifications from the other style/old app list
     *  first so we don't leave orphans in the shade. */
    fun update(
        ctx: Context,
        enabled: Boolean,
        apps: List<App>,
        prominent: Boolean = false,
        style: String = "consolidated",
    ) {
        cancelAll(ctx)
        if (!enabled) return
        try {
            ensureChannels(ctx)
            val capped = apps.take(MAX_APPS)
            if (style == "perApp") {
                postPerApp(ctx, capped, prominent)
            } else {
                postConsolidated(ctx, capped, prominent)
            }
        } catch (e: Exception) {
            Log.w(TAG, "failed to post quick launcher notification(s)", e)
        }
    }

    private fun cancelAll(ctx: Context) {
        try {
            val nm = NotificationManagerCompat.from(ctx)
            nm.cancel(NOTIFICATION_ID_CONSOLIDATED)
            nm.cancel(NOTIFICATION_ID_SUMMARY)
            for (i in 0 until MAX_APPS) {
                nm.cancel(NOTIFICATION_ID_PER_APP_BASE + i)
            }
        } catch (_: Exception) {}
    }

    // ── Consolidated style ──────────────────────────────────────────

    private fun postConsolidated(
        ctx: Context,
        apps: List<App>,
        prominent: Boolean,
    ) {
        val collapsed = RemoteViews(ctx.packageName, R.layout.quick_launcher_collapsed)

        val expanded = RemoteViews(ctx.packageName, R.layout.quick_launcher_expanded)
        expanded.removeAllViews(R.id.app_list)

        for ((index, app) in apps.withIndex()) {
            val row = buildConsolidatedRow(ctx, app, index) ?: continue
            expanded.addView(R.id.app_list, row)
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

        NotificationManagerCompat.from(ctx)
            .notify(NOTIFICATION_ID_CONSOLIDATED, notification)
    }

    private fun buildConsolidatedRow(ctx: Context, app: App, index: Int): RemoteViews? {
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

    // ── Per-app style ──────────────────────────────────────────────

    private fun postPerApp(
        ctx: Context,
        apps: List<App>,
        prominent: Boolean,
    ) {
        val (channel, priority) = channelAndPriority(prominent)
        val nm = NotificationManagerCompat.from(ctx)

        for ((index, app) in apps.withIndex()) {
            val launchIntent = ctx.packageManager.getLaunchIntentForPackage(app.packageName)
                ?: continue
            val tapIntent = Intent(launchIntent).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            }
            val tapPi = PendingIntent.getActivity(
                ctx,
                20000 + index,
                tapIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )

            val n = NotificationCompat.Builder(ctx, channel)
                .setSmallIcon(R.mipmap.ic_launcher)
                .setOngoing(true)
                .setOnlyAlertOnce(!prominent)
                .setPriority(priority)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                .setContentTitle(app.label)
                .setContentText("タップで起動")
                .setGroup(GROUP_KEY)
                .setContentIntent(tapPi)
                .build()
            nm.notify(NOTIFICATION_ID_PER_APP_BASE + index, n)
        }

        // Summary: required on Android 7+ when using setGroup so the
        // shade renders them as a single collapsible cluster.
        val summary = NotificationCompat.Builder(ctx, channel)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setPriority(priority)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setContentTitle("Layered Launcher")
            .setContentText("${apps.size} 件のクイック起動")
            .setGroup(GROUP_KEY)
            .setGroupSummary(true)
            .setContentIntent(openLauncherPendingIntent(ctx))
            .build()
        nm.notify(NOTIFICATION_ID_SUMMARY, summary)
    }

    // ── Helpers ───────────────────────────────────────────────────

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
