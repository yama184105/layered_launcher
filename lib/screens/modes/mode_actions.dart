import 'package:flutter/material.dart';

import '../../l10n/s.dart';
import '../../models/app_config.dart';
import '../../services/app_service.dart';
import '../../services/settings_service.dart';
import '../home/home_screen.dart' show floorLabel;

/// モード関連の共通UI/処理。ホーム画面（アプリ一覧）とモード画面の
/// 両方から使うため、どちらの part にも属さない独立ライブラリに置く。
///
/// 扱うモード:
///   normal / schedule / usageCount / usageTime  … 所属モード（排他）
///   temp                                        … 一時的（期限つきの上書き）
///
/// 「一時的」はフロアの一時移動（AppConfig.permanentFloor +
/// temporaryFloorExpiry）とモードの一時上書き（tempMode_ キー）の
/// どちらでも表現できる。期限切れの復帰はホーム画面の _tick と
/// SettingsService.effectiveAppMode が担当する。

const String kModeTemp = 'temp';

/// カスタム＝スケジュール。モードは「ノーマル / カスタム / 一時的」の3つだけで、
/// カスタムを選ぶとスケジュール編集画面へ進む（使用回数・使用時間はスケジュール
/// のスロット種別として内包されるので、独立したモードにはしない）。
const String kModeCustom = 'custom';

/// showModeSelectSheet の戻り値のうち、モード名ではない特別な値。
/// - release:     所属モードから外してノーマルへ（フロアは位置保持）
/// - tempRelease: 一時的な上書きだけを取り消す（所属モードはそのまま）
const String kModeActionRelease = 'release';
const String kModeActionTempRelease = 'tempRelease';

/// アプリの所属モードが「カスタム」（＝ノーマル以外）か。
bool isCustomMode(String mode) => mode != 'normal';

String modeLabel(BuildContext ctx, String mode) {
  final s = S.of(ctx);
  switch (mode) {
    case 'schedule':
      return s.modeScheduleName;
    case 'usageCount':
      return s.modeUsageCount;
    case 'usageTime':
      return s.modeUsageTime;
    case kModeTemp:
      return s.modeTemp;
    default:
      return s.modeNormal;
  }
}

IconData modeIcon(String mode) {
  switch (mode) {
    case 'schedule':
      return Icons.schedule;
    case 'usageCount':
      return Icons.tag;
    case 'usageTime':
      return Icons.hourglass_bottom;
    case kModeTemp:
      return Icons.timelapse;
    default:
      return Icons.apps;
  }
}

String appLabel(AppConfig app) {
  final custom = app.customName?.trim();
  if (custom != null && custom.isNotEmpty) return custom;
  final name = app.appName.trim();
  return name.isNotEmpty ? name : app.packageName;
}

/// 使用回数／使用時間ルールを「区間」表示にする。
///
/// ルールは各しきい値を区間の開始点として扱い、次のしきい値の直前までを
/// その階に割り当てる（最後は「以上」）。
/// 例: しきい値 [1→3F, 3→5F] → ["1〜2回 → 3F", "3回以上 → 5F"]
List<String> usageRangeLabels(
  S s,
  List<Map<String, int>> rules, {
  required bool isTime,
}) {
  final sorted = [...rules]
    ..sort((a, b) => a['threshold']!.compareTo(b['threshold']!));
  final out = <String>[];
  for (var i = 0; i < sorted.length; i++) {
    final lo = sorted[i]['threshold']!;
    final floor = floorLabel(sorted[i]['floor']!);
    final isLast = i == sorted.length - 1;
    if (isLast) {
      out.add(isTime
          ? s.minuteThresholdRule(lo, floor)
          : s.thresholdRule(lo, floor));
      continue;
    }
    final hi = sorted[i + 1]['threshold']! - 1;
    if (hi <= lo) {
      out.add(isTime ? s.timeExactRule(lo, floor) : s.countExactRule(lo, floor));
    } else {
      out.add(isTime
          ? s.timeRangeRule(lo, hi, floor)
          : s.countRangeRule(lo, hi, floor));
    }
  }
  return out;
}

// ── 一時的モードの状態 ───────────────────────────────────────────────────────

