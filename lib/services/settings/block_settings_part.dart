part of '../settings_service.dart';

extension BlockSettings on SettingsService {
  // ── Legacy Lock Mode (kept for backward compat) ────────────────────────────
  bool get lockModeEnabled => (_box.get('lockMode') as bool?) ?? false;
  Future<void> setLockMode(bool v) => _box.put('lockMode', v);

  // ── Strict Sub-modes ─────────────────────────────────────────────────────
  // Keys: 'floorMove', 'animation', 'submode', 'emergency', 'shortcut'
  static const strictSubKeys = ['floorMove', 'animation', 'submode', 'emergency', 'shortcut'];
  static const strictSubLabels = {
    'floorMove': 'アプリフロア移動ロック',
    'animation': 'アニメーション速度ロック',
    'submode': 'サブモード設定ロック',
    'emergency': '緊急使用設定ロック',
    'shortcut': 'ショートカットアプリ変更ロック',
  };
  static const strictSubDescriptions = {
    'floorMove': '選択したアプリのフロア移動を制限します',
    'animation': 'アニメーション速度の変更を制限します',
    'submode': 'ストリクトモードの各設定の変更自体を制限します',
    'emergency': '緊急モードの使用制限設定の変更を制限します',
    'shortcut': 'ホーム画面のショートカットアプリの変更を制限します',
  };

  bool strictSubEnabled(String key) =>
      (_box.get('strict_${key}_enabled') as bool?) ?? false;
  Future<void> setStrictSubEnabled(String key, bool v) =>
      _box.put('strict_${key}_enabled', v);

  /// 'block' = completely blocked, 'timer' = wait for timer
  String strictSubType(String key) =>
      (_box.get('strict_${key}_type') as String?) ?? 'timer';
  Future<void> setStrictSubType(String key, String v) =>
      _box.put('strict_${key}_type', v);

  int strictSubTimerMinutes(String key) =>
      (_box.get('strict_${key}_timer') as int?) ?? 3;
  Future<void> setStrictSubTimerMinutes(String key, int v) =>
      _box.put('strict_${key}_timer', v);

  bool isStrictSubCooldownActive(String key) {
    final ms = _box.get('strict_${key}_cooldownUntil') as int?;
    if (ms == null) return false;
    return DateTime.fromMillisecondsSinceEpoch(ms).isAfter(DateTime.now());
  }

  Duration? strictSubCooldownRemaining(String key) {
    final ms = _box.get('strict_${key}_cooldownUntil') as int?;
    if (ms == null) return null;
    final rem = DateTime.fromMillisecondsSinceEpoch(ms).difference(DateTime.now());
    return rem.isNegative ? null : rem;
  }

  Future<void> startStrictSubCooldown(String key) async {
    await _box.put('strict_${key}_cooldownUntil',
        DateTime.now().add(const Duration(seconds: 10)).millisecondsSinceEpoch);
  }

  // ── Floor-move locked apps (per-app selection) ────────────────────────────
  List<String> get floorMoveLockedApps {
    final raw = (_box.get('floorMoveLockedApps') as List?) ?? [];
    return List<String>.from(raw);
  }

  Future<void> setFloorMoveLockedApps(List<String> v) =>
      _box.put('floorMoveLockedApps', v);

  bool isFloorMoveLocked(String packageName) {
    if (!strictSubEnabled('floorMove')) return false;
    final locked = floorMoveLockedApps;
    // If no apps selected, lock applies to ALL (backward compat)
    if (locked.isEmpty) return true;
    return locked.contains(packageName);
  }

  // ── Emergency-lock per-app selection ─────────────────────────────────────
  List<String> get emergencyLockedApps {
    final raw = (_box.get('emergencyLockedApps') as List?) ?? [];
    return List<String>.from(raw);
  }

  Future<void> setEmergencyLockedApps(List<String> v) =>
      _box.put('emergencyLockedApps', v);

