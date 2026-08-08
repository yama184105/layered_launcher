part of '../settings_service.dart';

/// アプリの所属モード。全アプリがいずれか1つに属する。
/// - normal:     固定フロア（従来のアプリ一覧と同じ。手動移動のみ）
/// - schedule:   スケジュール（毎日/曜日別の時間帯でフロアが変わる）
/// - usageCount: 使用回数（1日の起動回数の閾値でフロアが変わる）
/// - usageTime:  使用時間（1日の使用時間(分)の閾値でフロアが変わる）
const kAppModes = ['normal', 'schedule', 'usageCount', 'usageTime'];

/// アプリ0個で保存されたスケジュール（テンプレート）。
/// [id] はスケジュールの実体を表し、アプリを割り当てるとそのIDが引き継がれる。
class SavedSchedule {
  final String id;
  final Map<String, dynamic> schedule;
  const SavedSchedule(this.id, this.schedule);
}

extension ModeSettings on SettingsService {
  // ── App mode (permanent assignment) ───────────────────────────────────────

  /// Permanent mode assignment for [pkg]. Unassigned apps are 'normal'.
  String appMode(String pkg) =>
      (_box.get('appMode_$pkg') as String?) ?? 'normal';

  Future<void> setAppMode(String pkg, String mode) async {
    if (mode == 'normal') {
      // ノーマル＝既定なのでキー自体を消す（位置保持: フロアは触らない）
      await _box.delete('appMode_$pkg');
    } else {
      await _box.put('appMode_$pkg', mode);
    }
  }

  /// Effective mode for [pkg] taking an active temporary override into
  /// account. Expired overrides are cleaned up lazily on read.
  String effectiveAppMode(String pkg) {
    final temp = _box.get('tempMode_$pkg') as String?;
    if (temp != null) {
      final ms = _box.get('tempModeExpiry_$pkg') as int?;
      if (ms != null &&
          DateTime.fromMillisecondsSinceEpoch(ms).isAfter(DateTime.now())) {
        return temp;
      }
      // expired — drop the override (位置保持: floor stays put, the
      // permanent mode's engine takes over from here)
      _box.delete('tempMode_$pkg');
      _box.delete('tempModeExpiry_$pkg');
    }
    return appMode(pkg);
  }

  // ── Temporary mode override ────────────────────────────────────────────────

  bool hasTempMode(String pkg) {
    final ms = _box.get('tempModeExpiry_$pkg') as int?;
    if (ms == null) return false;
    return DateTime.fromMillisecondsSinceEpoch(ms).isAfter(DateTime.now());
  }

  String? tempMode(String pkg) =>
      hasTempMode(pkg) ? _box.get('tempMode_$pkg') as String? : null;