/// アプリに掛かっている一時的な上書き。フロア移動とモード上書きは
/// 排他（applyTempMove が片方を消してからもう片方を書く）。
class TempState {
  /// 一時移動先のフロア。モード上書きのときは null。
  final int? floor;

  /// 一時的な所属モード。フロア移動のときは null。
  final String? mode;

  /// 元に戻る時刻。
  final DateTime expiry;

  const TempState({this.floor, this.mode, required this.expiry});

  Duration get remaining => expiry.difference(DateTime.now());
}

TempState? tempStateOf(SettingsService ss, AppConfig app) {
  final floorExpiry = app.temporaryFloorExpiry;
  if (floorExpiry != null && floorExpiry.isAfter(DateTime.now())) {
    return TempState(floor: app.floor, expiry: floorExpiry);
  }
  final mode = ss.tempMode(app.packageName);
  final expiry = ss.tempModeExpiry(app.packageName);
  if (mode != null && expiry != null && expiry.isAfter(DateTime.now())) {
    return TempState(mode: mode, expiry: expiry);
  }
  return null;
}

/// 「一時: 3F（残り 1時間20分）」のような1行サマリー。
String tempStateSummary(BuildContext ctx, TempState state) {
  final s = S.of(ctx);
  final target = state.floor != null
      ? floorLabel(state.floor!)
      : modeLabel(ctx, state.mode ?? 'normal');
  return '${s.tempModeActive(target)}・${s.tempRemaining(_fmtRemaining(ctx, state.remaining))}';
}

String _fmtRemaining(BuildContext ctx, Duration d) {
  final s = S.of(ctx);
  if (d.isNegative) return s.tempExpired;
  final h = d.inHours;
  final m = d.inMinutes % 60;
  return h > 0 ? s.durationHourMinute(h, m) : s.durationMinute(d.inMinutes);
}

// ── 一時的モードの適用 ───────────────────────────────────────────────────────

/// 一時的モードの内容。[floor] と [mode] はどちらか一方だけを設定する。
class TempMoveSpec {
  final int? floor;
  final String? mode;
  final int minutes;
  const TempMoveSpec({this.floor, this.mode, required this.minutes});
}

Future<void> applyTempMove(
  AppService appService,
  SettingsService ss,
  List<AppConfig> apps,
  TempMoveSpec spec,
) async {
  final expiry = DateTime.now().add(Duration(minutes: spec.minutes));
  for (final app in apps) {
    if (spec.floor != null) {
      // フロアの一時移動 — 既存のモード上書きは打ち消す
      await ss.clearTempMode(app.packageName);
      await appService.setTemporaryFloor(app, floor: spec.floor!, expiry: expiry);
    } else if (spec.mode != null) {
      // モードの一時上書き — フロアは位置保持
      await appService.clearTemporaryFloor(app);
      await ss.setTempMode(app.packageName, spec.mode!, expiry);
    }
  }
}

Future<void> clearTempMove(
  AppService appService,
  SettingsService ss,
  List<AppConfig> apps,
) async {
  for (final app in apps) {
    await ss.clearTempMode(app.packageName);
    await appService.clearTemporaryFloor(app);
  }
}

// ── ダイアログ / シート ──────────────────────────────────────────────────────

Widget _chip(String label, bool selected, VoidCallback onTap) {
  return GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: selected ? Colors.white : Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: selected ? Colors.white : Colors.white24),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: selected ? Colors.black : Colors.white54,
          fontSize: 12,
        ),
      ),
    ),
  );
}

Widget _sheetRow(
  BuildContext ctx,
  IconData icon,
  String label, {
  String? subtitle,
  required VoidCallback onTap,
  Color color = Colors.white,
  bool checked = false,
}) {
  return Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
        child: Row(
          children: [
            Icon(icon, color: color.withValues(alpha: 0.7), size: 22),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: TextStyle(color: color, fontSize: 15)),
                  if (subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        subtitle,
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 11,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (checked) const Icon(Icons.check, color: Colors.white, size: 18),
          ],
        ),
      ),
    ),
  );
}

