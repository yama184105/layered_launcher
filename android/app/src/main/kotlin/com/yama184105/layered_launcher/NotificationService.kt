package com.yama184105.layered_launcher

import android.app.Notification
import android.content.Context
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject

class NotificationService : NotificationListenerService() {
    companion object {
        const val PREFS_NAME = "notif_filter"
        const val KEY_OFF_PACKAGES = "off_packages"
        const val KEY_BATCH_GROUPS = "batch_groups"

        /** Per-group queue of intercepted notification payloads, persisted
         *  so they survive Flutter being killed and the device rebooting. */
        fun savedNotifsKeyFor(groupId: String): String = "saved_notifs_$groupId"

        val counts = mutableMapOf<String, Int>()
        var instance: NotificationService? = null

        private const val TAG = "NotificationService"
        /** Cap per-group queue length to keep SharedPreferences from
         *  growing unbounded if the user never opens the app. */
        private const val MAX_SAVED_PER_GROUP = 50
    }

    private fun isOffPackage(pkg: String): Boolean {
        return try {
            val sp = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            sp.getStringSet(KEY_OFF_PACKAGES, emptySet())?.contains(pkg) == true
        } catch (_: Exception) {
            false
        }
    }

    /** Returns the id of the first batch group containing [pkg], or null
     *  if [pkg] isn't part of any group. */
    private fun groupIdForPackage(pkg: String): String? {
        return try {
            val sp = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val raw = sp.getString(KEY_BATCH_GROUPS, null) ?: return null
            val arr = JSONArray(raw)
            for (i in 0 until arr.length()) {
                val g = arr.optJSONObject(i) ?: continue
                val apps = g.optJSONArray("apps") ?: continue
                for (j in 0 until apps.length()) {
                    if (apps.optString(j) == pkg) {
                        return g.optString("id")
                    }
                }
            }
            null
        } catch (_: Exception) {
            null
        }
    }

    /** Capture title/text/etc. and append to the group's queue. */
    private fun saveNotification(groupId: String, sbn: StatusBarNotification) {
        try {
            val sp = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val key = savedNotifsKeyFor(groupId)
            val existing = sp.getString(key, null)
            val arr = if (existing != null) JSONArray(existing) else JSONArray()

            val ex = sbn.notification.extras
            val title = ex.getCharSequence(Notification.EXTRA_TITLE)?.toString() ?: ""
            val text = ex.getCharSequence(Notification.EXTRA_TEXT)?.toString() ?: ""
            // EXTRA_BIG_TEXT is sometimes longer / more useful than EXTRA_TEXT.
            val bigText = ex.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString()
            val effectiveText = if (!bigText.isNullOrEmpty()) bigText else text

            val obj = JSONObject().apply {
                put("pkg", sbn.packageName)
                put("title", title)
                put("text", effectiveText)
                put("postedAt", sbn.postTime)
            }
            arr.put(obj)

            // Trim oldest if we're past the cap.
            while (arr.length() > MAX_SAVED_PER_GROUP) {
                arr.remove(0)
            }
            sp.edit().putString(key, arr.toString()).apply()
        } catch (e: Exception) {
            Log.w(TAG, "saveNotification failed", e)
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
                val gid = groupIdForPackage(sbn.packageName)
                if (gid != null) {
                    saveNotification(gid, sbn)
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
        // Daywise-style batch capture: if this app belongs to a batch group,
        // save its content for replay at the group's scheduled time and
        // dismiss the live notification so the user isn't interrupted now.
        val groupId = groupIdForPackage(sbn.packageName)
        if (groupId != null && !sbn.isOngoing) {
            saveNotification(groupId, sbn)
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
