part of '../settings_service.dart';

/// ストリクトモードの「予約変更」。
///
/// ロックされている変更を今すぐ適用するのではなく、指定時間後（既定1時間）
/// に自動で適用する。タイマーダイアログの前で待ち続けなくてよくなる代わり、
/// 衝動的な変更は結局その場では通らない、というのが狙い。
///
/// 保存形式: `strictReservations` に List<Map>
///   { 'id': String, 'kind': String, 'label': String,
///     'applyAt': int(epochMs), 'data': Map }
class StrictReservation {
  final String id;
  final String kind;

  /// 予約一覧に出す説明文（作成時のロケールで確定させる）。
  final String label;
  final DateTime applyAt;
  final Map<String, dynamic> data;

  const StrictReservation({
    required this.id,
    required this.kind,
    required this.label,
    required this.applyAt,
    required this.data,
  });

  Duration get remaining => applyAt.difference(DateTime.now());
  bool get isDue => !applyAt.isAfter(DateTime.now());

  /// 同じ対象への予約は1件だけ持つ（後から入れた方で上書き）。
  String get targetKey {
    final from = data['from'];
    if (from != null) return '$kind:$from-${data['to']}';
    return '$kind:${data['pkg'] ?? data['key'] ?? ''}';
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'kind': kind,
    'label': label,
    'applyAt': applyAt.millisecondsSinceEpoch,
    'data': data,
  };

  static StrictReservation? fromMap(Map raw) {
    final id = raw['id']?.toString();
    final kind = raw['kind']?.toString();
    final ms = (raw['applyAt'] as num?)?.toInt();
    if (id == null || kind == null || ms == null) return null;
    return StrictReservation(
      id: id,
      kind: kind,
      label: raw['label']?.toString() ?? '',
      applyAt: DateTime.fromMillisecondsSinceEpoch(ms),
      data: raw['data'] is Map
          ? Map<String, dynamic>.from(raw['data'] as Map)
          : const {},
    );
  }
}

/// 予約できる変更の種類。ここに無い操作（アニメーション速度・ショートカット）
/// はタイマー待ちのみ。
class ReservationKinds {
  /// data: {'pkg': String, 'floor': int} — ロック中アプリのフロア移動
  static const floorMove = 'floorMove';

  /// data: {'floors': {pkg: floor}} — 複数アプリのフロア移動をまとめて
  static const floorMoveBulk = 'floorMoveBulk';

  /// data: {'apps': List<String>} — フロア移動ロックの対象アプリを
  /// このリストに置き換える（＝ロックを緩める向きの変更）
  static const floorMoveLockSet = 'floorMoveLockSet';

  /// data: {'key': String, 'value': bool}
  static const strictSubEnabled = 'strictSubEnabled';

  /// data: {'key': String, 'value': String}
  static const strictSubType = 'strictSubType';

  /// data: {'key': String, 'value': int}
  static const strictSubTimer = 'strictSubTimer';

  /// data: {'value': String}
  static const emergencyLimit = 'emergencyLimit';

  /// data: {'key': 'all'|'pick'|'regGlobal', 'count': int, 'period': String}
  static const emergencyCap = 'emergencyCap';

  /// data: {'apps': List<String>} — 緊急アプリの登録リストを置き換える
  static const emergencyApps = 'emergencyApps';

  /// data: {'pkg': String, 'count': int, 'period': String}
  static const emergencyCapApp = 'emergencyCapApp';

  /// data: {'folders': List<Map>} — 緊急フォルダ上限をまとめて置き換える
  static const emergencyCapFolders = 'emergencyCapFolders';

  /// data: {'value': int} — アニメーション速度（全体）
  static const animationSpeed = 'animationSpeed';

  /// data: {'from': int, 'to': int, 'value': int} — フロア間の個別速度
  static const animationPairSpeed = 'animationPairSpeed';

  /// data: {} — フロア間の個別速度をすべて解除して全体設定に戻す
  static const animationClearPairs = 'animationClearPairs';

  /// data: {'pkg': String, 'floor': int, 'minutes': int} または
  ///       {'floors': {pkg: floor}, 'minutes': int} — 一時移動（期限つき）
  static const tempMove = 'tempMove';

  /// data: {'pkgs': List<String>, 'schedule': Map} — スケジュール割り当て
  static const scheduleAssign = 'scheduleAssign';
}

extension ReservationSettings on SettingsService {
  // ── 設定 ──────────────────────────────────────────────────────────────────

  bool get strictReservationEnabled =>
      (_box.get('strictReservationEnabled') as bool?) ?? false;
  Future<void> setStrictReservationEnabled(bool v) =>
      _box.put('strictReservationEnabled', v);