/// モード選択シート。戻り値は 'normal' | 'schedule' | 'usageCount' |
/// 'usageTime' | [kModeTemp] | [kModeActionRelease] |
/// [kModeActionTempRelease]、キャンセルで null。
///
/// [statusText] を渡すと見出し右の「現在: ○○」の代わりに表示する
/// （一時的な上書き中の残り時間など）。
Future<String?> showModeSelectSheet(
  BuildContext context, {
  required String title,
  String? currentMode,
  String? statusText,
  Color statusColor = Colors.orangeAccent,
  bool showTemp = true,
  bool showRelease = false,
  bool showTempRelease = false,
}) {
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: const Color(0xFF1A1A1A),
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) {
      final s = S.of(ctx);
      return Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewPadding.bottom),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.symmetric(vertical: 8),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    if (statusText != null)
                      Text(
                        statusText,
                        style: TextStyle(color: statusColor, fontSize: 11),
                      )
                    else if (currentMode != null)
                      Text(
                        s.currentModeLabel(modeLabel(ctx, currentMode)),
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 11,
                        ),
                      ),
                  ],
                ),
              ),
              const Divider(color: Colors.white12, height: 1),
              _sheetRow(
                ctx,
                Icons.apps,
                s.modeNormal,
                subtitle: s.modeNormalDesc,
                checked: currentMode == 'normal',
                onTap: () => Navigator.pop(ctx, 'normal'),
              ),
              _sheetRow(
                ctx,
                Icons.tune,
                s.customSection,
                subtitle: s.modeCustomDesc,
                checked: currentMode != null && isCustomMode(currentMode),
                onTap: () => Navigator.pop(ctx, kModeCustom),
              ),
              if (showTemp || showTempRelease) ...[
                const Divider(color: Colors.white12, height: 1),
                if (showTemp)
                  _sheetRow(
                    ctx,
                    Icons.timelapse,
                    s.modeTemp,
                    subtitle: s.modeTempDesc,
                    color: Colors.orangeAccent,
                    onTap: () => Navigator.pop(ctx, kModeTemp),
                  ),
                if (showTempRelease)
                  _sheetRow(
                    ctx,
                    Icons.undo,
                    s.tempMoveRelease,
                    subtitle: s.tempMoveReleaseDesc,
                    color: Colors.orangeAccent,
                    onTap: () => Navigator.pop(ctx, kModeActionTempRelease),
                  ),
              ],
              if (showRelease) ...[
                const Divider(color: Colors.white12, height: 1),
                _sheetRow(
                  ctx,
                  Icons.link_off,
                  s.actionRelease,
                  subtitle: s.releaseKeepsPosition,
                  color: Colors.redAccent,
                  onTap: () => Navigator.pop(ctx, kModeActionRelease),
                ),
              ],
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
    },
  );
}

/// 一時的モードの設定ダイアログ。移動先フロアと期間を選ぶ。
/// （一時的はフロアの一時移動のみ。所属モードの一時上書きは廃止した。）
Future<TempMoveSpec?> showTempMoveDialog(
  BuildContext context, {
  required SettingsService settingsService,
  required String title,
  String? currentMode,
  int? currentFloor,
}) async {
  final ss = settingsService;
  final floors = <int>[
    for (int i = ss.undergroundFloors; i >= 1; i--) -i,
    for (int i = 1; i <= ss.maxFloors; i++) i,
  ];
  int? targetFloor = floors.firstWhere(
    (f) => f != currentFloor,
    orElse: () => floors.isNotEmpty ? floors.first : 1,
  );
  int durationMinutes = 60;

  return showDialog<TempMoveSpec>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setInner) {
        final s = S.of(ctx);
        final now = DateTime.now();
        final untilEndOfDay = DateTime(
          now.year,
          now.month,
          now.day + 1,
        ).difference(now).inMinutes;

        return AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          title: Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontSize: 14),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.tempMoveFloorLabel,
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final f in floors)
                      _chip(
                        floorLabel(f),
                        targetFloor == f,
                        () => setInner(() => targetFloor = f),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  s.tempMoveDurationLabel,
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _chip(
                      s.tempDuration15m,
                      durationMinutes == 15,
                      () => setInner(() => durationMinutes = 15),
                    ),
                    _chip(
                      s.tempDuration1h,
                      durationMinutes == 60,
                      () => setInner(() => durationMinutes = 60),
                    ),
                    _chip(
                      s.tempDuration3h,
                      durationMinutes == 180,
                      () => setInner(() => durationMinutes = 180),
                    ),
                    _chip(
                      s.tempDurationToday,
                      durationMinutes == untilEndOfDay,
                      () => setInner(() => durationMinutes = untilEndOfDay),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  s.tempMoveHintFloor,
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(
                s.actionCancel,
                style: const TextStyle(color: Colors.white54),
              ),
            ),
            TextButton(
              onPressed: targetFloor == null
                  ? null
                  : () => Navigator.pop(
                      ctx,
                      TempMoveSpec(floor: targetFloor, minutes: durationMinutes),
                    ),
              child: Text(
                s.actionApply,
                style: const TextStyle(color: Colors.orangeAccent),
              ),
            ),
          ],
        );
      },
    ),
  );
}

