part of '../settings_service.dart';

extension BlockSettings on SettingsService {
  // ── Strict Sub-modes ─────────────────────────────────────────────────────
  // Keys: 'floorMove', 'animation', 'submode', 'emergency', 'shortcut'
  // Localized labels/descriptions live in the UI layer (security_settings_part.dart)
  // so that this service file stays free of hardcoded strings.
  static const strictSubKeys = [
    'floorMove',
    'animation',
    'submode',
    'emergency',
    'shortcut',
  ];

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

  /// 待ち時間を秒で。タイマーダイアログとクールダウンの両方がこれを使う
  /// （以前はどちらも10秒固定だった）。
  int strictSubTimerSeconds(String key) => strictSubTimerMinutes(key) * 60;

  bool isStrictSubCooldownActive(String key) {
    final ms = _box.get('strict_${key}_cooldownUntil') as int?;
    if (ms == null) return false;
    return DateTime.fromMillisecondsSinceEpoch(ms).isAfter(DateTime.now());
  }

  Duration? strictSubCooldownRemaining(String key) {
    final ms = _box.get('strict_${key}_cooldownUntil') as int?;
    if (ms == null) return null;
    final rem = DateTime.fromMillisecondsSinceEpoch(
      ms,
    ).difference(DateTime.now());
    return rem.isNegative ? null : rem;
  }

  Future<void> startStrictSubCooldown(String key) async {
    await _box.put(
      'strict_${key}_cooldownUntil',
      DateTime.now()
          .add(Duration(minutes: strictSubTimerMinutes(key)))
          .millisecondsSinceEpoch,
    );
  }

  // ── Floor-move locked apps (per-app selection) ────────────────────────────
  List<String> get floorMoveLockedApps {
    final raw = (_box.get('floorMoveLockedApps') as List?) ?? [];
    return List<String>.from(raw);
  }

  Future<void> setFloorMoveLockedApps(List<String> v) =>
      _box.put('floorMoveLockedApps', v);

  /// ロック対象への「追加」だけを即時に適用する。削除はストリクトの
  /// タイマー待ちか予約が要るので、呼び出し側（UI）がゲートを通す。
  Future<void> addFloorMoveLockedApps(Iterable<String> pkgs) async {
    final list = floorMoveLockedApps;
    var changed = false;
    for (final pkg in pkgs) {
      if (!list.contains(pkg)) {
        list.add(pkg);
        changed = true;
      }
    }
    if (changed) await setFloorMoveLockedApps(list);
  }