  bool isEmergencyLocked(String packageName) {
    if (!strictSubEnabled('emergency')) return false;
    final locked = emergencyLockedApps;
    if (locked.isEmpty) return true;
    return locked.contains(packageName);
  }

  // ── Emergency Apps (unified: registration, quick access, detail toggle) ───
  /// Single source of truth for emergency-designated apps.
  /// Used by: app detail toggle, settings registration list, emergency button.
  List<String> getEmergencyApps() {
    final raw = (_box.get('emergencyApps') as List?) ?? [];
    return List<String>.from(raw);
  }

  Future<void> addEmergencyApp(String pkg) async {
    final list = getEmergencyApps();
    if (!list.contains(pkg)) {
      list.add(pkg);
      await _box.put('emergencyApps', list);
    }
  }

  Future<void> removeEmergencyApp(String pkg) async {
    final list = getEmergencyApps();
    list.remove(pkg);
    await _box.put('emergencyApps', list);
  }

  Future<void> setEmergencyApps(List<String> v) =>
      _box.put('emergencyApps', v);

  bool isEmergencyApp(String pkg) => getEmergencyApps().contains(pkg);

  // Legacy alias for backward compat
  List<String> get emergencyQuickApps => getEmergencyApps();
  Future<void> setEmergencyQuickApps(List<String> v) => setEmergencyApps(v);

  DateTime? get _lockUntil {
    final ms = _box.get('lockCooldownUntil') as int?;
    return ms != null ? DateTime.fromMillisecondsSinceEpoch(ms) : null;
  }

  bool get isLockCooldownActive {
    final u = _lockUntil;
    return u != null && u.isAfter(DateTime.now());
  }

  Duration? get lockCooldownRemaining {
    final u = _lockUntil;
    if (u == null) return null;
    final rem = u.difference(DateTime.now());
    return rem.isNegative ? null : rem;
  }

  Future<void> _startLockCooldown() => _box.put(
      'lockCooldownUntil',
      DateTime.now()
          .add(const Duration(seconds: 10))
          .millisecondsSinceEpoch);

  // ── Pending Floor Changes ──────────────────────────────────────────────────

  bool get hasPendingFloorChanges => _box.containsKey('pendingFloorMap') &&
      (_box.get('pendingFloorMap') as Map?)?.isNotEmpty == true;

  Map<String, int>? get pendingFloorChanges {
    final raw = _box.get('pendingFloorMap');
    if (raw == null) return null;
    return (raw as Map).map((k, v) => MapEntry(k.toString(), (v as num).toInt()));
  }

  /// Stages a floor change for [packageName].
  /// Returns false if blocked or cooldown is running.
  Future<bool> requestFloorChange(String packageName, int newFloor) async {
    // Check new strict sub-mode first — only for selected apps
    if (isFloorMoveLocked(packageName)) {
      if (strictSubType('floorMove') == 'block') return false;
      if (isStrictSubCooldownActive('floorMove')) return false;
      final current = pendingFloorChanges ?? {};
      current[packageName] = newFloor;
      await _box.put('pendingFloorMap', current);
      await startStrictSubCooldown('floorMove');
      return true;
    }
    // Legacy lock mode fallback
    if (isLockCooldownActive) return false;
    if (lockModeEnabled) {
      final current = pendingFloorChanges ?? {};
      current[packageName] = newFloor;
      await _box.put('pendingFloorMap', current);
      await _startLockCooldown();
    }
    return true;
  }

  /// Applies all pending floor changes to the AppConfig box and clears them.
  Future<void> applyPendingFloorChanges(Box<AppConfig> appBox) async {
    final pending = pendingFloorChanges;
    if (pending == null) return;
    for (final e in pending.entries) {
      final cfg = appBox.get(e.key);
      if (cfg != null) {
        cfg.floor = e.value;
        await cfg.save();
      }
    }
    await _box.delete('pendingFloorMap');
    await _box.delete('lockCooldownUntil');
  }