  /// 予約してから適用されるまでの待ち時間（分）。既定60分＝1時間。
  int get strictReservationMinutes =>
      (_box.get('strictReservationMinutes') as int?) ?? 60;
  Future<void> setStrictReservationMinutes(int v) =>
      _box.put('strictReservationMinutes', v);

  // ── 予約の読み書き ────────────────────────────────────────────────────────

  /// 適用時刻の早い順。
  List<StrictReservation> get strictReservations {
    final raw = _box.get('strictReservations') as List?;
    if (raw == null) return [];
    final list = raw
        .whereType<Map>()
        .map(StrictReservation.fromMap)
        .whereType<StrictReservation>()
        .toList();
    list.sort((a, b) => a.applyAt.compareTo(b.applyAt));
    return list;
  }

  Future<void> _writeStrictReservations(List<StrictReservation> list) async {
    await _box.put('strictReservations', list.map((r) => r.toMap()).toList());
    // 次に適用すべき時刻をキャッシュしておく。毎秒の tick はこの1件だけを
    // 読めばよく、予約リスト全体のパースを避けられる。
    if (list.isEmpty) {
      await _box.delete('strictReservationNextMs');
    } else {
      final next = list
          .map((r) => r.applyAt.millisecondsSinceEpoch)
          .reduce((a, b) => a < b ? a : b);
      await _box.put('strictReservationNextMs', next);
    }
  }

  /// 次に予約が適用される時刻（epoch ms）。予約がなければ null。
  int? get nextReservationDueMs {
    final cached = _box.get('strictReservationNextMs') as int?;
    if (cached != null) return cached;
    // キャッシュ未作成（旧バージョンで書かれた予約）へのフォールバック
    final list = strictReservations;
    if (list.isEmpty) return null;
    return list.first.applyAt.millisecondsSinceEpoch;
  }

  /// 同じ対象への既存予約があれば置き換える。
  Future<StrictReservation> addStrictReservation(
    String kind,
    String label,
    Map<String, dynamic> data,
  ) async {
    final now = DateTime.now();
    final reservation = StrictReservation(
      id: now.microsecondsSinceEpoch.toString(),
      kind: kind,
      label: label,
      applyAt: now.add(Duration(minutes: strictReservationMinutes)),
      data: data,
    );
    final list = strictReservations
        .where((r) => r.targetKey != reservation.targetKey)
        .toList()
      ..add(reservation);
    await _writeStrictReservations(list);
    return reservation;
  }

  /// 予約の取り消しは制限しない（変更を「しない」方向なので安全側）。
  Future<void> cancelStrictReservation(String id) =>
      _writeStrictReservations(
        strictReservations.where((r) => r.id != id).toList(),
      );

  Future<void> clearStrictReservations() async {
    await _box.delete('strictReservations');
    await _box.delete('strictReservationNextMs');
  }

  StrictReservation? strictReservationFor(String kind, {String? pkg, String? key}) {
    final target = '$kind:${pkg ?? key ?? ''}';
    for (final r in strictReservations) {
      if (r.targetKey == target) return r;
    }
    return null;
  }

  bool get hasDueStrictReservations => strictReservations.any((r) => r.isDue);

  // ── 適用 ──────────────────────────────────────────────────────────────────

