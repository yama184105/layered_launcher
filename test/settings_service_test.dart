import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:layered_launcher/models/app_config.dart';
import 'package:layered_launcher/services/settings_service.dart';

/// サービス層は UI に依存しないのでそのままテストできる。日時に絡む
/// ロジック（予約の適用、一時モードの期限切れ）が手動確認頼みだったので
/// ここで押さえる。
void main() {
  late Directory dir;
  late SettingsService ss;
  late Box<AppConfig> appBox;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('layered_launcher_test');
    Hive.init(dir.path);
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(AppConfigAdapter());
    }
    ss = SettingsService();
    await ss.init();
    appBox = await Hive.openBox<AppConfig>('app_configs');
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    await Hive.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Future<AppConfig> putApp(String pkg, {int floor = 1}) async {
    final cfg = AppConfig(packageName: pkg, appName: pkg, floor: floor);
    await appBox.put(pkg, cfg);
    return cfg;
  }

  // ── モード ────────────────────────────────────────────────────────────
  group('app modes', () {
    test('normal is the implicit default and stores no key', () async {
      expect(ss.appMode('a.b.c'), 'normal');
      await ss.setAppMode('a.b.c', 'schedule');
      expect(ss.appMode('a.b.c'), 'schedule');
      await ss.setAppMode('a.b.c', 'normal');
      expect(ss.appMode('a.b.c'), 'normal');
      expect(ss.allModeAssignedApps, isNot(contains('a.b.c')));
    });

    test('temp mode overrides until it expires', () async {
      await ss.setAppMode('x', 'schedule');
      await ss.setTempMode('x', 'normal',
          DateTime.now().add(const Duration(minutes: 5)));
      expect(ss.effectiveAppMode('x'), 'normal');
      expect(ss.hasTempMode('x'), isTrue);

      await ss.setTempMode('x', 'normal',
          DateTime.now().subtract(const Duration(seconds: 1)));
      expect(ss.hasTempMode('x'), isFalse);
      // 期限切れ後は所属モードへ戻る（フロアは位置保持）
      expect(ss.effectiveAppMode('x'), 'schedule');
    });

    test('releaseFromMode clears rules and temp state', () async {
      await ss.setAppMode('y', 'usageCount');
      await ss.setUsageCountFloorRules('y', [
        {'threshold': 3, 'floor': 5},
      ]);
      await ss.setTempMode(
          'y', 'normal', DateTime.now().add(const Duration(hours: 1)));

      await ss.releaseFromMode('y');
      expect(ss.appMode('y'), 'normal');
      expect(ss.hasTempMode('y'), isFalse);
      expect(ss.usageCountFloorRules('y'), isEmpty);
    });
  });

  // ── ストリクト ────────────────────────────────────────────────────────
  group('strict sub-modes', () {
    test('timer seconds follow the configured minutes', () async {
      expect(ss.strictSubTimerMinutes('floorMove'), 3);
      expect(ss.strictSubTimerSeconds('floorMove'), 180);
      await ss.setStrictSubTimerMinutes('floorMove', 7);
      expect(ss.strictSubTimerSeconds('floorMove'), 420);
    });

    test('cooldown uses the configured minutes, not a fixed 10s', () async {
      await ss.setStrictSubTimerMinutes('floorMove', 5);
      await ss.startStrictSubCooldown('floorMove');
      final remaining = ss.strictSubCooldownRemaining('floorMove')!;
      expect(remaining.inMinutes, greaterThanOrEqualTo(4));
    });

    test('empty locked-app list means every app is locked', () async {
      expect(ss.isFloorMoveLocked('any'), isFalse); // sub-mode off
      await ss.setStrictSubEnabled('floorMove', true);
      expect(ss.isFloorMoveLocked('any'), isTrue);
      await ss.addFloorMoveLockedApps(['only.this']);
      expect(ss.isFloorMoveLocked('only.this'), isTrue);
      expect(ss.isFloorMoveLocked('other'), isFalse);
    });
  });

  // ── 予約変更 ──────────────────────────────────────────────────────────
  group('strict reservations', () {
    test('a reservation applies only once its time has come', () async {
      await putApp('app.one', floor: 1);
      await ss.setStrictReservationMinutes(60);
      await ss.addStrictReservation(
        ReservationKinds.floorMove,
        'move',
        {'pkg': 'app.one', 'floor': 4},
      );

      expect(ss.hasDueStrictReservations, isFalse);
      expect(await ss.applyDueStrictReservations(appBox), isEmpty);
      expect(appBox.get('app.one')!.floor, 1);

      // 期限を過去にずらして再確認
      await ss.setStrictReservationMinutes(-1);
      await ss.addStrictReservation(
        ReservationKinds.floorMove,
        'move',
        {'pkg': 'app.one', 'floor': 4},
      );
      expect(ss.hasDueStrictReservations, isTrue);
      final applied = await ss.applyDueStrictReservations(appBox);
      expect(applied, hasLength(1));
      expect(appBox.get('app.one')!.floor, 4);
      expect(ss.strictReservations, isEmpty);
    });

    test('same target replaces the previous reservation', () async {
      await ss.addStrictReservation(
          ReservationKinds.floorMove, 'a', {'pkg': 'p', 'floor': 2});
      await ss.addStrictReservation(
          ReservationKinds.floorMove, 'b', {'pkg': 'p', 'floor': 3});
      expect(ss.strictReservations, hasLength(1));
      expect(ss.strictReservations.single.data['floor'], 3);

      // 別アプリは別の予約として残る
      await ss.addStrictReservation(
          ReservationKinds.floorMove, 'c', {'pkg': 'q', 'floor': 9});
      expect(ss.strictReservations, hasLength(2));
    });

    test('per-pair animation reservations do not collide', () async {
      await ss.addStrictReservation(ReservationKinds.animationPairSpeed, 'a',
          {'from': 1, 'to': 2, 'value': 300});
      await ss.addStrictReservation(ReservationKinds.animationPairSpeed, 'b',
          {'from': 2, 'to': 3, 'value': 400});
      expect(ss.strictReservations, hasLength(2));
    });

    test('cancelling removes just that reservation', () async {
      final a = await ss.addStrictReservation(
          ReservationKinds.floorMove, 'a', {'pkg': 'p', 'floor': 2});
      await ss.addStrictReservation(
          ReservationKinds.floorMove, 'b', {'pkg': 'q', 'floor': 3});
      await ss.cancelStrictReservation(a.id);
      expect(ss.strictReservations, hasLength(1));
      expect(ss.strictReservations.single.data['pkg'], 'q');
    });

    test('nextReservationDueMs tracks the earliest entry', () async {
      expect(ss.nextReservationDueMs, isNull);
      await ss.setStrictReservationMinutes(120);
      final late = await ss.addStrictReservation(
          ReservationKinds.floorMove, 'l', {'pkg': 'p', 'floor': 2});
      await ss.setStrictReservationMinutes(30);
      final soon = await ss.addStrictReservation(
          ReservationKinds.floorMove, 's', {'pkg': 'q', 'floor': 2});
      expect(ss.nextReservationDueMs, soon.applyAt.millisecondsSinceEpoch);
      expect(ss.nextReservationDueMs,
          lessThan(late.applyAt.millisecondsSinceEpoch));

      await ss.clearStrictReservations();
      expect(ss.nextReservationDueMs, isNull);
    });

    test('floorMoveBulk moves every listed app', () async {
      await putApp('a');
      await putApp('b');
      await ss.setStrictReservationMinutes(-1);
      await ss.addStrictReservation(ReservationKinds.floorMoveBulk, 'bulk', {
        'floors': {'a': 3, 'b': 5},
      });
      await ss.applyDueStrictReservations(appBox);
      expect(appBox.get('a')!.floor, 3);
      expect(appBox.get('b')!.floor, 5);
    });

    test('tempMove reservation starts a temporary move on fire', () async {
      final cfg = await putApp('t.app', floor: 2);
      await ss.setStrictReservationMinutes(-1);
      await ss.addStrictReservation(ReservationKinds.tempMove, 'tm', {
        'pkg': 't.app',
        'floor': 5,
        'minutes': 30,
      });
      await ss.applyDueStrictReservations(appBox);
      final after = appBox.get('t.app')!;
      expect(after.floor, 5, reason: '一時移動先へ');
      expect(after.permanentFloor, 2, reason: '本来のフロアを退避');
      expect(after.temporaryFloorExpiry, isNotNull);
      expect(after.temporaryFloorExpiry!.isAfter(DateTime.now()), isTrue);
      cfg.floor; // silence unused
    });

    test('scheduleAssign reservation assigns schedule mode on fire', () async {
      await putApp('s1');
      await putApp('s2');
      await ss.setStrictReservationMinutes(-1);
      await ss.addStrictReservation(ReservationKinds.scheduleAssign, 'sa', {
        'pkgs': ['s1', 's2'],
        'scheduleId': 'sch-x',
        'schedule': {
          '1': {
            'default': {'type': 'keep'},
            'slots': const [],
          },
        },
      });
      await ss.applyDueStrictReservations(appBox);
      expect(ss.appMode('s1'), 'schedule');
      expect(ss.appMode('s2'), 'schedule');
      expect(ss.autoMoveSchedule('s1')['1'], isA<Map>());
      // 同じ予約で入ったアプリは同じスケジュール実体に属する
      expect(ss.autoMoveScheduleId('s1'), 'sch-x');
      expect(ss.autoMoveScheduleId('s2'), 'sch-x');
    });

    test('releaseFromMode clears the schedule identity', () async {
      await putApp('s3');
      await ss.setAppMode('s3', 'schedule');
      await ss.setAutoMoveScheduleId('s3', 'sch-y');
      expect(ss.autoMoveScheduleId('s3'), 'sch-y');
      await ss.releaseFromMode('s3');
      expect(ss.autoMoveScheduleId('s3'), isNull);
    });

    test('a temporary override keeps its floor; the baseline moves', () async {
      final cfg = await putApp('temp.app', floor: 2);
      cfg.permanentFloor = 2;
      cfg.floor = 1; // 一時的に1Fへ移動中
      cfg.temporaryFloorExpiry = DateTime.now().add(const Duration(hours: 1));
      await cfg.save();

      await ss.setStrictReservationMinutes(-1);
      await ss.addStrictReservation(
          ReservationKinds.floorMove, 'm', {'pkg': 'temp.app', 'floor': 7});
      await ss.applyDueStrictReservations(appBox);

      final after = appBox.get('temp.app')!;
      expect(after.floor, 1, reason: '一時移動先はそのまま');
      expect(after.permanentFloor, 7, reason: '本来のフロアだけ書き換わる');
    });
  });

  // ── レガシー移行 ──────────────────────────────────────────────────────
  group('legacy lock migration', () {
    test('turns lockMode into a floorMove timer lock and drains pending',
        () async {
      await putApp('pending.app', floor: 1);
      final box = await Hive.openBox<dynamic>('global_settings');
      await box.put('lockMode', true);
      await box.put('pendingFloorMap', {'pending.app': 6});

      await ss.migrateLegacyLockIfNeeded(appBox);

      expect(appBox.get('pending.app')!.floor, 6);
      expect(ss.strictSubEnabled('floorMove'), isTrue);
      expect(ss.strictSubType('floorMove'), 'timer');
      expect(box.get('lockMode'), isNull);
      expect(box.get('pendingFloorMap'), isNull);

      // 2回目は何もしない
      await ss.setStrictSubEnabled('floorMove', false);
      await ss.migrateLegacyLockIfNeeded(appBox);
      expect(ss.strictSubEnabled('floorMove'), isFalse);
    });
  });

  // ── 保存されたスケジュール（テンプレート）────────────────────────────
  group('saved schedules', () {
    final sched = {
      '1': {
        'default': {'type': 'keep'},
        'slots': const [],
      },
    };

    test('add is idempotent per id; remove drops it', () async {
      await ss.addSavedSchedule('id-1', Map<String, dynamic>.from(sched));
      await ss.addSavedSchedule('id-1', Map<String, dynamic>.from(sched));
      expect(ss.savedSchedules, hasLength(1));
      expect(ss.savedSchedules.single.id, 'id-1');

      await ss.removeSavedScheduleById('id-1');
      expect(ss.savedSchedules, isEmpty);
    });

    test('same content under a different id stays a separate schedule',
        () async {
      // 内容が同じでも別々に作ったスケジュールは合体させない
      await ss.addSavedSchedule('id-a', Map<String, dynamic>.from(sched));
      await ss.addSavedSchedule('id-b', Map<String, dynamic>.from(sched));
      expect(ss.savedSchedules, hasLength(2));
      expect(ss.savedSchedules.map((s) => s.id), containsAll(['id-a', 'id-b']));
    });

    test('canonical ignores key order', () {
      final a = ss.scheduleCanonical({'a': 1, 'b': 2});
      final b = ss.scheduleCanonical({'b': 2, 'a': 1});
      expect(a, b);
    });
  });

  // ── 使用時間ルール ────────────────────────────────────────────────────
  group('usage-time rules', () {
    test('picks the highest satisfied threshold, else keeps position', () async {
      await ss.setUsageTimeFloorRules('u', [
        {'threshold': 10, 'floor': 3},
        {'threshold': 30, 'floor': 6},
      ]);
      expect(ss.usageTimeTargetFloor('u', 5), isNull, reason: '閾値未満は位置保持');
      expect(ss.usageTimeTargetFloor('u', 10), 3);
      expect(ss.usageTimeTargetFloor('u', 45), 6);
    });
  });

  // ── バックアップ ──────────────────────────────────────────────────────
  group('backup', () {
    test('round-trips settings and app placement through JSON', () async {
      await ss.setStrictSubEnabled('floorMove', true);
      await ss.setAppMode('sched.app', 'schedule');
      await ss.setAutoMoveSchedule('sched.app', {
        '1': {
          'default': {'type': 'keep'},
          'slots': [
            {'startMinute': 540, 'endMinute': 1080, 'type': 'fixed', 'floor': 4},
          ],
        },
      });
      final cfg = await putApp('placed.app', floor: 8);
      cfg.customName = 'Renamed';
      cfg.isPinned = true;
      await cfg.save();

      final json = ss.buildBackupJson(appBox);
      // 旧実装と違い、本物の JSON として読める
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      expect(decoded['version'], kBackupFormatVersion);
      expect(decoded['apps'], isNotEmpty);

      // 別の状態から復元して元に戻ることを確認
      await ss.setStrictSubEnabled('floorMove', false);
      await ss.releaseFromMode('sched.app');
      cfg.floor = 1;
      cfg.customName = null;
      cfg.isPinned = false;
      await cfg.save();

      final restored = await ss.restoreBackupJson(json, appBox);
      expect(restored, greaterThanOrEqualTo(1));
      expect(ss.strictSubEnabled('floorMove'), isTrue);
      expect(ss.appMode('sched.app'), 'schedule');
      expect(ss.autoMoveSchedule('sched.app')['1'], isA<Map>());
      final back = appBox.get('placed.app')!;
      expect(back.floor, 8);
      expect(back.customName, 'Renamed');
      expect(back.isPinned, isTrue);
    });

    test('rejects anything that is not a backup', () async {
      expect(() => ss.restoreBackupJson('{"hello":1}', appBox),
          throwsA(isA<FormatException>()));
      expect(() => ss.restoreBackupJson('not json', appBox),
          throwsA(isA<FormatException>()));
    });

    test('preserves DateTime values across the round trip', () async {
      final when = DateTime.now().add(const Duration(days: 2));
      final cfg = await putApp('dt.app');
      cfg.emergencyUntil = when;
      await cfg.save();

      final json = ss.buildBackupJson(appBox);
      cfg.emergencyUntil = null;
      await cfg.save();

      await ss.restoreBackupJson(json, appBox);
      expect(appBox.get('dt.app')!.emergencyUntil!.millisecondsSinceEpoch,
          when.millisecondsSinceEpoch);
    });
  });
}
