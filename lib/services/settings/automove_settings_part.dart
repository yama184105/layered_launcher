part of '../settings_service.dart';

extension AutoMoveSettings on SettingsService {
  // ── Auto Move Mode ────────────────────────────────────────────────────────
  // Per-app: 'none' | 'schedule' | 'interval'
  String autoMoveMode(String pkg) =>
      (_box.get('autoMove_mode_$pkg') as String?) ?? 'none';

  Future<void> setAutoMoveMode(String pkg, String mode) =>
      _box.put('autoMove_mode_$pkg', mode);

  // ── Schedule ──────────────────────────────────────────────────────────────
  // Stored as JSON string: per-weekday default + slot list
  // Structure: { "weekday": {
  //   "default": { "type": "fixed"|"random", "floor": 1, "floors": [...],
  //                "shuffleMode": "once"|"repeat"|"count", ... },
  //   "slots": [ { "startMinute": 540, "endMinute": 1020,
  //                "type": "fixed"|"random", "floor": 3, "floors": [1,3,5],
  //                "shuffleMode": "once"|"repeat"|"count",
  //                "repeatDays": 0, "repeatHours": 1, "repeatMinutes": 0,
  //                "shuffleCount": 3 }, ... ]
  // } }
  // weekday keys: "1" (Mon) .. "7" (Sun). スケジュールが空の時間帯では
  // default の設定が適用される。

  Map<String, dynamic> autoMoveSchedule(String pkg) {
    final raw = _box.get('autoMove_schedule_$pkg') as String?;
    if (raw == null) return {};
    try {
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return {};
    }
  }

  Future<void> setAutoMoveSchedule(String pkg, Map<String, dynamic> schedule) =>
      _box.put('autoMove_schedule_$pkg', jsonEncode(schedule));

  // ── Schedule identity ─────────────────────────────────────────────────────
  // スケジュールは「内容」ではなく「実体」で区別する。同じ内容でも別々に
  // 作ったものは別スケジュール（使用回数などが混ざらないように）。
  // 同じスケジュールを共有するアプリだけが同じIDを持つ。

  String? autoMoveScheduleId(String pkg) =>
      _box.get('autoMove_scheduleId_$pkg') as String?;

  Future<void> setAutoMoveScheduleId(String pkg, String id) =>
      _box.put('autoMove_scheduleId_$pkg', id);

  /// 新しいスケジュール実体のID。
  String newScheduleId() =>
      'sch_${DateTime.now().microsecondsSinceEpoch}_${_scheduleIdSeq++}';

  /// 既存データ（IDが無い時代のスケジュール）にIDを振る。
  /// これまでは内容が同じものが1グループとして扱われていたので、その
  /// グループ分けを引き継ぐ（同一内容 → 同じID）。
  Future<void> migrateScheduleIdsIfNeeded() async {
    if ((_box.get('scheduleIdsMigrated') as bool?) == true) return;
    final idByCanonical = <String, String>{};
    for (final key in _box.keys.toList()) {
      final k = key.toString();
      if (!k.startsWith('autoMove_schedule_')) continue;
      final pkg = k.substring('autoMove_schedule_'.length);
      if (autoMoveScheduleId(pkg) != null) continue;
      final canonical = scheduleCanonical(autoMoveSchedule(pkg));
      final id = idByCanonical.putIfAbsent(canonical, newScheduleId);
      await setAutoMoveScheduleId(pkg, id);
    }
    await _box.put('scheduleIdsMigrated', true);
  }

  // ── Last schedule slot tracking (to detect slot changes) ──────────────────
  String? autoMoveLastSlotKey(String pkg) =>
      _box.get('autoMove_lastSlot_$pkg') as String?;

  Future<void> setAutoMoveLastSlotKey(String pkg, String key) =>
      _box.put('autoMove_lastSlot_$pkg', key);

  // ── Last shuffle time (for repeat mode) ───────────────────────────────────
  int? autoMoveLastShuffleMs(String pkg) =>
      _box.get('autoMove_lastShuffle_$pkg') as int?;

  Future<void> setAutoMoveLastShuffleMs(String pkg, int ms) =>
      _box.put('autoMove_lastShuffle_$pkg', ms);

  // ── Shuffle count tracking (for count mode) ──────────────────────────────
  int autoMoveShuffleCount(String pkg) =>
      (_box.get('autoMove_shuffleCount_$pkg') as int?) ?? 0;

  Future<void> setAutoMoveShuffleCount(String pkg, int count) =>
      _box.put('autoMove_shuffleCount_$pkg', count);

  // ── Clear auto-move for app ───────────────────────────────────────────────
  // interval系キーは廃止済みの旧モードBデータの掃除のため削除し続ける。
  Future<void> clearAutoMove(String pkg) async {
    await _box.delete('autoMove_mode_$pkg');
    await _box.delete('autoMove_intervalDays_$pkg');
    await _box.delete('autoMove_intervalFloors_$pkg');
    await _box.delete('autoMove_lastMoved_$pkg');
    await _box.delete('autoMove_schedule_$pkg');
    await _box.delete('autoMove_scheduleId_$pkg');
    await _box.delete('autoMove_lastSlot_$pkg');
    await _box.delete('autoMove_lastShuffle_$pkg');
    await _box.delete('autoMove_shuffleCount_$pkg');
  }
}
