part of '../settings_service.dart';

extension EmergencySettings on SettingsService {
  // ── Emergency Limit ────────────────────────────────────────────────────────

  /// Values: 'unlimited' | 'daily' | 'weekly' | 'yearly'
  String get emergencyLimit =>
      (_box.get('emergencyLimit') as String?) ?? 'unlimited';
  Future<void> setEmergencyLimit(String v) => _box.put('emergencyLimit', v);

  String? get pendingEmergencyLimit =>
      _box.get('pendingEmergencyLimit') as String?;

  DateTime? get _emergencyLimitUntil {
    final ms = _box.get('emergencyLimitCooldownUntil') as int?;
    return ms != null ? DateTime.fromMillisecondsSinceEpoch(ms) : null;
  }

  bool get isEmergencyLimitCooldownActive {
    final u = _emergencyLimitUntil;
    return u != null && u.isAfter(DateTime.now());
  }

  Duration? get emergencyLimitCooldownRemaining {
    final u = _emergencyLimitUntil;
    if (u == null) return null;
    final rem = u.difference(DateTime.now());
    return rem.isNegative ? null : rem;
  }

  /// Stages a new emergency limit. Returns false if blocked/cooldown active.
  Future<bool> requestEmergencyLimitChange(String newValue) async {
    // Check new strict sub-mode first
    if (strictSubEnabled('emergency')) {
      if (strictSubType('emergency') == 'block') return false;
      if (isStrictSubCooldownActive('emergency')) return false;
      await _box.put('pendingEmergencyLimit', newValue);
      await startStrictSubCooldown('emergency');
      return true;
    }
    // Legacy fallback
    if (isEmergencyLimitCooldownActive) return false;
    await _box.put('pendingEmergencyLimit', newValue);
    await _box.put(
        'emergencyLimitCooldownUntil',
        DateTime.now()
            .add(const Duration(seconds: 10))
            .millisecondsSinceEpoch);
    return true;
  }

  Future<void> applyPendingEmergencyLimit() async {
    final pending = pendingEmergencyLimit;
    if (pending == null) return;
    await _box.put('emergencyLimit', pending);
    await _box.delete('pendingEmergencyLimit');
    await _box.delete('emergencyLimitCooldownUntil');
  }

  // ── Emergency Usage Tracking (legacy, kept for backups/restore) ──────────
  List<DateTime> get emergencyUsageLog {
    final raw = _box.get('emergencyUsageLog') as List<dynamic>?;
    if (raw == null) return [];
    return raw
        .map((e) => DateTime.fromMillisecondsSinceEpoch((e as num).toInt()))
        .toList();
  }

  /// Returns true if the legacy global limit allows another use. Always true
  /// when emergencyLimit == 'unlimited'.
  bool _legacyGlobalAllows() {
    final limit = emergencyLimit;
    if (limit == 'unlimited') return true;
    final now = DateTime.now();
    final log = emergencyUsageLog;
    final DateTime cutoff;
    switch (limit) {
      case 'daily':
        cutoff = DateTime(now.year, now.month, now.day);
        break;
      case 'weekly':
        final mon = now.subtract(Duration(days: now.weekday - 1));
        cutoff = DateTime(mon.year, mon.month, mon.day);
        break;
      case 'yearly':
        cutoff = DateTime(now.year);
        break;
      default:
        return true;
    }
    return !log.any((d) => d.isAfter(cutoff));
  }

  String emergencyLimitBlockMessage(AppLocalizations s) =>
      checkEmergencyLimit(s, 'all', const []) ?? s.legacyEmergencyLimitGeneric;

  String limitLabel(AppLocalizations s, String key) {
    switch (key) {
      case 'unlimited':
        return s.unlimited;
      case 'daily':
        return s.periodOnceDaily;
      case 'weekly':
        return s.limitOnceWeeklyLong;
      case 'yearly':
        return s.limitOnceYearlyLong;
      default:
        return key;
    }
  }

  // ── Detailed per-mode limits (v2) ─────────────────────────────────────────
  // Each cap is stored as { 'count': int, 'period': String }.
  //   count == 0  → unlimited
  //   period one of 'hourly' | 'daily' | 'weekly' | 'monthly' | 'yearly'.

  Map<String, dynamic> _readCap(String key, String defaultPeriod) {
    final raw = _box.get(key);
    if (raw is Map) {
      return {
        'count': (raw['count'] as num?)?.toInt() ?? 0,
        'period': (raw['period'] as String?) ?? defaultPeriod,
      };
    }
    return {'count': 0, 'period': defaultPeriod};
  }

