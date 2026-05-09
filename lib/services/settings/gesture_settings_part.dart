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
  //
  // Per-app mode is stored as one of three explicit-override sets (off,
  // batch, allow) plus a `defaultNotifMode` setting that applies to any
  // package not in any of those sets. This lets the user say e.g. "block
  // every new app's notifications by default" without having to enumerate
  // every package that's ever installed.
  //
  // - Default 'allow' (the historical behavior): apps not in batch or off
  //   sets are permitted; allowApps is unused.
  // - Default 'off' / 'batch': any unknown app falls into that mode at
  //   runtime; allowApps is the explicit allowlist.

  /// Default mode for apps without an explicit override.
  /// Values: 'allow' | 'batch' | 'off'.
  String get defaultNotifMode =>
      (_box.get('defaultNotifMode') as String?) ?? 'allow';
  Future<void> setDefaultNotifMode(String mode) async {
    await _box.put('defaultNotifMode', mode);
    // Native layer needs the new policy immediately.
    await _syncNotifPolicy();
  }

  /// Explicit allowlist used when the default mode is 'batch' or 'off'.
  Set<String> get notifAllowApps {
    final raw = _box.get('notifAllowApps') as List<dynamic>?;
    if (raw == null) return {};
    return raw.map((e) => e.toString()).toSet();
  }
  Future<void> _setNotifAllowApps(Set<String> v) async {
    await _box.put('notifAllowApps', v.toList());
  }

  /// Returns the effective notification mode for [pkg]: 'allow' | 'batch' |
  /// 'off'. Checks explicit override sets first, then falls back to
  /// [defaultNotifMode].
  String notifModeForApp(String pkg) {
    if (notifOffApps.contains(pkg)) return 'off';
    if (batchApps.contains(pkg)) return 'batch';
    if (notifAllowApps.contains(pkg)) return 'allow';
    return defaultNotifMode;
  }

  /// Pushes the current per-app override sets + default to native so the
  /// notification listener can resolve any package's mode without consulting
  /// Flutter.
  Future<void> _syncNotifPolicy() async {
    await onNotifPolicyChanged?.call(
      defaultNotifMode,
      notifOffApps,
      notifAllowApps,
    );
  }

  /// Sets notification mode for a package, updating notifOffApps, batchApps,
  /// and notifAllowApps so that the chain in [notifModeForApp] resolves to
  /// [mode] for [pkg].
  Future<void> setNotifModeForApp(String pkg, String mode) async {
    final off = notifOffApps;
    final batch = batchApps;
    final allow = notifAllowApps;
    off.remove(pkg);
    batch.remove(pkg);
    allow.remove(pkg);
    // Only store an explicit override when the requested mode differs from
    // the current default — otherwise the override-less fallback reaches
    // the same answer and we keep the override sets minimal.
    if (mode != defaultNotifMode) {
      if (mode == 'off') off.add(pkg);
      if (mode == 'batch') batch.add(pkg);
      if (mode == 'allow') allow.add(pkg);
    }
    await _box.put('notifOffApps', off.toList());
    await setBatchApps(batch);
    await _setNotifAllowApps(allow);
    // Keep batch groups in sync: auto-add to first group when entering batch
    // mode (so the user immediately gets the Daywise behavior), and remove
    // from every group when leaving batch mode.
    final groups = batchGroups;
    var groupsChanged = false;
    if (mode == 'batch') {
      final inAnyGroup = groups.any((g) {
        final apps = ((g['apps'] as List?) ?? const []).map((e) => e.toString());
        return apps.contains(pkg);
      });
      if (!inAnyGroup && groups.isNotEmpty) {
        final firstApps = ((groups[0]['apps'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList();
        firstApps.add(pkg);
        groups[0]['apps'] = firstApps;
        groupsChanged = true;
      }
    } else {
      // Removing from batch (mode 'allow' or 'off'): scrub from all groups.
      for (final g in groups) {
        final apps = ((g['apps'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList();
        if (apps.remove(pkg)) {
          g['apps'] = apps;
          groupsChanged = true;
        }
      }
    }
    if (groupsChanged) {
      // Use the public setter so native sync fires.
      await setBatchGroups(groups);
    }
    // Push the full notif policy (default, off, allow) to native so its
    // listener can resolve any package's effective mode.
    await _syncNotifPolicy();
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

  Future<void> setBatchGroups(List<Map<String, dynamic>> groups) async {
    await _box.put('batchGroups', groups);
    await onBatchGroupsChanged?.call(groups);
  }

  Future<void> updateBatchGroupLastFire(String id, DateTime when) async {
    final groups = batchGroups;
    final i = groups.indexWhere((g) => g['id'] == id);
    if (i < 0) return;
    groups[i]['lastFireAt'] = when.millisecondsSinceEpoch;
    // Bypass the native-sync callback for this internal book-keeping write —
    // it doesn't change the schedule, only the last-fire bookkeeping that
    // native already tracks via SharedPreferences.
    await _box.put('batchGroups', groups);
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