  // ── App Block ──────────────────────────────────────────────────────────────

  /// Values: 'none' | 'always' | 'time_range' | 'days'
  String blockTypeForApp(String pkg) =>
      (_box.get('blockType_$pkg') as String?) ?? 'none';

  Future<void> setBlockTypeForApp(String pkg, String type) =>
      _box.put('blockType_$pkg', type);

  /// Start of block time range in minutes from midnight (0-1439). Default 1320 (22:00).
  int blockStartForApp(String pkg) =>
      (_box.get('blockStart_$pkg') as int?) ?? 1320;

  Future<void> setBlockStartForApp(String pkg, int minutes) =>
      _box.put('blockStart_$pkg', minutes);

  /// End of block time range in minutes from midnight (0-1439). Default 420 (07:00).
  int blockEndForApp(String pkg) =>
      (_box.get('blockEnd_$pkg') as int?) ?? 420;

  Future<void> setBlockEndForApp(String pkg, int minutes) =>
      _box.put('blockEnd_$pkg', minutes);

  /// Days to block: list of Dart weekday ints (1=Mon .. 7=Sun). Default [1,2,3,4,5].
  List<int> blockDaysForApp(String pkg) {
    final raw = _box.get('blockDays_$pkg') as List<dynamic>?;
    if (raw == null) return [1, 2, 3, 4, 5];
    return raw.map((e) => (e as num).toInt()).toList();
  }

  Future<void> setBlockDaysForApp(String pkg, List<int> days) =>
      _box.put('blockDays_$pkg', days);

  /// Returns true if the app is currently blocked based on its block type and schedule.
  bool isAppBlocked(String pkg) {
    final type = blockTypeForApp(pkg);
    if (type == 'none') return false;
    if (type == 'always') return true;
    final now = DateTime.now();
    final nowMin = now.hour * 60 + now.minute;
    if (type == 'time_range') {
      final start = blockStartForApp(pkg);
      final end = blockEndForApp(pkg);
      if (start <= end) return nowMin >= start && nowMin < end;
      return nowMin >= start || nowMin < end; // overnight
    }
    if (type == 'days') {
      return blockDaysForApp(pkg).contains(now.weekday);
    }
    return false;
  }

  bool isBlockCooldownActive(String pkg) {
    final ms = _box.get('blockCooldownUntil_$pkg') as int?;
    if (ms == null) return false;
    return DateTime.fromMillisecondsSinceEpoch(ms).isAfter(DateTime.now());
  }

  Duration? blockCooldownRemaining(String pkg) {
    final ms = _box.get('blockCooldownUntil_$pkg') as int?;
    if (ms == null) return null;
    final rem = DateTime.fromMillisecondsSinceEpoch(ms).difference(DateTime.now());
    return rem.isNegative ? null : rem;
  }

  String? pendingBlockTypeForApp(String pkg) =>
      _box.get('pendingBlockType_$pkg') as String?;

  /// Requests a block type change. If block is currently active, stages with 3-min cooldown.
  /// Returns false if cooldown is already active.
  Future<bool> requestBlockChange(String pkg, String newType) async {
    if (isBlockCooldownActive(pkg)) return false;
    if (isAppBlocked(pkg)) {
      await _box.put('pendingBlockType_$pkg', newType);
      await _box.put(
          'blockCooldownUntil_$pkg',
          DateTime.now()
              .add(const Duration(seconds: 10))
              .millisecondsSinceEpoch);
    } else {
      await _box.put('blockType_$pkg', newType);
    }
    return true;
  }

  Future<void> applyPendingBlockChange(String pkg) async {
    final pending = pendingBlockTypeForApp(pkg);
    if (pending == null) return;
    await _box.put('blockType_$pkg', pending);
    await _box.delete('pendingBlockType_$pkg');
    await _box.delete('blockCooldownUntil_$pkg');
  }