  Future<void> _writeCap(String key, int count, String period) =>
      _box.put(key, {'count': count, 'period': period});

  // Mode 'all' — entire app list shown on 1F.
  Map<String, dynamic> get emergencyCapAll => _readCap('emgCap_all', 'weekly');
  Future<void> setEmergencyCapAll(int count, String period) =>
      _writeCap('emgCap_all', count, period);

  // Mode 'pick' — pick from full app list.
  Map<String, dynamic> get emergencyCapPick => _readCap('emgCap_pick', 'daily');
  Future<void> setEmergencyCapPick(int count, String period) =>
      _writeCap('emgCap_pick', count, period);

  // Mode 'registered' — global cap across all registered emergency apps.
  Map<String, dynamic> get emergencyCapRegisteredGlobal =>
      _readCap('emgCap_regGlobal', 'daily');
  Future<void> setEmergencyCapRegisteredGlobal(int count, String period) =>
      _writeCap('emgCap_regGlobal', count, period);

  // Per-registered-app cap. Returns null when the user hasn't set one for [pkg].
  Map<String, dynamic>? emergencyCapForApp(String pkg) {
    final raw = _box.get('emgCap_app_$pkg');
    if (raw is Map) {
      return {
        'count': (raw['count'] as num?)?.toInt() ?? 0,
        'period': (raw['period'] as String?) ?? 'daily',
      };
    }
    return null;
  }

  Future<void> setEmergencyCapForApp(
      String pkg, int count, String period) async {
    if (count <= 0) {
      await _box.delete('emgCap_app_$pkg');
    } else {
      await _box.put('emgCap_app_$pkg', {'count': count, 'period': period});
    }
  }

