import 'package:flutter/material.dart';

import '../../l10n/s.dart';
import '../../models/app_config.dart';
import '../../services/app_service.dart';
import '../../services/settings_service.dart';
import '../home/home_screen.dart' show floorLabel, showStrictTimerDialog;
import '../modes/mode_actions.dart';

/// ストリクトモードの制限がかかった操作を通すための共通ゲート。
///
/// ホーム（フロア移動）とモード画面と設定画面から共用する。判定は:
///   1. サブモードOFF          → allowed（そのまま実行）
///   2. 完全ブロック            → denied
///   3. 予約変更ON かつ予約可能  → 「今すぐ待つ / 予約する」を選ばせる
///   4. それ以外                → タイマーダイアログ（設定した待ち時間）
enum StrictGateResult {
  /// すぐ実行してよい。
  allowed,

  /// 予約した。呼び出し側は何もしない（期限が来たら自動で適用される）。
  reserved,

  /// 実行不可（ブロック中／ユーザーがキャンセル）。
  denied,
}

/// [key] はストリクトのサブモードキー（'floorMove' / 'submode' / 'emergency'
/// / 'animation' / 'shortcut'）。
///
/// [reservationKind] を渡すと予約変更が使える。予約できない操作
/// （アニメーション速度・ショートカット）は null のままにする。
///
/// [treatBlockAsTimer] は「ロック自身の設定を変える」ときに使う。完全ブロック
/// でも待ち時間／予約でなら通す — でないとサブモード設定ロックを完全ブロック
/// にした瞬間、二度と解除できない状態になってしまう。
Future<StrictGateResult> requestStrictAction(
  BuildContext context,
  SettingsService ss, {
  required String key,
  required String blockedMessage,
  String? reservationKind,
  Map<String, dynamic>? reservationData,
  String? reservationLabel,
  bool treatBlockAsTimer = false,
}) async {
  if (!ss.strictSubEnabled(key)) return StrictGateResult.allowed;

  if (ss.strictSubType(key) == 'block' && !treatBlockAsTimer) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(blockedMessage)));
    }
    return StrictGateResult.denied;
  }

  final canReserve = ss.strictReservationEnabled &&
      reservationKind != null &&
      reservationData != null;

  if (canReserve) {
    final choice = await _askWaitOrReserve(context, ss);
    if (choice == null) return StrictGateResult.denied;
    if (choice == _StrictChoice.reserve) {
      final reservation = await ss.addStrictReservation(
        reservationKind,
        reservationLabel ?? '',
        reservationData,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              S.of(context).reservationCreated(
                formatClockTime(reservation.applyAt),
              ),
            ),
          ),
        );
      }
      return StrictGateResult.reserved;
    }
  }

  if (!context.mounted) return StrictGateResult.denied;
  final confirmed = await showStrictTimerDialog(
    context,
    seconds: ss.strictSubTimerSeconds(key),
  );
  return confirmed ? StrictGateResult.allowed : StrictGateResult.denied;
}

enum _StrictChoice { wait, reserve }

Future<_StrictChoice?> _askWaitOrReserve(
  BuildContext context,
  SettingsService ss,
) {
  return showDialog<_StrictChoice>(
    context: context,
    builder: (ctx) {
      final s = S.of(ctx);
      return AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: Text(
          s.strictModeTimerTitle,
          style: const TextStyle(color: Colors.orangeAccent, fontSize: 15),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              s.strictChoiceMessage,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const SizedBox(height: 12),
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(
                Icons.hourglass_bottom,
                color: Colors.orangeAccent,
                size: 20,
              ),
              title: Text(
                s.strictChoiceWaitNow,
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
              onTap: () => Navigator.pop(ctx, _StrictChoice.wait),
            ),
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(
                Icons.event_available,
                color: Colors.tealAccent,
                size: 20,
              ),
              title: Text(
                s.strictChoiceReserve,
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
              subtitle: Text(
                s.reservationAppliesIn(
                  formatDurationShort(
                    ctx,
                    Duration(minutes: ss.strictReservationMinutes),
                  ),
                ),
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),
              onTap: () => Navigator.pop(ctx, _StrictChoice.reserve),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              s.actionCancel,
              style: const TextStyle(color: Colors.white54),
            ),
          ),
        ],
      );
    },
  );
}