/// フロア選択ダイアログ。戻り値は選ばれたフロア、キャンセルで null。
Future<int?> showFloorSelectDialog(
  BuildContext context,
  SettingsService ss, {
  required String title,
  int? initial,
}) {
  int? selected = initial;
  final floors = <int>[
    for (int i = ss.undergroundFloors; i >= 1; i--) -i,
    for (int i = 1; i <= ss.maxFloors; i++) i,
  ];
  return showDialog<int>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setInner) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: Text(
          title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white, fontSize: 14),
        ),
        content: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final f in floors)
              GestureDetector(
                onTap: () => setInner(() => selected = f),
                child: Container(
                  width: 44,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: selected == f ? Colors.white : Colors.transparent,
                    border: Border.all(
                      color: selected == f ? Colors.white : Colors.white38,
                    ),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    floorLabel(f),
                    style: TextStyle(
                      color: selected == f ? Colors.black : Colors.white54,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              S.of(ctx).actionCancel,
              style: const TextStyle(color: Colors.white54),
            ),
          ),
          TextButton(
            onPressed: selected == null
                ? null
                : () => Navigator.pop(ctx, selected),
            child: Text(
              S.of(ctx).actionMove,
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    ),
  );
}

/// アプリの複数選択ダイアログ。[initial] のパッケージを選択済みで開き、
/// 確定すると選択されたパッケージ一覧を返す（キャンセルで null）。
Future<List<String>?> showAppMultiSelectDialog(
  BuildContext context, {
  required List<AppConfig> allApps,
  required Set<String> initial,
  required String title,
  SettingsService? settingsService,
  String? confirmLabel,
  bool allowEmpty = false,
}) {
  final sorted = List<AppConfig>.from(allApps)
    ..sort(
      (a, b) => appLabel(a).toLowerCase().compareTo(appLabel(b).toLowerCase()),
    );
  final selected = Set<String>.from(initial);

  return showDialog<List<String>>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setInner) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
            const SizedBox(height: 4),
            Text(
              S.of(ctx).selectionCountSuffix(selected.length),
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: Column(
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  TextButton(
                    onPressed: () => setInner(
                      () => selected.addAll(sorted.map((a) => a.packageName)),
                    ),
                    child: Text(
                      S.of(ctx).actionAllSelect,
                      style: const TextStyle(
                        color: Colors.tealAccent,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => setInner(selected.clear),
                    child: Text(
                      S.of(ctx).actionAllDeselect,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              const Divider(color: Colors.white12),
              Expanded(
                child: ListView.builder(
                  itemCount: sorted.length,
                  itemBuilder: (_, i) {
                    final app = sorted[i];
                    final checked = selected.contains(app.packageName);
                    final mode = settingsService?.appMode(app.packageName);
                    return CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      value: checked,
                      activeColor: Colors.white,
                      checkColor: Colors.black,
                      title: Text(
                        appLabel(app),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                        ),
                      ),
                      subtitle: (mode != null && mode != 'normal')
                          ? Text(
                              modeLabel(ctx, mode),
                              style: const TextStyle(
                                color: Colors.white38,
                                fontSize: 10,
                              ),
                            )
                          : null,
                      onChanged: (_) => setInner(() {
                        if (checked) {
                          selected.remove(app.packageName);
                        } else {
                          selected.add(app.packageName);
                        }
                      }),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              S.of(ctx).actionCancel,
              style: const TextStyle(color: Colors.white54),
            ),
          ),
          TextButton(
            onPressed: (selected.isEmpty && !allowEmpty)
                ? null
                : () => Navigator.pop(ctx, selected.toList()),
            child: Text(
              confirmLabel ?? S.of(ctx).actionDone,
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    ),
  );
}
