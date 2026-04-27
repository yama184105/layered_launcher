part of '../settings_service.dart';

extension AutoMoveSettings on SettingsService {
  // ── Auto Move Mode ────────────────────────────────────────────────────────
  // Per-app: 'none' | 'schedule' | 'interval'
  String autoMoveMode(String pkg) =>
      (_box.get('autoMove_mode_$pkg') as String?) ?? 'none';

  Future<void> setAutoMoveMode(String pkg, String mode) =>
      _box.put('autoMove_mode_$pkg', mode);

  // ── Mode B: Interval Random ───────────────────────────────────────────────
  int autoMoveIntervalDays(String pkg) =>
      (_box.get('autoMove_intervalDays_$pkg') as int?) ?? 1;

  Future<void> setAutoMoveIntervalDays(String pkg, int days) =>
      _box.put('autoMove_intervalDays_$pkg', days);

  List<int> autoMoveIntervalFloors(String pkg) {
    final raw = _box.get('autoMove_intervalFloors_$pkg') as List?;
    if (raw == null) return [1, 2, 3];
    return raw.map((e) => (e as num).toInt()).toList();
  }

  Future<void> setAutoMoveIntervalFloors(String pkg, List<int> floors) =>
      _box.put('autoMove_intervalFloors_$pkg', floors);

  int? autoMoveLastMovedMs(String pkg) =>
      _box.get('autoMove_lastMoved_$pkg') as int?;

  Future<void> setAutoMoveLastMovedMs(String pkg, int ms) =>
      _box.put('autoMove_lastMoved_$pkg', ms);

  // ── Mode A: Schedule ──────────────────────────────────────────────────────
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

  // ── Get all apps with auto-move enabled ───────────────────────────────────
  List<String> get allAutoMoveApps {
    final result = <String>[];
    for (final key in _box.keys) {
      final k = key.toString();
      if (k.startsWith('autoMove_mode_')) {
        final mode = _box.get(k) as String?;
        if (mode != null && mode != 'none') {
          result.add(k.substring('autoMove_mode_'.length));
        }
      }
    }
    return result;
  }

  // ── Clear auto-move for app ───────────────────────────────────────────────
  Future<void> clearAutoMove(String pkg) async {
    await _box.delete('autoMove_mode_$pkg');
    await _box.delete('autoMove_intervalDays_$pkg');
    await _box.delete('autoMove_intervalFloors_$pkg');
    await _box.delete('autoMove_lastMoved_$pkg');
    await _box.delete('autoMove_schedule_$pkg');
    await _box.delete('autoMove_lastSlot_$pkg');
    await _box.delete('autoMove_lastShuffle_$pkg');
    await _box.delete('autoMove_shuffleCount_$pkg');
  }
}