/// [floors]（pkg → フロア）をストリクトのロックを尊重しつつ適用する。
///
/// ロックされていないアプリはその場で移動し、ロック中のアプリだけを
/// ゲートに通す（待つ or 予約）。1個なら floorMove、複数なら floorMoveBulk の
/// 予約になる。戻り値 false = 何も適用されずキャンセル/ブロックされた。
Future<bool> applyFloorsWithStrictGate(
  BuildContext context,
  SettingsService ss,
  AppService appService,
  Map<String, int> floors,
  List<AppConfig> allApps,
) async {
  if (floors.isEmpty) return false;

  AppConfig configFor(String pkg) => allApps.firstWhere(
        (a) => a.packageName == pkg,
        orElse: () => AppConfig(packageName: pkg, appName: pkg, floor: 1),
      );

  Future<void> move(Iterable<String> pkgs) async {
    for (final pkg in pkgs) {
      // 一時移動中でも「本来のフロア」を書き換える（位置は期限切れで復帰）
      await appService.setPermanentFloor(configFor(pkg), floors[pkg]!);
    }
  }

  final locked = floors.keys.where(ss.isFloorMoveLocked).toList();
  final unlocked = floors.keys.where((p) => !ss.isFloorMoveLocked(p)).toList();

  // ロック無し — そのまま全部移動
  if (locked.isEmpty) {
    await move(unlocked);
    return true;
  }
  if (!context.mounted) return false;

  // 完全ブロック: ロック中は移動不可。ロック外だけ動かす。
  if (ss.strictSubType('floorMove') == 'block') {
    await move(unlocked);
    notifyFloorMoveLocked(context, allLocked: unlocked.isEmpty);
    return unlocked.isNotEmpty;
  }

  // タイマー／予約ゲート（ロック中アプリ）。確定するまでロック外も動かさない。
  final single = locked.length == 1 ? locked.first : null;
  final gate = await requestStrictAction(
    context,
    ss,
    key: 'floorMove',
    blockedMessage: unlocked.isEmpty
        ? S.of(context).floorMoveLockedAll
        : S.of(context).floorMoveLockedSome,
    reservationKind: single != null
        ? ReservationKinds.floorMove
        : ReservationKinds.floorMoveBulk,
    reservationData: single != null
        ? {'pkg': single, 'floor': floors[single]}
        : {'floors': {for (final pkg in locked) pkg: floors[pkg]}},
    reservationLabel: single != null
        ? S.of(context).reservationFloorMoveLabel(
            appLabelOf(configFor(single)), floorLabel(floors[single]!))
        : S.of(context).reservationFloorMoveBulkLabel(locked.length),
  );
  if (gate == StrictGateResult.allowed) {
    await move(unlocked);
    await move(locked);
    return true;
  }
  if (gate == StrictGateResult.reserved) {
    await move(unlocked); // ロック外は今すぐ、ロック中は予約で後から
    return true;
  }
  // キャンセル — ロック外をどうするか選ばせる
  return applyUnlockedAfterGateCancel(
      context, unlocked.length, locked.length, () => move(unlocked));
}

String appLabelOf(AppConfig app) {
  final custom = app.customName?.trim();
  if (custom != null && custom.isNotEmpty) return custom;
  final name = app.appName.trim();
  return name.isNotEmpty ? name : app.packageName;
}

/// 完全ブロックでロック中アプリを動かせなかったことを知らせる。
void notifyFloorMoveLocked(BuildContext context, {required bool allLocked}) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(allLocked
        ? S.of(context).floorMoveLockedAll
        : S.of(context).floorMoveLockedSome),
  ));
}