  bool isFloorMoveLocked(String packageName) {
    if (!strictSubEnabled('floorMove')) return false;
    final locked = floorMoveLockedApps;
    // If no apps selected, lock applies to ALL (backward compat)
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

  Future<void> setEmergencyApps(List<String> v) => _box.put('emergencyApps', v);

  bool isEmergencyApp(String pkg) => getEmergencyApps().contains(pkg);

  // Legacy alias for backward compat
  List<String> get emergencyQuickApps => getEmergencyApps();
  Future<void> setEmergencyQuickApps(List<String> v) => setEmergencyApps(v);

  // ── レガシーロックモードからの移行 ──────────────────────────────────────
  // 旧: lockMode + pendingFloorMap + 10秒クールダウン。
  // 新: ストリクトのサブモード（タイマー/予約）に一本化。移行時は
  //     lockMode が ON だったなら floorMove ロック（タイマー）を有効にし、
  //     保留中だったフロア変更はその場で適用してキーごと捨てる。
  Future<void> migrateLegacyLockIfNeeded(Box<AppConfig> appBox) async {
    if ((_box.get('legacyLockMigrated') as bool?) == true) return;

    final pending = _box.get('pendingFloorMap');
    if (pending is Map) {
      for (final e in pending.entries) {
        final cfg = appBox.get(e.key.toString());
        final floor = (e.value as num?)?.toInt();
        if (cfg == null || floor == null) continue;
        cfg.floor = floor;
        await cfg.save();
      }
    }
    if ((_box.get('lockMode') as bool?) == true &&
        !strictSubEnabled('floorMove')) {
      await setStrictSubEnabled('floorMove', true);
      await setStrictSubType('floorMove', 'timer');
    }
    for (final key in [
      'lockMode',
      'pendingFloorMap',
      'lockCooldownUntil',
      'animCooldownUntil',
      'pendingAnimationType',
      'pendingAnimationSpeedMs',
      'pendingEmergencyLimit',
      'emergencyLimitCooldownUntil',
      'emergencyLockedApps',
    ]) {
      await _box.delete(key);
    }
    await _box.put('legacyLockMigrated', true);
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
  int blockEndForApp(String pkg) => (_box.get('blockEnd_$pkg') as int?) ?? 420;

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
    final rem = DateTime.fromMillisecondsSinceEpoch(
      ms,
    ).difference(DateTime.now());
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
        DateTime.now().add(const Duration(seconds: 10)).millisecondsSinceEpoch,
      );
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
  bool get showRecentlyAdded =>
      (_box.get('showRecentlyAdded') as bool?) ?? false;
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
    final byDay = usageCountFloorRulesByWeekday(pkg);
    if (byDay.isNotEmpty) {
      return byDay[DateTime.now().weekday] ?? const [];
    }
    final raw = _box.get('usageCountRules_$pkg') as List?;
    if (raw == null) return [];
    return raw.map((e) {
      final m = e as Map;
      return {
        'threshold': (m['threshold'] as num).toInt(),
        'floor': (m['floor'] as num).toInt(),
      };
    }).toList();
  }

  Future<void> setUsageCountFloorRules(
    String pkg,
    List<Map<String, int>> rules,
  ) => _box.put('usageCountRules_$pkg', rules);

  Map<int, List<Map<String, int>>> usageCountFloorRulesByWeekday(String pkg) {
    final raw = _box.get('usageCountRulesByDay_$pkg') as String?;
    if (raw == null) return {};
    try {
      final decoded = jsonDecode(raw) as Map;
      return decoded.map((key, value) {
        final list = (value as List? ?? const []).map((e) {
          final m = e as Map;
          return {
            'threshold': (m['threshold'] as num).toInt(),
            'floor': (m['floor'] as num).toInt(),
          };
        }).toList();
        return MapEntry(int.parse(key.toString()), list);
      });
    } catch (_) {
      return {};
    }
  }

  List<Map<String, int>> usageCountFloorRulesForWeekday(
    String pkg,
    int weekday,
  ) {
    final byDay = usageCountFloorRulesByWeekday(pkg);
    if (byDay.isNotEmpty) return byDay[weekday] ?? const [];
    final raw = _box.get('usageCountRules_$pkg') as List?;
    if (raw == null) return [];
    return raw.map((e) {
      final m = e as Map;
      return {
        'threshold': (m['threshold'] as num).toInt(),
        'floor': (m['floor'] as num).toInt(),
      };
    }).toList();
  }

  Future<void> setUsageCountFloorRulesByWeekday(
    String pkg,
    Map<int, List<Map<String, int>>> rules,
  ) async {
    final encoded = rules.map((key, value) => MapEntry(key.toString(), value));
    await _box.put('usageCountRulesByDay_$pkg', jsonEncode(encoded));
    await _box.delete('usageCountRules_$pkg');
  }

  Future<void> clearUsageCountFloorRules(String pkg) async {
    await _box.delete('usageCountRules_$pkg');
    await _box.delete('usageCountRulesByDay_$pkg');
  }

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
    final count = savedDate == today
        ? ((_box.get('usageDailyCount_$pkg') as int?) ?? 0)
        : 0;
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
    final sorted = [...rules]
      ..sort((a, b) => b['threshold']!.compareTo(a['threshold']!));
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
