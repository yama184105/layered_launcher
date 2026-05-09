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
        /** Explicit allow-overrides used when KEY_DEFAULT_MODE is 'off' or
         *  'batch'. Apps in this set bypass the default. */
        const val KEY_ALLOW_PACKAGES = "allow_packages"
        /** 'allow' | 'batch' | 'off' — default mode for apps without an
         *  explicit override. Defaults to 'allow' for backward compat. */
        const val KEY_DEFAULT_MODE = "default_mode"
        const val KEY_BATCH_GROUPS = "batch_groups"
        /** History log of OFF-blocked notifications, JSON array of
         *  { pkg, title, text, blockedAt }. Capped to MAX_BLOCKED_HISTORY. */
        const val KEY_BLOCKED_HISTORY = "blocked_history"

        /** Per-group queue of intercepted notification payloads, persisted
         *  so they survive Flutter being killed and the device rebooting. */
        fun savedNotifsKeyFor(groupId: String): String = "saved_notifs_$groupId"

        val counts = mutableMapOf<String, Int>()
        var instance: NotificationService? = null

        private const val TAG = "NotificationService"
        /** Cap per-group queue length to keep SharedPreferences from
         *  growing unbounded if the user never opens the app. */
        private const val MAX_SAVED_PER_GROUP = 50
        /** Cap for the OFF-blocked history shown to the user. Older
         *  entries are trimmed when the cap is exceeded. */
        private const val MAX_BLOCKED_HISTORY = 500
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

    /** Returns the id of the first batch group regardless of contents — the
     *  fallback target for apps that get caught by a 'batch' default mode. */
    private fun firstBatchGroupId(): String? {
        return try {
            val sp = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val raw = sp.getString(KEY_BATCH_GROUPS, null) ?: return null
            val arr = JSONArray(raw)
            if (arr.length() == 0) return null
            arr.optJSONObject(0)?.optString("id")
        } catch (_: Exception) {
            null
        }
    }

    /** Public for MainActivity's setNotifPolicy sweep. Resolves a package's
     *  effective mode using the same priority chain as Flutter's
     *  notifModeForApp:
     *    explicit OFF > batch group membership > explicit allow > default. */
    fun resolveModeFor(pkg: String): String {
        return try {
            val sp = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val off = sp.getStringSet(KEY_OFF_PACKAGES, emptySet()) ?: emptySet()
            if (off.contains(pkg)) return "off"
            if (groupIdForPackage(pkg) != null) return "batch"
            val allow = sp.getStringSet(KEY_ALLOW_PACKAGES, emptySet()) ?: emptySet()
            if (allow.contains(pkg)) return "allow"
            sp.getString(KEY_DEFAULT_MODE, "allow") ?: "allow"
        } catch (_: Exception) {
            "allow"
        }
    }

    /** Append an entry to the OFF-blocked history log. Trims oldest
     *  entries when the cap is exceeded. */
    private fun appendBlockedHistory(sbn: StatusBarNotification) {
        try {
            val sp = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val existing = sp.getString(KEY_BLOCKED_HISTORY, null)
            val arr = if (existing != null) JSONArray(existing) else JSONArray()
            val ex = sbn.notification.extras
            val title = ex.getCharSequence(Notification.EXTRA_TITLE)?.toString() ?: ""
            val text = ex.getCharSequence(Notification.EXTRA_TEXT)?.toString() ?: ""
            val bigText = ex.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString()
            val effectiveText = if (!bigText.isNullOrEmpty()) bigText else text
            arr.put(JSONObject().apply {
                put("pkg", sbn.packageName)
                put("title", title)
                put("text", effectiveText)
                put("blockedAt", System.currentTimeMillis())
            })
            while (arr.length() > MAX_BLOCKED_HISTORY) arr.remove(0)
            sp.edit().putString(KEY_BLOCKED_HISTORY, arr.toString()).apply()
        } catch (e: Exception) {
            Log.w(TAG, "appendBlockedHistory failed", e)
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

    /** Apply the resolved mode for [sbn]. Single source of policy logic
     *  used by both onListenerConnected (snapshot replay) and
     *  onNotificationPosted (live event). */
    private fun handleSbn(sbn: StatusBarNotification) {
        if (sbn.isOngoing) return
        val pkg = sbn.packageName
        val mode = resolveModeFor(pkg)
        when (mode) {
            "off" -> {
                appendBlockedHistory(sbn)
                try { cancelNotification(sbn.key) } catch (_: Exception) {}
            }
            "batch" -> {
                // Pick the explicit group if any, otherwise the first one
                // (the user-defined fallback target for default-batch).
                val groupId = groupIdForPackage(pkg) ?: firstBatchGroupId()
                if (groupId == null) {
                    // Default 'batch' but no groups exist — degrade to allow
                    // so we never silently lose a notification.
                    counts[pkg] = (counts[pkg] ?: 0) + 1
                    return
                }
                saveNotification(groupId, sbn)
                try { cancelNotification(sbn.key) } catch (_: Exception) {}
            }
            else -> counts[pkg] = (counts[pkg] ?: 0) + 1
        }
    }

    override fun onListenerConnected() {
        instance = this
        counts.clear()
        try {
            for (sbn in activeNotifications) handleSbn(sbn)
        } catch (_: Exception) {}
    }

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        handleSbn(sbn)
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification) {
        val c = (counts[sbn.packageName] ?: 1) - 1
        if (c <= 0) counts.remove(sbn.packageName) else counts[sbn.packageName] = c
    }

    override fun onListenerDisconnected() {
        instance = null
    }
}