/// ゲート（今すぐ待つ／予約）をキャンセルしたときに「ロック外だけ移動する／
/// すべてキャンセルする」を選ばせる。ロック外が無ければ何もしない。
/// moveUnlocked が選ばれたら [applyUnlocked] を実行する。戻り値 = 何か適用したか。
Future<bool> applyUnlockedAfterGateCancel(
  BuildContext context,
  int unlockedCount,
  int lockedCount,
  Future<void> Function() applyUnlocked,
) async {
  if (unlockedCount == 0 || !context.mounted) return false;
  final choice = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF1A1A1A),
      title: Text(S.of(ctx).moveCancelTitle,
          style: const TextStyle(color: Colors.white, fontSize: 14)),
      content: Text(S.of(ctx).moveCancelMessage(lockedCount, unlockedCount),
          style: const TextStyle(color: Colors.white70, fontSize: 13)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(S.of(ctx).moveCancelAll,
              style: const TextStyle(color: Colors.redAccent)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(S.of(ctx).moveCancelUnlockedOnly,
              style: const TextStyle(color: Colors.white)),
        ),
      ],
    ),
  );
  if (choice == true) {
    await applyUnlocked();
    return true;
  }
  return false;
}

// ── 一時移動（フロア移動ロックを尊重）────────────────────────────────────────

/// 一時移動をストリクトのフロア移動ロックを尊重しつつ適用する。
/// ロックされていないアプリは即時、ロック中のアプリはゲート（待つか予約）。
/// フロア移動ロックの本来の待ち時間／予約と同じ扱いにする。
Future<bool> applyTempMoveWithStrictGate(
  BuildContext context,
  SettingsService ss,
  AppService appService,
  List<AppConfig> apps,
  TempMoveSpec spec,
) async {
  if (apps.isEmpty) return false;
  // モードの一時上書き（floor==null）は廃止済みだが、来たら素通しで適用
  if (spec.floor == null) {
    await applyTempMove(appService, ss, apps, spec);
    return true;
  }

  final locked =
      apps.where((a) => ss.isFloorMoveLocked(a.packageName)).toList();
  final unlocked =
      apps.where((a) => !ss.isFloorMoveLocked(a.packageName)).toList();

  if (locked.isEmpty) {
    await applyTempMove(appService, ss, unlocked, spec);
    return true;
  }
  if (!context.mounted) return false;

  if (ss.strictSubType('floorMove') == 'block') {
    await applyTempMove(appService, ss, unlocked, spec);
    notifyFloorMoveLocked(context, allLocked: unlocked.isEmpty);
    return unlocked.isNotEmpty;
  }

  final single = locked.length == 1 ? locked.first : null;
  final gate = await requestStrictAction(
    context,
    ss,
    key: 'floorMove',
    blockedMessage: unlocked.isEmpty
        ? S.of(context).floorMoveLockedAll
        : S.of(context).floorMoveLockedSome,
    reservationKind: ReservationKinds.tempMove,
    reservationData: single != null
        ? {
            'pkg': single.packageName,
            'floor': spec.floor,
            'minutes': spec.minutes,
          }
        : {
            'floors': {for (final a in locked) a.packageName: spec.floor},
            'minutes': spec.minutes,
          },
    reservationLabel: single != null
        ? S.of(context).reservationTempMoveLabel(
            appLabelOf(single), floorLabel(spec.floor!))
        : S.of(context).reservationTempMoveBulkLabel(locked.length),
  );
  if (gate == StrictGateResult.allowed) {
    await applyTempMove(appService, ss, [...unlocked, ...locked], spec);
    return true;
  }
  if (gate == StrictGateResult.reserved) {
    await applyTempMove(appService, ss, unlocked, spec);
    return true;
  }
  return applyUnlockedAfterGateCancel(context, unlocked.length, locked.length,
      () => applyTempMove(appService, ss, unlocked, spec));
}

// ── カスタム（スケジュール）割り当て ──────────────────────────────────────────

/// スケジュール割り当ての入口の結果。
enum ScheduleEntryResult { createNew, done, cancelled }