  // Folder caps for registered apps.
  // Stored as List<{ 'name': String, 'apps': List<String>, 'count': int, 'period': String }>
  List<Map<String, dynamic>> get emergencyCapFolders {
    final raw = _box.get('emgCap_folders') as List?;
    if (raw == null) return [];
    return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<void> setEmergencyCapFolders(List<Map<String, dynamic>> folders) =>
      _box.put('emgCap_folders', folders);

  // ── Usage Log v2 ──────────────────────────────────────────────────────────
  // Each entry: { 'ts': epochMs, 'mode': 'all'|'pick'|'registered', 'apps': [pkg,...] }
  List<Map<String, dynamic>> get emergencyUsageLogV2 {
    final raw = _box.get('emergencyUsageLogV2') as List?;
    if (raw == null) return [];
    return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<void> recordEmergencyUseV2(String mode, List<String> apps) async {
    final log = emergencyUsageLogV2;
    log.add({
      'ts': DateTime.now().millisecondsSinceEpoch,
      'mode': mode,
      'apps': List<String>.from(apps),
    });
    final trimmed = log.length > 500 ? log.sublist(log.length - 500) : log;
    await _box.put('emergencyUsageLogV2', trimmed);

    // Keep the legacy log alive too — used by `emergencyLimit` (legacy global cap).
    final legacy = emergencyUsageLog;
    legacy.add(DateTime.now());
    final legacyTrim =
        legacy.length > 200 ? legacy.sublist(legacy.length - 200) : legacy;
    await _box.put('emergencyUsageLog',
        legacyTrim.map((d) => d.millisecondsSinceEpoch).toList());
  }

  DateTime _periodCutoff(String period, DateTime now) {
    switch (period) {
      case 'hourly':
        return now.subtract(const Duration(hours: 1));
      case 'daily':
        return DateTime(now.year, now.month, now.day);
      case 'weekly':
        final mon = now.subtract(Duration(days: now.weekday - 1));
        return DateTime(mon.year, mon.month, mon.day);
      case 'monthly':
        return DateTime(now.year, now.month);
      case 'yearly':
        return DateTime(now.year);
      default:
        return DateTime.fromMillisecondsSinceEpoch(0);
    }
  }

  int _countUsage({
    String? mode,
    String? containingApp,
    Set<String>? containingAnyOf,
    required String period,
  }) {
    if (period == 'unlimited' || period.isEmpty) return 0;
    final cutoff = _periodCutoff(period, DateTime.now());
    int n = 0;
    for (final entry in emergencyUsageLogV2) {
      final ts = (entry['ts'] as num?)?.toInt() ?? 0;
      if (ts <= 0) continue;
      final when = DateTime.fromMillisecondsSinceEpoch(ts);
      if (when.isBefore(cutoff)) continue;
      if (mode != null && (entry['mode'] as String?) != mode) continue;
      final entryApps = (entry['apps'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const <String>[];
      if (containingApp != null && !entryApps.contains(containingApp)) continue;
      if (containingAnyOf != null &&
          !entryApps.any(containingAnyOf.contains)) continue;
      n++;
    }
    return n;
  }

  String periodLabel(AppLocalizations s, String period) {
    switch (period) {
      case 'hourly':
        return s.periodHourly;
      case 'daily':
        return s.periodDaily;
      case 'weekly':
        return s.periodWeekly;
      case 'monthly':
        return s.periodMonthly;
      case 'yearly':
        return s.periodYearly;
      case 'unlimited':
        return s.unlimited;
      default:
        return period;
    }
  }

  String capSummary(AppLocalizations s, Map<String, dynamic> cap) {
    final count = (cap['count'] as num?)?.toInt() ?? 0;
    if (count <= 0) return s.unlimited;
    final period = cap['period'] as String? ?? 'daily';
    return s.capCountInPeriod(periodLabel(s, period), count);
  }

  /// Returns null when the requested emergency activation is allowed; otherwise
  /// a localized reason describing which cap blocks it. [apps] is the set of
  /// packages the user is about to activate.
  String? checkEmergencyLimit(AppLocalizations s, String mode, List<String> apps) {
    // Legacy global cap (kept for backwards compatibility with old setting).
    if (!_legacyGlobalAllows()) {
      switch (emergencyLimit) {
        case 'daily':
          return s.legacyEmergencyLimitDaily;
        case 'weekly':
          return s.legacyEmergencyLimitWeekly;
        case 'yearly':
          return s.legacyEmergencyLimitYearly;
        default:
          return s.legacyEmergencyLimitGeneric;
      }
    }
    if (mode == 'all') {
      final cap = emergencyCapAll;
      final c = (cap['count'] as num?)?.toInt() ?? 0;
      if (c > 0) {
        final p = cap['period'] as String? ?? 'weekly';
        final used = _countUsage(mode: 'all', period: p);
        if (used >= c) {
          return s.emergencyShowAllOn1FExceeded(periodLabel(s, p), c);
        }
      }
    } else if (mode == 'pick') {
      final cap = emergencyCapPick;
      final c = (cap['count'] as num?)?.toInt() ?? 0;
      if (c > 0) {
        final p = cap['period'] as String? ?? 'daily';
        final used = _countUsage(mode: 'pick', period: p);
        if (used >= c) {
          return s.emergencyAppListPickExceeded(periodLabel(s, p), c);
        }
      }
    } else if (mode == 'registered') {
      // 1) global cap for the registered mode
      final globalCap = emergencyCapRegisteredGlobal;
      final gc = (globalCap['count'] as num?)?.toInt() ?? 0;
      if (gc > 0) {
        final p = globalCap['period'] as String? ?? 'daily';
        final used = _countUsage(mode: 'registered', period: p);
        if (used >= gc) {
          return s.emergencyRegisteredGlobalExceeded(periodLabel(s, p), gc);
        }
      }
      // 2) per-app caps
      for (final pkg in apps) {
        final cfg = emergencyCapForApp(pkg);
        if (cfg == null) continue;
        final c = (cfg['count'] as num?)?.toInt() ?? 0;
        if (c <= 0) continue;
        final p = cfg['period'] as String? ?? 'daily';
        final used = _countUsage(containingApp: pkg, period: p);
        if (used >= c) {
          return s.emergencyAppCapExceeded(periodLabel(s, p), c);
        }
      }
      // 3) folder caps
      for (final folder in emergencyCapFolders) {
        final folderApps = (folder['apps'] as List?)
                ?.map((e) => e.toString())
                .toSet() ??
            <String>{};
        final overlap = apps.where(folderApps.contains).toList();
        if (overlap.isEmpty) continue;
        final c = (folder['count'] as num?)?.toInt() ?? 0;
        if (c <= 0) continue;
        final p = folder['period'] as String? ?? 'daily';
        final used = _countUsage(containingAnyOf: folderApps, period: p);
        if (used >= c) {
          final name = folder['name'] as String? ?? s.folderLabel;
          return s.emergencyFolderCapExceeded(name, periodLabel(s, p), c);
        }
      }
    }
    return null;
  }

  /// Returns true if any emergency-mode activation is plausible right now —
  /// used to short-circuit the chooser dialog when literally everything is
  /// blocked.
  bool canActivateEmergency() => _legacyGlobalAllows();
}
