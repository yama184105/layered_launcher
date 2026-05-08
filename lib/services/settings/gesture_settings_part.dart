part of '../settings_service.dart';

extension GestureSettings on SettingsService {
  // ── Gesture Settings ───────────────────────────────────────────────────────

  /// Package name, 'screen_off', or null
  String? get gestureUpApp {
    final v = _box.get('gestureUpApp') as String?;
    return v == 'open_keyboard' ? null : v;
  }
  Future<void> setGestureUpApp(String? v) async {
    if (v == null) {
      await _box.delete('gestureUpApp');
    } else {
      await _box.put('gestureUpApp', v);
    }
  }

  String? get gestureDownApp {
    final v = _box.get('gestureDownApp') as String?;
    return v == 'open_keyboard' ? null : v;
  }
  Future<void> setGestureDownApp(String? v) async {
    if (v == null) {
      await _box.delete('gestureDownApp');
    } else {
      await _box.put('gestureDownApp', v);
    }
  }

  String? get gestureDoubleTapApp {
    final v = (_box.get('gestureDoubleTapApp') as String?) ?? 'screen_off';
    return v == 'open_keyboard' ? null : v;
  }
  Future<void> setGestureDoubleTapApp(String? v) async {
    if (v == null) {
      await _box.delete('gestureDoubleTapApp');
    } else {
      await _box.put('gestureDoubleTapApp', v);
    }
  }

  // ── Mindful Delay ──────────────────────────────────────────────────────────

  int get mindfulDelaySeconds {
    final v = _box.get('mindfulDelaySeconds') as int?;
    return v ?? 5;
  }

  Future<void> setMindfulDelaySeconds(int v) =>
      _box.put('mindfulDelaySeconds', v);

  // ── Mindful Delay Global ───────────────────────────────────────────────────
  /// Global on/off for mindful delay feature
  bool get mindfulDelayEnabled =>
      (_box.get('mindfulDelayEnabled') as bool?) ?? false;
  Future<void> setMindfulDelayEnabled(bool v) =>
      _box.put('mindfulDelayEnabled', v);

  /// Values: 'launch' | 'confirm' | 'cancel'
  String get mindfulDelayAction =>
      (_box.get('mindfulDelayAction') as String?) ?? 'launch';
  Future<void> setMindfulDelayAction(String v) =>
      _box.put('mindfulDelayAction', v);

  // ── Batch Notifications ────────────────────────────────────────────────────

  Set<String> get batchApps {
    final raw = _box.get('batchApps') as List<dynamic>?;
    if (raw == null) return {};
    return raw.map((e) => e.toString()).toSet();
  }

  Future<void> setBatchApps(Set<String> apps) =>
      _box.put('batchApps', apps.toList());

  Future<void> toggleBatchApp(String packageName) async {
    final current = batchApps;
    if (current.contains(packageName)) {
      current.remove(packageName);
    } else {
      current.add(packageName);
    }
    await setBatchApps(current);
  }

  /// Values: 30 | 60 | 120 | 240 (minutes)
  int get batchIntervalMinutes {
    final v = _box.get('batchIntervalMinutes') as int?;
    return v ?? 60;
  }

  Future<void> setBatchIntervalMinutes(int v) =>
      _box.put('batchIntervalMinutes', v);

  // ── Notification Mode ──────────────────────────────────────────────────────

  /// Returns the notification mode for a package: 'allow' | 'batch' | 'off'
  String notifModeForApp(String pkg) {
    if (notifOffApps.contains(pkg)) return 'off';
    if (batchApps.contains(pkg)) return 'batch';
    return 'allow';
  }

  /// Sets notification mode for a package, updating notifOffApps and batchApps.
  Future<void> setNotifModeForApp(String pkg, String mode) async {
    final off = notifOffApps;
    final batch = batchApps;
    off.remove(pkg);
    batch.remove(pkg);
    if (mode == 'off') off.add(pkg);
    if (mode == 'batch') batch.add(pkg);
    await _box.put('notifOffApps', off.toList());
    await setBatchApps(batch);
    // The user just opted into a feature that needs notification access, so
    // un-defer the prompt so the home screen can ask again on next launch.
    if (mode == 'batch') {
      await setNotifPermDeferred(false);
    }
  }

  Set<String> get notifOffApps {
    final raw = _box.get('notifOffApps') as List<dynamic>?;
    if (raw == null) return {};
    return raw.map((e) => e.toString()).toSet();
  }
}