/// スケジュールモードのアプリを同一設定ごとにまとめたグループ。
/// スケジュールのまとまり。同一内容のアプリをまとめる。[apps] が空のものは
/// 「保存されたスケジュール」（アプリ0個のテンプレート）。
class ScheduleGroup {
  /// スケジュールの実体ID。内容が同じでも別々に作ったものは別ID。
  final String id;
  final Map<String, dynamic> schedule;
  final List<AppConfig> apps;
  const ScheduleGroup(this.id, this.schedule, this.apps);
  bool get isTemplate => apps.isEmpty;
}

/// ライブのスケジュールグループ＋保存されたテンプレート（アプリ0個）を
/// 同一内容ごとにまとめて返す。
List<ScheduleGroup> allScheduleGroups(
  SettingsService ss,
  List<AppConfig> apps,
) {
  final byId = <String, List<AppConfig>>{};
  final schedById = <String, Map<String, dynamic>>{};
  for (final a in apps.where((a) => ss.appMode(a.packageName) == 'schedule')) {
    final id = scheduleIdOf(ss, a.packageName);
    byId.putIfAbsent(id, () => []).add(a);
    schedById[id] = Map<String, dynamic>.from(
      ss.autoMoveSchedule(a.packageName),
    );
  }
  final out = <ScheduleGroup>[
    for (final e in byId.entries)
      ScheduleGroup(e.key, schedById[e.key]!, e.value),
  ];
  // 保存テンプレート（ライブに存在しないIDだけ）
  for (final tmpl in ss.savedSchedules) {
    if (byId.containsKey(tmpl.id)) continue;
    out.add(ScheduleGroup(tmpl.id, Map<String, dynamic>.from(tmpl.schedule),
        const []));
  }
  out.sort((a, b) => b.apps.length.compareTo(a.apps.length));
  return out;
}

/// [pkg] のスケジュール実体ID。未設定（移行前）のアプリはパッケージ名で
/// 単独グループになる。
String scheduleIdOf(SettingsService ss, String pkg) =>
    ss.autoMoveScheduleId(pkg) ?? 'pkg:$pkg';

/// スケジュールの短い要約（先頭アプリ名 or テンプレート表記）。
String scheduleGroupSubtitle(BuildContext context, ScheduleGroup g) {
  if (g.apps.isEmpty) return S.of(context).scheduleTemplateLabel;
  return g.apps.map(appLabelOf).take(3).join(', ');
}

/// スケジュールに属する最後のアプリをノーマルに戻すとき、そのスケジュールを
/// 残すか消すかを尋ねてから [pkgs] を解除する。残す場合はテンプレートとして
/// 保存し、「既存に追加」やカスタム一覧に現れる。
Future<void> releaseAppsWithSchedulePrompt(
  BuildContext context,
  SettingsService ss,
  List<AppConfig> allApps,
  List<String> pkgs,
) async {
  final releaseSet = pkgs.toSet();
  // schedule モードのアプリをスケジュール実体（ID）ごとにまとめる
  final byId = <String, List<AppConfig>>{};
  final schedById = <String, Map<String, dynamic>>{};
  for (final a in allApps.where((a) => ss.appMode(a.packageName) == 'schedule')) {
    final id = scheduleIdOf(ss, a.packageName);
    byId.putIfAbsent(id, () => []).add(a);
    schedById[id] = Map<String, dynamic>.from(
      ss.autoMoveSchedule(a.packageName),
    );
  }
  // 解除でアプリ0個になるスケジュールについて残す/消すを尋ねる
  for (final e in byId.entries) {
    final willBeEmpty =
        e.value.every((a) => releaseSet.contains(a.packageName));
    if (!willBeEmpty) continue;
    if (!context.mounted) break;
    final keep = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: Text(S.of(ctx).scheduleKeepTitle,
            style: const TextStyle(color: Colors.white, fontSize: 14)),
        content: Text(S.of(ctx).scheduleKeepMessage,
            style: const TextStyle(color: Colors.white70, fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(S.of(ctx).scheduleKeepDelete,
                style: const TextStyle(color: Colors.redAccent)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(S.of(ctx).scheduleKeepKeep,
                style: const TextStyle(color: Colors.tealAccent)),
          ),
        ],
      ),
    );
    if (keep == true) await ss.addSavedSchedule(e.key, schedById[e.key]!);
  }
  for (final pkg in pkgs) {
    await ss.releaseFromMode(pkg);
  }
}

