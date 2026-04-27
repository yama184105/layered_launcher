package com.example.layered_launcher

import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification

class NotificationService : NotificationListenerService() {
    companion object {
        val counts = mutableMapOf<String, Int>()
        var instance: NotificationService? = null
    }

    override fun onListenerConnected() {
        instance = this
        counts.clear()
        try {
            for (sbn in activeNotifications) {
                if (!sbn.isOngoing) counts[sbn.packageName] = (counts[sbn.packageName] ?: 0) + 1
            }
        } catch (_: Exception) {}
    }

    override fun onNotificationPosted(sbn: StatusBarNotification) {
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
