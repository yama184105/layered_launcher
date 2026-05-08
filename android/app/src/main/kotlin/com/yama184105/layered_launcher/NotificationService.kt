package com.yama184105.layered_launcher

import android.content.Context
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification

class NotificationService : NotificationListenerService() {
    companion object {
        const val PREFS_NAME = "notif_filter"
        const val KEY_OFF_PACKAGES = "off_packages"

        val counts = mutableMapOf<String, Int>()
        var instance: NotificationService? = null
    }

    private fun isOffPackage(pkg: String): Boolean {
        return try {
            val sp = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            sp.getStringSet(KEY_OFF_PACKAGES, emptySet())?.contains(pkg) == true
        } catch (_: Exception) {
            false
        }
    }

    override fun onListenerConnected() {
        instance = this
        counts.clear()
        try {
            for (sbn in activeNotifications) {
                if (sbn.isOngoing) continue
                if (isOffPackage(sbn.packageName)) {
                    // Carry over enforcement to notifications that already
                    // existed when our listener connected.
                    try { cancelNotification(sbn.key) } catch (_: Exception) {}
                    continue
                }
                counts[sbn.packageName] = (counts[sbn.packageName] ?: 0) + 1
            }
        } catch (_: Exception) {}
    }

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        // Off mode: dismiss immediately. The notification flashes very briefly
        // (between post and cancel) but is then gone from the shade.
        if (isOffPackage(sbn.packageName)) {
            try { cancelNotification(sbn.key) } catch (_: Exception) {}
            return
        }
        if (!sbn.isOngoing) counts[sbn.packageName] = (counts[sbn.packageName] ?: 0) + 1
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification) {
        val c = (counts[sbn.packageName] ?: 1) - 1
        if (c <= 0) counts.remove(sbn.packageName) else counts[sbn.packageName] = c
    }

    override fun onListenerDisconnected() {
        instance = null
    }
}
