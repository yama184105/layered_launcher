package com.yama184105.layered_launcher

import android.app.ActivityOptions
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
 * just shows "Layered Launcher". Expanding reveals one row per favorite
 * app, where tapping the name launches normally and tapping the ▢▢ icon
 * launches in split-screen using FLAG_ACTIVITY_LAUNCH_ADJACENT.
 *
 * Posted from Flutter via MainActivity.setQuickLauncherConfig and from
 * QuickLauncherBootReceiver after a device reboot so the notification
 * survives without needing a foreground service.
 */
object QuickLauncherNotification {
    private const val TAG = "QuickLauncherNotif"
    const val CHANNEL_ID = "quick_launcher"
    const val NOTIFICATION_ID = 9001

    /** Cap how many apps we put in the expanded RemoteViews. The
     *  notification panel clips long lists anyway and each row keeps a
     *  PendingIntent alive, so we limit to a sane number. */
    private const val MAX_APPS = 12

    data class App(val packageName: String, val label: String)

    fun ensureChannel(ctx: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (nm.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "クイック起動",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "通知シェードからアプリを素早く起動するための常駐通知"
            setShowBadge(false)
            enableLights(false)
            enableVibration(false)
            setSound(null, null)
        }
        nm.createNotificationChannel(channel)
    }

    /** Post or cancel the persistent notification based on [enabled]. */
    fun update(ctx: Context, enabled: Boolean, apps: List<App>) {
        if (!enabled) {
            try {
                NotificationManagerCompat.from(ctx).cancel(NOTIFICATION_ID)
            } catch (_: Exception) {}
            return
        }
        try {
            ensureChannel(ctx)
            val notification = buildNotification(ctx, apps.take(MAX_APPS))
            NotificationManagerCompat.from(ctx).notify(NOTIFICATION_ID, notification)
        } catch (e: Exception) {
            Log.w(TAG, "failed to post quick launcher notification", e)
        }
    }

    private fun buildNotification(
        ctx: Context,
        apps: List<App>,
    ): android.app.Notification {
        val collapsed = RemoteViews(ctx.packageName, R.layout.quick_launcher_collapsed)

        val expanded = RemoteViews(ctx.packageName, R.layout.quick_launcher_expanded)
        // Remove any rows left over from a previous post (RemoteViews caches
        // child views per id). Defensive — Android usually rebuilds from the
        // layout xml on each notify but be explicit.
        expanded.removeAllViews(R.id.app_list)

        for ((index, app) in apps.withIndex()) {
            val row = buildRow(ctx, app, index) ?: continue
            expanded.addView(R.id.app_list, row)
        }

        // Tap the notification body itself opens our launcher app — a
        // fallback in case the user wants the full Layered Launcher UI.
        val openLauncherIntent = Intent(ctx, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT
        }
        val openLauncherPi = PendingIntent.getActivity(
            ctx,
            0,
            openLauncherIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        return NotificationCompat.Builder(ctx, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
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

        // Normal launch: just FLAG_ACTIVITY_NEW_TASK so it opens fullscreen
        // (or in whatever windowing mode the user already has). Use unique
        // request codes per row so PendingIntents don't collide.
        val normalIntent = Intent(launchIntent).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK
        }
        val normalPi = PendingIntent.getActivity(
            ctx,
            10000 + index * 2,
            normalIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        row.setOnClickPendingIntent(R.id.app_name, normalPi)

        // Split-screen launch. The FLAG_ACTIVITY_LAUNCH_ADJACENT alone
        // often fails when launching from a notification because the
        // caller (system UI / launcher) isn't itself in multi-window
        // mode. We additionally pass ActivityOptions with explicit
        // windowing mode = MULTI_WINDOW (5) via reflection — that hidden
        // attribute is the same one the system shell uses for split.
        // MULTIPLE_TASK ensures we get a fresh window instance.
        val splitIntent = Intent(launchIntent).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_LAUNCH_ADJACENT or
                Intent.FLAG_ACTIVITY_MULTIPLE_TASK or
                Intent.FLAG_ACTIVITY_NEW_DOCUMENT
        }
        val splitPi = makeSplitPendingIntent(
            ctx,
            splitIntent,
            10001 + index * 2,
        )
        row.setOnClickPendingIntent(R.id.split_button, splitPi)

        return row
    }

    /** Build a PendingIntent that asks the system to launch [splitIntent]
     *  in split-screen / multi-window mode. On Android 12+ we attach
     *  ActivityOptions with WINDOWING_MODE_MULTI_WINDOW (=5) via
     *  reflection; this is the same mechanism Samsung/Lenovo task
     *  switchers use and is required for split-screen to actually take
     *  effect when launched from a notification (FLAG_ACTIVITY_LAUNCH_ADJACENT
     *  alone falls back to single-window if the caller isn't already in
     *  multi-window). Falls back to a flag-only PendingIntent on older
     *  Android or if reflection fails. */
    private fun makeSplitPendingIntent(
        ctx: Context,
        splitIntent: Intent,
        requestCode: Int,
    ): PendingIntent {
        val piFlags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        val optsBundle = buildSplitOptionsBundle()
        return if (optsBundle != null) {
            PendingIntent.getActivity(ctx, requestCode, splitIntent, piFlags, optsBundle)
        } else {
            PendingIntent.getActivity(ctx, requestCode, splitIntent, piFlags)
        }
    }

    private fun buildSplitOptionsBundle(): android.os.Bundle? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return null
        return try {
            val opts = ActivityOptions.makeBasic()
            // WINDOWING_MODE_MULTI_WINDOW = 5 in WindowConfiguration.
            // The setLaunchWindowingMode method is @SystemApi but
            // accessible via reflection on most builds.
            val method = opts.javaClass.getMethod(
                "setLaunchWindowingMode",
                Int::class.javaPrimitiveType,
            )
            method.invoke(opts, 5)
            opts.toBundle()
        } catch (_: Exception) {
            null
        }
    }
}