  /// 期限が来た予約を適用して取り除く。フロア移動を含むので AppConfig の
  /// box を受け取る。戻り値は適用した予約（UI通知用）。
  Future<List<StrictReservation>> applyDueStrictReservations(
    Box<AppConfig> appBox,
  ) async {
    final all = strictReservations;
    final due = all.where((r) => r.isDue).toList();
    if (due.isEmpty) return const [];

    for (final r in due) {
      switch (r.kind) {
        case ReservationKinds.floorMove:
          final pkg = r.data['pkg']?.toString();
          final floor = (r.data['floor'] as num?)?.toInt();
          if (pkg == null || floor == null) break;
          final cfg = appBox.get(pkg);
          if (cfg == null) break;
          // 一時移動中なら「本来のフロア」だけを書き換える
          if (cfg.permanentFloor != null) {
            cfg.permanentFloor = floor;
          } else {
            cfg.floor = floor;
          }
          await cfg.save();
          break;
        case ReservationKinds.floorMoveBulk:
          final raw = r.data['floors'];
          if (raw is! Map) break;
          for (final e in raw.entries) {
            final cfg = appBox.get(e.key.toString());
            final floor = (e.value as num?)?.toInt();
            if (cfg == null || floor == null) continue;
            if (cfg.permanentFloor != null) {
              cfg.permanentFloor = floor;
            } else {
              cfg.floor = floor;
            }
            await cfg.save();
          }
          break;
        case ReservationKinds.floorMoveLockSet:
          final apps =
              (r.data['apps'] as List?)?.map((e) => e.toString()).toList();
          if (apps != null) await setFloorMoveLockedApps(apps);
          break;
        case ReservationKinds.tempMove:
          final minutes = (r.data['minutes'] as num?)?.toInt() ?? 60;
          final expiry = DateTime.now().add(Duration(minutes: minutes));
          final targets = <String, int>{};
          final floorsMap = r.data['floors'];
          if (floorsMap is Map) {
            for (final e in floorsMap.entries) {
              final f = (e.value as num?)?.toInt();
              if (f != null) targets[e.key.toString()] = f;
            }
          } else {
            final pkg = r.data['pkg']?.toString();
            final f = (r.data['floor'] as num?)?.toInt();
            if (pkg != null && f != null) targets[pkg] = f;
          }
          for (final e in targets.entries) {
            final cfg = appBox.get(e.key);
            if (cfg == null) continue;
            // 期限が来た時点から一時移動を開始する（本来のフロアを退避）
            cfg.permanentFloor ??= cfg.floor;
            cfg.floor = e.value;
            cfg.temporaryFloorExpiry = expiry;
            await cfg.save();
            await clearTempMode(e.key);
          }
          break;
        case ReservationKinds.scheduleAssign:
          final pkgs =
              (r.data['pkgs'] as List?)?.map((e) => e.toString()).toList() ??
              const <String>[];
          final schedule = r.data['schedule'];
          if (schedule is Map) {
            final id = r.data['scheduleId']?.toString() ?? newScheduleId();
            for (final pkg in pkgs) {
              await setAutoMoveSchedule(
                pkg,
                Map<String, dynamic>.from(schedule),
              );
              await setAutoMoveScheduleId(pkg, id);
              await setAutoMoveMode(pkg, 'schedule');
              await setAppMode(pkg, 'schedule');
              await clearUsageCountFloorRules(pkg);
              await clearUsageTimeFloorRules(pkg);
            }
            await removeSavedScheduleById(id);
          }
          break;
        case ReservationKinds.strictSubEnabled:
          final key = r.data['key']?.toString();
          final value = r.data['value'];
          if (key != null && value is bool) {
            await setStrictSubEnabled(key, value);
          }
          break;
        case ReservationKinds.strictSubType:
          final key = r.data['key']?.toString();
          final value = r.data['value']?.toString();
          if (key != null && value != null) await setStrictSubType(key, value);
          break;
        case ReservationKinds.strictSubTimer:
          final key = r.data['key']?.toString();
          final value = (r.data['value'] as num?)?.toInt();
          if (key != null && value != null) {
            await setStrictSubTimerMinutes(key, value);
          }
          break;
        case ReservationKinds.emergencyLimit:
          final value = r.data['value']?.toString();
          if (value != null) await setEmergencyLimit(value);
          break;
        case ReservationKinds.emergencyCap:
          final target = r.data['key']?.toString();
          final count = (r.data['count'] as num?)?.toInt();
          final period = r.data['period']?.toString();
          if (target == null || count == null || period == null) break;
          switch (target) {
            case 'all':
              await setEmergencyCapAll(count, period);
              break;
            case 'pick':
              await setEmergencyCapPick(count, period);
              break;
            case 'regGlobal':
              await setEmergencyCapRegisteredGlobal(count, period);
              break;
          }
          break;
        case ReservationKinds.emergencyApps:
          final apps =
              (r.data['apps'] as List?)?.map((e) => e.toString()).toList();
          if (apps != null) await setEmergencyApps(apps);
          break;
        case ReservationKinds.emergencyCapApp:
          final pkg = r.data['pkg']?.toString();
          final count = (r.data['count'] as num?)?.toInt();
          final period = r.data['period']?.toString();
          if (pkg != null && count != null && period != null) {
            await setEmergencyCapForApp(pkg, count, period);
          }
          break;
        case ReservationKinds.emergencyCapFolders:
          final folders = (r.data['folders'] as List?)
              ?.whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
          if (folders != null) await setEmergencyCapFolders(folders);
          break;
        case ReservationKinds.animationSpeed:
          final value = (r.data['value'] as num?)?.toInt();
          if (value != null) await setAnimationSpeedMs(value);
          break;
        case ReservationKinds.animationPairSpeed:
          final from = (r.data['from'] as num?)?.toInt();
          final to = (r.data['to'] as num?)?.toInt();
          final value = (r.data['value'] as num?)?.toInt();
          if (from != null && to != null && value != null) {
            if (value == -1) {
              await clearFloorPairSpeedMs(from, to);
            } else {
              await setFloorPairSpeedMs(from, to, value);
            }
          }
          break;
        case ReservationKinds.animationClearPairs:
          await clearAllFloorPairSpeeds();
          break;
      }
    }

    await _writeStrictReservations(all.where((r) => !r.isDue).toList());
    return due;
  }
}