/// [pkgs] をノーマルへ切り替え、続けて移動先フロアを選ぶ。
///
/// フロア選択を確定するまで解除（releaseFromMode）はしない。フロア選択を
/// キャンセルしたときは、元がノーマル以外なら「キャンセルすると元のモードの
/// ままになります」と確認し、キャンセルを選べば**解除せず元のモードのまま**に
/// する（フロアを選び直すなら戻る）。
///
/// 戻り値 true = ノーマルへ移行してフロアを適用した。
Future<bool> switchToNormalWithFloor(
  BuildContext context,
  SettingsService ss,
  AppService appService,
  List<AppConfig> allApps,
  List<String> pkgs, {
  int? initialFloor,
}) async {
  if (pkgs.isEmpty) return false;
  final wasAssigned = pkgs.any((p) => ss.appMode(p) != 'normal');

  AppConfig cfgFor(String pkg) => allApps.firstWhere(
        (a) => a.packageName == pkg,
        orElse: () => AppConfig(packageName: pkg, appName: pkg, floor: 1),
      );

  while (true) {
    if (!context.mounted) return false;
    final floor = await showFloorSelectDialog(
      context,
      ss,
      title: pkgs.length == 1
          ? S.of(context).moveFloorWithName(appLabelOf(cfgFor(pkgs.first)))
          : S.of(context).moveCount(pkgs.length),
      initial: initialFloor,
    );
    if (floor != null) {
      // フロア確定 → ここで初めて解除（残す/消すの確認込み）してフロア適用
      if (!context.mounted) return false;
      await releaseAppsWithSchedulePrompt(context, ss, allApps, pkgs);
      if (context.mounted) {
        await applyFloorsWithStrictGate(
          context,
          ss,
          appService,
          {for (final p in pkgs) p: floor},
          allApps,
        );
      }
      return true;
    }

    // フロア選択をキャンセル
    if (!wasAssigned) return false; // もともとノーマル — 何もしない
    if (!context.mounted) return false;
    final reallyCancel = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: Text(S.of(ctx).cancelKeepScheduleTitle,
            style: const TextStyle(color: Colors.white, fontSize: 14)),
        content: Text(S.of(ctx).cancelKeepScheduleMessage,
            style: const TextStyle(color: Colors.white70, fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(S.of(ctx).cancelKeepScheduleBack,
                style: const TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(S.of(ctx).actionCancel,
                style: const TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (reallyCancel == true) return false; // 元のモードのまま
    // 「戻る」→ ループしてフロア選択に戻る
  }
}

/// カスタム（スケジュール）を選んだときの入口。既存スケジュールがあれば
/// 「既存に追加 / 新規作成」を選ばせる。既存に追加ならその場で適用し
/// （ロック中アプリはゲート経由）、新規なら呼び出し側が編集画面を開く。
Future<ScheduleEntryResult> enterScheduleForApps(
  BuildContext context,
  SettingsService ss,
  List<AppConfig> allApps,
  List<String> pkgs,
) async {
  final groups = allScheduleGroups(ss, allApps);
  if (groups.isEmpty) return ScheduleEntryResult.createNew;

  final choice = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF1A1A1A),
      title: Text(S.of(ctx).customSection,
          style: const TextStyle(color: Colors.white, fontSize: 14)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.playlist_add, color: Colors.white54),
            title: Text(S.of(ctx).scheduleAddToExisting,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 13)),
            onTap: () => Navigator.pop(ctx, true),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.edit_calendar, color: Colors.white54),
            title: Text(S.of(ctx).scheduleCreateNew,
                style: const TextStyle(color: Colors.white, fontSize: 13)),
            onTap: () => Navigator.pop(ctx, false),
          ),
        ],
      ),
    ),
  );
  if (choice == null) return ScheduleEntryResult.cancelled;
  if (choice == false) return ScheduleEntryResult.createNew;
  if (!context.mounted) return ScheduleEntryResult.cancelled;

  final picked = await showDialog<int>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF1A1A1A),
      title: Text(S.of(ctx).scheduleAddToExisting,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white, fontSize: 14)),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: groups.length,
          itemBuilder: (_, i) {
            final group = groups[i];
            return ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                group.isTemplate
                    ? S.of(ctx).scheduleTemplateLabel
                    : S.of(ctx).groupAppsCount(group.apps.length),
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
              subtitle: Text(
                scheduleGroupSubtitle(ctx, group),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
              onTap: () => Navigator.pop(ctx, i),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(S.of(ctx).actionCancel,
              style: const TextStyle(color: Colors.white54)),
        ),
      ],
    ),
  );
  if (picked == null || !context.mounted) {
    return ScheduleEntryResult.cancelled;
  }
  final applied = await applyScheduleToAppsWithGate(
      context, ss, groups[picked].schedule, pkgs,
      scheduleId: groups[picked].id);
  return applied ? ScheduleEntryResult.done : ScheduleEntryResult.cancelled;
}

