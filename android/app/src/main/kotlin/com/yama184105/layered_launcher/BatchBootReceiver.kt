package com.yama184105.layered_launcher

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * AlarmManager alarms are wiped when the device reboots or our package is
 * upgraded. This receiver re-registers every batch group's next alarm so
 * the scheduled deliveries still fire after a reboot.
 */
class BatchBootReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val a = intent.action ?: return
        if (a != Intent.ACTION_BOOT_COMPLETED &&
            a != Intent.ACTION_LOCKED_BOOT_COMPLETED &&
            a != Intent.ACTION_MY_PACKAGE_REPLACED &&
            a != "android.intent.action.QUICKBOOT_POWERON" &&
            a != "com.htc.intent.action.QUICKBOOT_POWERON"
        ) return
        Log.d("BatchBootReceiver", "Re-arming batch alarms after $a")
        BatchAlarms.rescheduleAll(context)
    }
}
