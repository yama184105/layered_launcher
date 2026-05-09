import 'dart:async';
import 'package:flutter/services.dart';

class NativeService {
  static const _channel =
      MethodChannel('com.yama184105.layered_launcher/native');

  // Singleton: only one instance so setMethodCallHandler is never overwritten.
  static final NativeService _instance = NativeService._internal();
  factory NativeService() => _instance;

  final _homePressedController = StreamController<void>.broadcast();
  Stream<void> get onHomePressed => _homePressedController.stream;

  NativeService._internal() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onHomePressed') {
        _homePressedController.add(null);
      }
    });
  }

  void dispose() {
    // Do not close the stream — singleton lives for the app lifetime.
  }

  Future<int> getBatteryLevel() async {
    try {
      final result = await _channel.invokeMethod<int>('getBatteryLevel');
      return result ?? -1;
    } catch (_) {
      return -1;
    }
  }

  Future<int> getTodayScreenTime() async {
    try {
      final result =
          await _channel.invokeMethod<int>('getTodayScreenTime');
      return result ?? -1;
    } catch (_) {
      return -1;
    }
  }

  Future<List<Map<String, dynamic>>> getCalendarEvents() async {
    try {
      final result = await _channel.invokeMethod('getCalendarEvents');
      if (result == null) return [];
      return (result as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<Map<String, int>> getNotificationCounts() async {
    try {
      final result =
          await _channel.invokeMethod('getNotificationCounts');
      if (result == null) return {};
      return (result as Map)
          .map((k, v) => MapEntry(k.toString(), (v as num).toInt()));
    } catch (_) {
      return {};
    }
  }

  /// Push the current set of OFF-mode packages to the native side so that
  /// NotificationService can dismiss new notifications from those apps and
  /// our SharedPreferences-backed list survives Flutter being killed.
  Future<void> setOffPackages(Set<String> packages) async {
    try {
      await _channel.invokeMethod('setOffPackages', packages.toList());
    } catch (_) {}
  }

  /// Push the full batch-group config to the native side. The native code
  /// persists it (so NotificationService can intercept matching apps even
  /// when Flutter is dead) and arms an AlarmManager wake-up for each
  /// group's next delivery time so scheduled batches keep firing during
  /// Doze and after device reboots.
  Future<void> setBatchGroups(List<Map<String, dynamic>> groups) async {
    try {
      await _channel.invokeMethod('setBatchGroups', groups);
    } catch (_) {}
  }

  /// Android 12+: returns whether SCHEDULE_EXACT_ALARM is granted. False
  /// means batch alarms fall back to the inexact "while idle" path
  /// (~9-15 min window during Doze).
  Future<bool> canScheduleExactAlarms() async {
    try {
      final v = await _channel.invokeMethod<bool>('canScheduleExactAlarms');
      return v ?? true;
    } catch (_) {
      return true;
    }
  }

  Future<void> openExactAlarmSettings() async {
    try {
      await _channel.invokeMethod('openExactAlarmSettings');
    } catch (_) {}
  }

  /// Returns the OFF-blocked notification history captured by
  /// NotificationService. Each entry: `{pkg, title, text, blockedAt}`
  /// (epochMs). Order is oldest-first; the UI flips it for display.
  Future<List<Map<String, dynamic>>> getBlockedHistory() async {
    try {
      final raw = await _channel.invokeMethod('getBlockedHistory');
      if (raw == null) return [];
      return (raw as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> clearBlockedHistory() async {
    try {
      await _channel.invokeMethod('clearBlockedHistory');
    } catch (_) {}
  }

  /// Returns one entry per batch group with its pending captured items
  /// (queued for delivery at the group's next fire time). Each entry:
  /// `{id, name, scheduleType, nextFireMs, items: [{pkg, title, text, postedAt}]}`.
  Future<List<Map<String, dynamic>>> getBatchQueues() async {
    try {
      final raw = await _channel.invokeMethod('getBatchQueues');
      if (raw == null) return [];
      return (raw as List).map((e) {
        final m = Map<String, dynamic>.from(e as Map);
        m['items'] = (m['items'] as List? ?? const [])
            .map((it) => Map<String, dynamic>.from(it as Map))
            .toList();
        return m;
      }).toList();
    } catch (_) {
      return [];
    }
  }

  Future<bool> isNotificationServiceEnabled() async {
    try {
      final result = await _channel
          .invokeMethod<bool>('isNotificationServiceEnabled');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> openNotificationAccessSettings() async {
    try {
      await _channel.invokeMethod('openNotificationAccessSettings');
    } catch (_) {}
  }

  Future<bool> lockScreen() async {
    try {
      final result =
          await _channel.invokeMethod<bool>('lockScreen');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> isDeviceAdminEnabled() async {
    try {
      final result =
          await _channel.invokeMethod<bool>('isDeviceAdminEnabled');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> openDeviceAdminSettings() async {
    try {
      await _channel.invokeMethod('openDeviceAdminSettings');
    } catch (_) {}
  }

  Future<bool> isUsageStatsPermissionGranted() async {
    try {
      final result = await _channel
          .invokeMethod<bool>('isUsageStatsPermissionGranted');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> openUsageStatsSettings() async {
    try {
      await _channel.invokeMethod('openUsageStatsSettings');
    } catch (_) {}
  }

  Future<Map<String, int>> getUsageStats30Days() async {
    try {
      final result =
          await _channel.invokeMethod('getUsageStats30Days');
      if (result == null) return {};
      return (result as Map)
          .map((k, v) => MapEntry(k.toString(), (v as num).toInt()));
    } catch (_) {
      return {};
    }
  }

  /// Returns a map of packageName -> lastTimeUsed (epoch ms) over the past
  /// 30 days. Empty map if the usage-stats permission is not granted.
  Future<Map<String, int>> getLastTimeUsedMap() async {
    try {
      final result = await _channel.invokeMethod('getLastTimeUsedMap');
      if (result == null) return {};
      return (result as Map)
          .map((k, v) => MapEntry(k.toString(), (v as num).toInt()));
    } catch (_) {
      return {};
    }
  }

  Future<Map<String, double>?> getLastKnownLocation() async {
    try {
      final result =
          await _channel.invokeMethod('getLastKnownLocation');
      if (result == null) return null;
      final m = Map<String, dynamic>.from(result as Map);
      return {
        'lat': (m['lat'] as num).toDouble(),
        'lon': (m['lon'] as num).toDouble(),
      };
    } catch (_) {
      return null;
    }
  }

  Future<void> openDial() async {
    try { await _channel.invokeMethod('openDial'); } catch (_) {}
  }

  Future<void> openCamera() async {
    try { await _channel.invokeMethod('openCamera'); } catch (_) {}
  }

  Future<void> openAlarmClock() async {
    try { await _channel.invokeMethod('openAlarmClock'); } catch (_) {}
  }

  Future<void> openDeviceSettings() async {
    try { await _channel.invokeMethod('openDeviceSettings'); } catch (_) {}
  }

  Future<void> uninstallApp(String packageName) async {
    try {
      await _channel.invokeMethod('uninstallApp', {'packageName': packageName});
    } catch (_) {}
  }

  Future<bool> isCharging() async {
    try {
      final result = await _channel.invokeMethod<bool>('isCharging');
      return result ?? false;
    } catch (_) { return false; }
  }

  Future<void> sendEmail({required String to, required String subject, required String body}) async {
    try {
      await _channel.invokeMethod('sendEmail', {'to': to, 'subject': subject, 'body': body});
    } catch (_) {}
  }

  Future<void> expandNotificationPanel() async {
    try { await _channel.invokeMethod('expandNotificationPanel'); } catch (_) {}
  }
}