/// [pkgs] にスケジュール [schedule] を割り当てる（直接・ゲート無し）。
/// [scheduleId] を渡すとそのスケジュール実体に合流する（＝同じグループ）。
/// 省略すると新しい実体になる（内容が同じでも別スケジュール扱い）。
Future<void> applyScheduleToApps(
  SettingsService ss,
  List<String> pkgs,
  Map<String, dynamic> schedule, {
  String? scheduleId,
}) async {
  if (pkgs.isEmpty) return;
  final id = scheduleId ?? ss.newScheduleId();
  for (final pkg in pkgs) {
    await ss.setAutoMoveSchedule(pkg, Map<String, dynamic>.from(schedule));
    await ss.setAutoMoveScheduleId(pkg, id);
    await ss.setAutoMoveMode(pkg, 'schedule');
    await ss.setAppMode(pkg, 'schedule');
    await ss.clearUsageCountFloorRules(pkg);
    await ss.clearUsageTimeFloorRules(pkg);
  }
  // テンプレートにアプリが付いたのでテンプレートとしては不要
  await ss.removeSavedScheduleById(id);
}

/// スケジュール割り当てをフロア移動ロックを尊重して適用する。
/// ロック中のアプリはゲート（待つか予約）を挟む — でないと移動ロックを
/// スケジュール割り当てで迂回できてしまう。戻り値 false = 全キャンセル。
Future<bool> applyScheduleToAppsWithGate(
  BuildContext context,
  SettingsService ss,
  Map<String, dynamic> schedule,
  List<String> pkgs, {
  String? scheduleId,
}) async {
  if (pkgs.isEmpty) return false;
  final locked = pkgs.where(ss.isFloorMoveLocked).toList();
  final unlocked = pkgs.where((p) => !ss.isFloorMoveLocked(p)).toList();

  // 実体IDを先に決めておく（ロック外とロック中で同じスケジュールに揃える）
  final id = scheduleId ?? ss.newScheduleId();

  if (locked.isEmpty) {
    await applyScheduleToApps(ss, unlocked, schedule, scheduleId: id);
    return true;
  }
  if (!context.mounted) return false;

  if (ss.strictSubType('floorMove') == 'block') {
    await applyScheduleToApps(ss, unlocked, schedule, scheduleId: id);
    notifyFloorMoveLocked(context, allLocked: unlocked.isEmpty);
    return unlocked.isNotEmpty;
  }

  final gate = await requestStrictAction(
    context,
    ss,
    key: 'floorMove',
    blockedMessage: unlocked.isEmpty
        ? S.of(context).floorMoveLockedAll
        : S.of(context).floorMoveLockedSome,
    reservationKind: ReservationKinds.scheduleAssign,
    reservationData: {
      'pkgs': locked,
      'schedule': Map<String, dynamic>.from(schedule),
      'scheduleId': id,
    },
    reservationLabel: S.of(context).reservationScheduleLabel(locked.length),
  );
  if (gate == StrictGateResult.allowed) {
    await applyScheduleToApps(ss, [...unlocked, ...locked], schedule,
        scheduleId: id);
    return true;
  }
  if (gate == StrictGateResult.reserved) {
    await applyScheduleToApps(ss, unlocked, schedule, scheduleId: id);
    return true;
  }
  return applyUnlockedAfterGateCancel(
      context,
      unlocked.length,
      locked.length,
      () => applyScheduleToApps(ss, unlocked, schedule, scheduleId: id));
}