  Future<void> recordBlockOverride(String pkg) async {
    final raw = (_box.get('blockOverrideLog_$pkg') as List<dynamic>?) ?? [];
    final log = raw.map((e) => (e as num).toInt()).toList();
    log.add(DateTime.now().millisecondsSinceEpoch);
    await _box.put('blockOverrideLog_$pkg', log);
  }

  // ── Recently Added Apps ────────────────────────────────────────────────────
  bool get showRecentlyAdded => (_box.get('showRecentlyAdded') as bool?) ?? false;
  Future<void> setShowRecentlyAdded(bool v) => _box.put('showRecentlyAdded', v);

  int get recentlyAddedDays => (_box.get('recentlyAddedDays') as int?) ?? 7;
  Future<void> setRecentlyAddedDays(int v) => _box.put('recentlyAddedDays', v);

  Map<String, int> get appInstallDates {
    final raw = _box.get('appInstallDates') as Map?;
    if (raw == null) return {};
    return raw.map((k, v) => MapEntry(k.toString(), (v as num).toInt()));
  }

  Future<void> recordAppInstallDate(String packageName) async {
    final dates = appInstallDates;
    if (!dates.containsKey(packageName)) {
      dates[packageName] = DateTime.now().millisecondsSinceEpoch;
      await _box.put('appInstallDates', dates);
    }
  }

  bool isRecentlyAdded(String packageName) {
    if (!showRecentlyAdded) return false;
    final dates = appInstallDates;
    final ts = dates[packageName];
    if (ts == null) return false;
    final installed = DateTime.fromMillisecondsSinceEpoch(ts);
    return DateTime.now().difference(installed).inDays <= recentlyAddedDays;
  }

  // ── Usage Count Floor Rules ───────────────────────────────────────────────
  // Each rule: {'threshold': int, 'floor': int}
  // Rules are sorted by threshold ascending. When daily count >= threshold, floor changes.

  List<Map<String, int>> usageCountFloorRules(String pkg) {
    final raw = _box.get('usageCountRules_$pkg') as List?;
    if (raw == null) return [];
    return raw.map((e) {
      final m = e as Map;
      return {'threshold': (m['threshold'] as num).toInt(), 'floor': (m['floor'] as num).toInt()};
    }).toList();
  }

  Future<void> setUsageCountFloorRules(String pkg, List<Map<String, int>> rules) =>
      _box.put('usageCountRules_$pkg', rules);

  Future<void> clearUsageCountFloorRules(String pkg) => _box.delete('usageCountRules_$pkg');

  /// Returns today's launch count for [pkg], resetting if date has changed.
  int dailyLaunchCount(String pkg) {
    final today = _todayString();
    final savedDate = _box.get('usageDailyDate_$pkg') as String?;
    if (savedDate != today) return 0;
    return (_box.get('usageDailyCount_$pkg') as int?) ?? 0;
  }

  /// Increments today's count by 1 (resets if day changed). Returns new count.
  Future<int> incrementDailyLaunchCount(String pkg) async {
    final today = _todayString();
    final savedDate = _box.get('usageDailyDate_$pkg') as String?;
    final count = savedDate == today ? ((_box.get('usageDailyCount_$pkg') as int?) ?? 0) : 0;
    final newCount = count + 1;
    await _box.put('usageDailyDate_$pkg', today);
    await _box.put('usageDailyCount_$pkg', newCount);
    return newCount;
  }

  /// Returns the floor override for [pkg] given its current daily count, or null if no rule applies.
  int? usageCountTargetFloor(String pkg) {
    final rules = usageCountFloorRules(pkg);
    if (rules.isEmpty) return null;
    final count = dailyLaunchCount(pkg);
    // Sort descending by threshold; return floor for first satisfied rule
    final sorted = [...rules]..sort((a, b) => b['threshold']!.compareTo(a['threshold']!));
    for (final rule in sorted) {
      if (count >= rule['threshold']!) return rule['floor'];
    }
    return null;
  }

  String _todayString() {
    final now = DateTime.now();
    return '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
  }
}