  DateTime? tempModeExpiry(String pkg) {
    final ms = _box.get('tempModeExpiry_$pkg') as int?;
    if (ms == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }

  Future<void> setTempMode(String pkg, String mode, DateTime expiry) async {
    await _box.put('tempMode_$pkg', mode);
    await _box.put('tempModeExpiry_$pkg', expiry.millisecondsSinceEpoch);
  }

  Future<void> clearTempMode(String pkg) async {
    await _box.delete('tempMode_$pkg');
    await _box.delete('tempModeExpiry_$pkg');
  }

  // ── Usage-time floor rules ─────────────────────────────────────────────────
  // Each rule: {'threshold': int(minutes), 'floor': int}. Sorted ascending.
  // 1日の累計使用時間(分)が閾値に達したらフロア変更。閾値未満は位置保持。

  List<Map<String, int>> usageTimeFloorRules(String pkg) {
    final byDay = usageTimeFloorRulesByWeekday(pkg);
    if (byDay.isNotEmpty) {
      return byDay[DateTime.now().weekday] ?? const [];
    }
    final raw = _box.get('usageTimeRules_$pkg') as List?;
    if (raw == null) return [];
    return raw.map((e) {
      final m = e as Map;
      return {
        'threshold': (m['threshold'] as num).toInt(),
        'floor': (m['floor'] as num).toInt(),
      };
    }).toList();
  }

  Future<void> setUsageTimeFloorRules(
    String pkg,
    List<Map<String, int>> rules,
  ) => _box.put('usageTimeRules_$pkg', rules);

  Map<int, List<Map<String, int>>> usageTimeFloorRulesByWeekday(String pkg) {
    final raw = _box.get('usageTimeRulesByDay_$pkg') as String?;
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

  List<Map<String, int>> usageTimeFloorRulesForWeekday(
    String pkg,
    int weekday,
  ) {
    final byDay = usageTimeFloorRulesByWeekday(pkg);
    if (byDay.isNotEmpty) return byDay[weekday] ?? const [];
    final raw = _box.get('usageTimeRules_$pkg') as List?;
    if (raw == null) return [];
    return raw.map((e) {
      final m = e as Map;
      return {
        'threshold': (m['threshold'] as num).toInt(),
        'floor': (m['floor'] as num).toInt(),
      };
    }).toList();
  }

  Future<void> setUsageTimeFloorRulesByWeekday(
    String pkg,
    Map<int, List<Map<String, int>>> rules,
  ) async {
    final encoded = rules.map((key, value) => MapEntry(key.toString(), value));
    await _box.put('usageTimeRulesByDay_$pkg', jsonEncode(encoded));
    await _box.delete('usageTimeRules_$pkg');
  }

  Future<void> clearUsageTimeFloorRules(String pkg) async {
    await _box.delete('usageTimeRules_$pkg');
    await _box.delete('usageTimeRulesByDay_$pkg');
  }

  /// Target floor for [pkg] given today's usage of [usedMinutes], or null
  /// when no rule applies (位置保持).
  int? usageTimeTargetFloor(String pkg, int usedMinutes) {
    final rules = usageTimeFloorRules(pkg);
    if (rules.isEmpty) return null;
    final sorted = [...rules]
      ..sort((a, b) => b['threshold']!.compareTo(a['threshold']!));
    for (final rule in sorted) {
      if (usedMinutes >= rule['threshold']!) return rule['floor'];
    }
    return null;
  }

  // ── Queries ────────────────────────────────────────────────────────────────

  /// Packages explicitly assigned to [mode] ('schedule' | 'usageCount' |
  /// 'usageTime'). 'normal' is the implicit default and has no keys, so
  /// callers list normal apps as (all installed) − (assigned).
  List<String> appsInMode(String mode) {
    final result = <String>[];
    for (final key in _box.keys) {
      final k = key.toString();
      if (!k.startsWith('appMode_')) continue;
      if (_box.get(k) == mode) result.add(k.substring('appMode_'.length));
    }
    return result;
  }

  /// Packages with an active (non-expired) temporary mode override.
  List<String> get allTempModeApps {
    final result = <String>[];
    for (final key in _box.keys) {
      final k = key.toString();
      if (!k.startsWith('tempMode_') || k.startsWith('tempModeExpiry_')) {
        continue;
      }
      final pkg = k.substring('tempMode_'.length);
      if (hasTempMode(pkg)) result.add(pkg);
    }
    return result;
  }

  /// All packages with any non-normal permanent assignment.
  List<String> get allModeAssignedApps {
    final result = <String>[];
    for (final key in _box.keys) {
      final k = key.toString();
      if (k.startsWith('appMode_')) result.add(k.substring('appMode_'.length));
    }
    return result;
  }

  /// Removes [pkg] from whatever mode it is in → normal (位置保持:
  /// the floor is left exactly where it is now). Rule data is cleared
  /// so the app starts fresh if re-assigned later.
  Future<void> releaseFromMode(String pkg) async {
    await _box.delete('appMode_$pkg');
    await clearTempMode(pkg);
    await clearAutoMove(pkg);
    await clearUsageCountFloorRules(pkg);
    await clearUsageTimeFloorRules(pkg);
  }

  // ── 保存されたスケジュール（アプリ0個のテンプレート）────────────────────
  // スケジュールに属する最後のアプリをノーマルに戻すとき、そのスケジュールを
  // 残したい場合はここへ保存する。「既存のスケジュールに追加」やカスタム一覧に
  // アプリ0個のグループとして現れる。アプリが割り当てられたら自動で消える。

  Object? _canonize(Object? v) {
    if (v is Map) {
      final keys = v.keys.map((k) => k.toString()).toList()..sort();
      return {for (final k in keys) k: _canonize(v[k])};
    }
    if (v is List) return v.map(_canonize).toList();
    return v;
  }

  String scheduleCanonical(Map<String, dynamic> schedule) =>
      jsonEncode(_canonize(schedule));

  /// 保存形式: [{'id': String, 'schedule': Map}]。旧形式（スケジュール本体が
  /// そのまま入っている）も読めるようにしてある。
  List<SavedSchedule> get savedSchedules {
    final raw = _box.get('savedSchedules') as List?;
    if (raw == null) return [];
    final out = <SavedSchedule>[];
    for (final e in raw.whereType<Map>()) {
      final m = Map<String, dynamic>.from(e);
      if (m['schedule'] is Map) {
        out.add(SavedSchedule(
          m['id']?.toString() ?? 'legacy_${scheduleCanonical(m).hashCode}',
          Map<String, dynamic>.from(m['schedule'] as Map),
        ));
      } else {
        // 旧形式
        out.add(SavedSchedule('legacy_${scheduleCanonical(m).hashCode}', m));
      }
    }
    return out;
  }

  Future<void> _writeSavedSchedules(List<SavedSchedule> list) => _box.put(
        'savedSchedules',
        [
          for (final s in list) {'id': s.id, 'schedule': s.schedule},
        ],
      );

  Future<void> addSavedSchedule(
    String id,
    Map<String, dynamic> schedule,
  ) async {
    final list = savedSchedules;
    if (list.any((s) => s.id == id)) return;
    list.add(SavedSchedule(id, schedule));
    await _writeSavedSchedules(list);
  }

  Future<void> removeSavedScheduleById(String id) async {
    final list = savedSchedules.where((s) => s.id != id).toList();
    if (list.length == savedSchedules.length) return;
    await _writeSavedSchedules(list);
  }

  // ── Migration from the pre-mode systems ────────────────────────────────────
  // 旧: autoMove_mode_ ('schedule'|'interval') と usageCountRules_ が独立に
  // 共存していた。新: 1アプリ1モード。
  //   - schedule → schedule モード
  //   - interval（日数間隔ランダム・廃止）→ normal（位置保持）、設定は破棄
  //   - usageCountRules あり（schedule でない場合）→ usageCount モード
  Future<void> migrateAppModesIfNeeded() async {
    if ((_box.get('appModesMigrated') as bool?) == true) return;

    final scheduled = <String>{};
    final intervals = <String>{};
    for (final key in _box.keys.toList()) {
      final k = key.toString();
      if (!k.startsWith('autoMove_mode_')) continue;
      final pkg = k.substring('autoMove_mode_'.length);
      final mode = _box.get(k) as String?;
      if (mode == 'schedule') scheduled.add(pkg);
      if (mode == 'interval') intervals.add(pkg);
    }
    final counted = <String>{};
    for (final key in _box.keys.toList()) {
      final k = key.toString();
      if (!k.startsWith('usageCountRules_')) continue;
      final pkg = k.substring('usageCountRules_'.length);
      if ((_box.get(k) as List?)?.isNotEmpty == true) counted.add(pkg);
    }

    for (final pkg in scheduled) {
      await _box.put('appMode_$pkg', 'schedule');
    }
    for (final pkg in intervals) {
      await clearAutoMove(pkg); // 廃止 — 位置保持で normal へ
    }
    for (final pkg in counted) {
      if (scheduled.contains(pkg)) {
        // モードは排他。schedule を優先し回数ルールは破棄。
        await clearUsageCountFloorRules(pkg);
      } else {
        await _box.put('appMode_$pkg', 'usageCount');
      }
    }

    await _box.put('appModesMigrated', true);
  }
}
