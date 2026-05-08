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
    // Push the new OFF list to the native notification listener so it
    // actually starts dismissing those apps' notifications.
    await onOffPackagesChanged?.call(off);
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

  // ── Batch Groups ───────────────────────────────────────────────────────────
  // A batch group bundles a subset of the batch-mode apps with a delivery
  // schedule. Three schedule types are supported:
  //   - 'interval'   : every N minutes
  //   - 'fixed'      : at a list of specific times of day
  //   - 'dailyOnce'  : at a single time once per day
  // Each group also has a weekday filter (default: every day).
  //
  // Stored shape (List<Map<String, dynamic>>):
  //   {
  //     'id': String,                        // stable UUID-ish
  //     'name': String,                      // user-facing
  //     'apps': List<String>,                // package names
  //     'scheduleType': 'interval'|'fixed'|'dailyOnce',
  //     'intervalMinutes': int,              // for 'interval'
  //     'times': List<{'h': int, 'm': int}>, // for 'fixed'
  //     'time': {'h': int, 'm': int},        // for 'dailyOnce'
  //     'weekdays': List<int>,               // 1=Mon..7=Sun (Dart weekday)
  //     'lastFireAt': int,                   // epochMs, anti-double-fire
  //   }

  List<Map<String, dynamic>> get batchGroups {
    final raw = _box.get('batchGroups') as List?;
    if (raw == null) return [];
    return raw
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<void> setBatchGroups(List<Map<String, dynamic>> groups) =>
      _box.put('batchGroups', groups);

  Future<void> updateBatchGroupLastFire(String id, DateTime when) async {
    final groups = batchGroups;
    final i = groups.indexWhere((g) => g['id'] == id);
    if (i < 0) return;
    groups[i]['lastFireAt'] = when.millisecondsSinceEpoch;
    await setBatchGroups(groups);
  }

  /// Initial migration from the legacy single-interval batch model. Runs once.
  /// All existing batch apps (if any) move into a single "デフォルト" group
  /// that defaults to every-4-hours, every weekday.
  Future<void> migrateBatchGroupsIfNeeded() async {
    if (_box.containsKey('batchGroups')) return;
    final apps = batchApps.toList();
    final defaultGroup = <String, dynamic>{
      'id': 'default-${DateTime.now().millisecondsSinceEpoch}',
      'name': 'デフォルト',
      'apps': apps,
      'scheduleType': 'interval',
      'intervalMinutes': 240,
      'weekdays': const <int>[1, 2, 3, 4, 5, 6, 7],
      'lastFireAt': 0,
    };
    await _box.put('batchGroups', [defaultGroup]);
    // Drop the now-unused legacy interval setting.
    await _box.delete('batchIntervalMinutes');
  }

  /// Generates a fresh group id for new groups created from the UI. Not a
  /// real UUID — millisecond timestamp is plenty since we only need it
  /// stable within this device.
  static String newBatchGroupId() => 'g-${DateTime.now().microsecondsSinceEpoch}';
}