// ── 表示用ヘルパー ────────────────────────────────────────────────────────────

String formatClockTime(DateTime t) =>
    '${t.hour.toString().padLeft(2, "0")}:${t.minute.toString().padLeft(2, "0")}';

String formatDurationShort(BuildContext context, Duration d) {
  final s = S.of(context);
  if (d.isNegative) return s.tempExpired;
  final h = d.inHours;
  final m = d.inMinutes % 60;
  return h > 0 ? s.durationHourMinute(h, m) : s.durationMinute(d.inMinutes);
}

// ── 予約状況の画面 ────────────────────────────────────────────────────────────

/// 現在の予約一覧。残り時間の表示と、個別／一括のキャンセルができる。
class StrictReservationsScreen extends StatefulWidget {
  final SettingsService settingsService;
  const StrictReservationsScreen({super.key, required this.settingsService});

  @override
  State<StrictReservationsScreen> createState() =>
      _StrictReservationsScreenState();
}

class _StrictReservationsScreenState extends State<StrictReservationsScreen> {
  SettingsService get _ss => widget.settingsService;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final reservations = _ss.strictReservations;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(
          s.reservationsTitle,
          style: const TextStyle(color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (reservations.isNotEmpty)
            TextButton(
              onPressed: _confirmCancelAll,
              child: Text(
                s.reservationCancelAll,
                style: const TextStyle(color: Colors.redAccent, fontSize: 12),
              ),
            ),
        ],
      ),
      body: reservations.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  s.reservationsEmpty,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white38, fontSize: 13),
                ),
              ),
            )
          : ListView.separated(
              itemCount: reservations.length,
              separatorBuilder: (_, _) =>
                  const Divider(color: Colors.white12, height: 1),
              itemBuilder: (_, i) {
                final r = reservations[i];
                final due = r.isDue;
                return ListTile(
                  leading: Icon(
                    due ? Icons.check_circle_outline : Icons.event_available,
                    color: due ? Colors.tealAccent : Colors.orangeAccent,
                    size: 20,
                  ),
                  title: Text(
                    r.label.isNotEmpty ? r.label : r.kind,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
                  subtitle: Text(
                    due
                        ? s.reservationApplyingSoon
                        : '${formatClockTime(r.applyAt)}  '
                              '(${s.tempRemaining(formatDurationShort(context, r.remaining))})',
                    style: TextStyle(
                      color: due ? Colors.tealAccent : Colors.white38,
                      fontSize: 11,
                    ),
                  ),
                  trailing: IconButton(
                    icon: const Icon(
                      Icons.close,
                      color: Colors.redAccent,
                      size: 18,
                    ),
                    onPressed: () async {
                      await _ss.cancelStrictReservation(r.id);
                      if (mounted) setState(() {});
                    },
                  ),
                );
              },
            ),
    );
  }

  Future<void> _confirmCancelAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: Text(
          S.of(ctx).reservationCancelAll,
          style: const TextStyle(color: Colors.white, fontSize: 14),
        ),
        content: Text(
          S.of(ctx).reservationCancelAllConfirm,
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              S.of(ctx).actionCancel,
              style: const TextStyle(color: Colors.white54),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              S.of(ctx).actionConfirm,
              style: const TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _ss.clearStrictReservations();
    if (mounted) setState(() {});
  }
}
