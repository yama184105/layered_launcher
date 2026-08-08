import 'dart:convert';

import 'package:flutter/material.dart';
import '../../l10n/s.dart';
import '../../models/app_config.dart';
import '../../services/app_service.dart';
import '../../services/settings_service.dart';
import '../home/home_screen.dart' show floorLabel;
import '../settings/automove_screen.dart';
import '../strict/strict_gate.dart';
import 'mode_actions.dart';

/// モード一覧画面。全アプリは4モードのいずれかに属する:
///   ノーマル / スケジュール / 使用回数 / 使用時間
/// 一覧上は「ノーマル」「カスタム（＝残り3モード）」「一時的」の
/// 3エントリで見せる。一時的は所属モードではなく期限つきの上書きで、
/// 期限が切れると元のフロア／モードへ自動で戻る。
/// 各モードを開くと、その中のスケジュール（同一設定のアプリは
/// まとめて1グループ）一覧が見える。ストリクトモードで移動制限中の
/// アプリは同一設定でも別グループとして表示される。
class ModesScreen extends StatefulWidget {
  final AppService appService;
  final SettingsService settingsService;
  const ModesScreen({
    super.key,
    required this.appService,
    required this.settingsService,
  });

  @override
  State<ModesScreen> createState() => _ModesScreenState();
}

class _ModesScreenState extends State<ModesScreen> {
  List<AppConfig> _apps = [];
  bool _loading = true;

  SettingsService get _ss => widget.settingsService;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final apps = await widget.appService.getAllApps();
    if (!mounted) return;
    setState(() {
      _apps = apps;
      _loading = false;
    });
  }

  int _countInMode(String mode) {
    int n = 0;
    for (final a in _apps) {
      if (mode == kModeTemp) {
        if (tempStateOf(_ss, a) != null) n++;
        continue;
      }
      final current = _ss.appMode(a.packageName);
      if (mode == 'custom') {
        if (current != 'normal') n++;
      } else if (current == mode) {
        n++;
      }
    }
    return n;
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final entries = [
      ('normal', Icons.apps, s.modeNormal, s.modeNormalDesc),
      (
        'custom',
        Icons.tune,
        s.customSection,
        '${s.modeScheduleName} / ${s.modeUsageCount} / ${s.modeUsageTime}',
      ),
      (kModeTemp, Icons.timelapse, s.modeTemp, s.modeTempDesc),
    ];
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(s.modesTitle, style: const TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : ListView(
              children: [
                for (final (mode, icon, name, desc) in entries)
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ModeDetailScreen(
                              mode: mode,
                              appService: widget.appService,
                              settingsService: _ss,
                              initialApps: _apps,
                            ),
                          ),
                        );
                        if (mounted) _load();
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 16,
                        ),
                        child: Row(
                          children: [
                            Icon(icon, color: Colors.white54, size: 22),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    name,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 15,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    desc,
                                    style: const TextStyle(
                                      color: Colors.white38,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              s.groupAppsCount(_countInMode(mode)),
                              style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(width: 6),
                            const Icon(
                              Icons.chevron_right,
                              color: Colors.white24,
                              size: 18,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

// ── Mode detail ─────────────────────────────────────────────────────────────

class ModeDetailScreen extends StatefulWidget {
  final String mode; // 'normal' | 'schedule' | 'usageCount' | 'usageTime'
  final AppService appService;
  final SettingsService settingsService;
  final List<AppConfig>? initialApps;
  const ModeDetailScreen({
    super.key,
    required this.mode,
    required this.appService,
    required this.settingsService,
    this.initialApps,
  });

  @override
  State<ModeDetailScreen> createState() => _ModeDetailScreenState();
}

class _ModeDetailScreenState extends State<ModeDetailScreen> {
  static List<AppConfig> _cachedApps = [];
  List<AppConfig> _apps = [];
  final Set<String> _expandedGroups = {};
  bool _selectionMode = false;
  final Set<String> _selectedPkgs = {};

  SettingsService get _ss => widget.settingsService;

  @override
  void initState() {
    super.initState();
    _apps = List<AppConfig>.from(
      _cachedApps.isNotEmpty ? _cachedApps : widget.initialApps ?? const [],
    );
    _load();
  }

  Future<void> _load() async {
    final apps = await widget.appService.getAllApps();
    if (!mounted) return;
    setState(() {
      _cachedApps = List<AppConfig>.from(apps);
      _apps = apps;
    });
  }

  String _modeName(BuildContext context) {
    final s = S.of(context);
    switch (widget.mode) {
      case 'custom':
        return s.customSection;
      default:
        return modeLabel(context, widget.mode);
    }
  }

  String _displayName(AppConfig app) => appLabel(app);

  List<AppConfig> get _members =>
      _apps.where((a) {
        if (widget.mode == kModeTemp) return tempStateOf(_ss, a) != null;
        final mode = _ss.appMode(a.packageName);
        return widget.mode == 'custom' ? mode != 'normal' : mode == widget.mode;
      }).toList()..sort(
        (a, b) => _displayName(
          a,
        ).toLowerCase().compareTo(_displayName(b).toLowerCase()),
      );

  List<AppConfig> get _selectedApps =>
      _apps.where((a) => _selectedPkgs.contains(a.packageName)).toList();

  void _toggleSelected(String pkg) {
    setState(() {
      if (_selectedPkgs.remove(pkg)) {
        if (_selectedPkgs.isEmpty) _selectionMode = false;
      } else {
        _selectedPkgs.add(pkg);
      }
    });
  }

  void _startSelection(Iterable<String> pkgs) {
    setState(() {
      _selectionMode = true;
      _selectedPkgs.addAll(pkgs);
    });
  }

  void _endSelection() {
    setState(() {
      _selectionMode = false;
      _selectedPkgs.clear();
    });
  }

  // ── Grouping ──────────────────────────────────────────────────────────────

  /// グループのフィンガープリント。スケジュールは「実体ID」で区別するので、
  /// 内容がまったく同じでも別々に作ったスケジュールは別グループになる
  /// （使用回数などが混ざらないように）。
  /// ロック中のアプリは同じスケジュールでも必ず別グループになる。
  String _fingerprint(String pkg) {
    final locked = _ss.isFloorMoveLocked(pkg);
    Object payload;
    final mode = (widget.mode == 'custom' || widget.mode == kModeTemp)
        ? _ss.appMode(pkg)
        : widget.mode;
    switch (mode) {
      case 'schedule':
        payload = scheduleIdOf(_ss, pkg);
        break;
      case 'usageCount':
        payload = _ss.usageCountFloorRules(pkg);
        break;
      case 'usageTime':
        payload = _ss.usageTimeFloorRules(pkg);
        break;
      default:
        payload = '';
    }
    return '${locked ? "locked|" : ""}${_canonicalJson(payload)}';
  }

  String _canonicalJson(Object? value) {
    if (value is Map) {
      final keys = value.keys.map((k) => k.toString()).toList()..sort();
      final buf = StringBuffer('{');
      for (var i = 0; i < keys.length; i++) {
        if (i > 0) buf.write(',');
        buf.write(jsonEncode(keys[i]));
        buf.write(':');
        buf.write(_canonicalJson(value[keys[i]]));
      }
      buf.write('}');
      return buf.toString();
    }
    if (value is List) {
      final buf = StringBuffer('[');
      for (var i = 0; i < value.length; i++) {
        if (i > 0) buf.write(',');
        buf.write(_canonicalJson(value[i]));
      }
      buf.write(']');
      return buf.toString();
    }
    return jsonEncode(value);
  }

  /// グループの内容サマリー（先頭アプリの設定から生成）。
  String _groupSummary(String pkg) {
    final s = S.of(context);
    final mode = (widget.mode == 'custom' || widget.mode == kModeTemp)
        ? _ss.appMode(pkg)
        : widget.mode;
    switch (mode) {
      case 'schedule':
        return _scheduleSummary(pkg) ?? s.notSet;
      case 'usageCount':
        final rules = _ss.usageCountFloorRules(pkg);
        if (rules.isEmpty) return s.notSet;
        return usageRangeLabels(s, rules, isTime: false).join(' / ');
      case 'usageTime':
        final rules = _ss.usageTimeFloorRules(pkg);
        if (rules.isEmpty) return s.notSet;
        return usageRangeLabels(s, rules, isTime: true).join(' / ');
      default:
        return '';
    }
  }

  /// 今のスケジュール状態の説明（現在のフロア / 次の変化時刻）。
  String? _scheduleSummary(String pkg) =>
      _scheduleSummaryRaw(_ss.autoMoveSchedule(pkg));

  String? _scheduleSummaryRaw(Map<String, dynamic> raw) {
    final s = S.of(context);
    if (raw.isEmpty) return null;

    final now = DateTime.now();
    final nowMinute = now.hour * 60 + now.minute;
    final dayData = raw[now.weekday.toString()];
    if (dayData is! Map) return s.notSet;
    final defaultCfg = (dayData['default'] is Map)
        ? Map<String, dynamic>.from(dayData['default'] as Map)
        : null;
    final slots = (dayData['slots'] as List?) ?? [];

    Map<String, dynamic>? active;
    int? activeEnd;
    int? nextStart;
    Map<String, dynamic>? nextSlot;
    for (final sl in slots) {
      if (sl is! Map) continue;
      final m = Map<String, dynamic>.from(sl);
      final start = (m['startMinute'] as num?)?.toInt() ?? 0;
      final end = (m['endMinute'] as num?)?.toInt() ?? 0;
      if (nowMinute >= start && nowMinute < end) {
        active = m;
        activeEnd = end;
      } else if (start > nowMinute &&
          (nextStart == null || start < nextStart)) {
        nextStart = start;
        nextSlot = m;
      }
    }

    String describe(Map<String, dynamic> cfg) {
      final type = cfg['type'] as String? ?? 'fixed';
      if (type == 'keep') return s.keepPosition;
      if (type == 'random') {
        final list =
            (cfg['floors'] as List?)?.map((e) => (e as num).toInt()).toList() ??
            const <int>[];
        return s.scheduleArrowRandom(list.length);
      }
      if (type == 'usageCount' || type == 'usageTime') {
        final rules =
            ((type == 'usageTime' ? cfg['timeRules'] : cfg['countRules'])
                    as List?)
                ?.whereType<Map>()
                .toList() ??
            const <Map>[];
        if (rules.isEmpty) return s.notSet;
        final normalized = [
          for (final r in rules)
            {
              'threshold': (r['threshold'] as num).toInt(),
              'floor': (r['floor'] as num).toInt(),
            },
        ];
        return usageRangeLabels(
          s,
          normalized,
          isTime: type == 'usageTime',
        ).join(' / ');
      }
      final floor = (cfg['floor'] as num?)?.toInt();
      return floor != null ? floorLabel(floor) : '?';
    }

    String fmtMin(int minute) {
      final h = (minute ~/ 60) % 24;
      final m = minute % 60;
      return '${h.toString().padLeft(2, "0")}:${m.toString().padLeft(2, "0")}';
    }

    final activeDesc = active != null
        ? describe(active)
        : (defaultCfg != null ? describe(defaultCfg) : s.keepPosition);
    final parts = <String>[s.scheduleNowLabel(activeDesc)];
    if (defaultCfg != null) {
      parts.add('${s.defaultLabel}: ${describe(defaultCfg)}');
    }
    for (final slot in slots.whereType<Map>()) {
      final m = Map<String, dynamic>.from(slot);
      final start = (m['startMinute'] as num?)?.toInt() ?? 0;
      final end = (m['endMinute'] as num?)?.toInt() ?? 1440;
      parts.add('${fmtMin(start)}-${fmtMin(end)}: ${describe(m)}');
    }
    if (active != null && activeEnd != null) {
      parts.add(s.scheduleUntilLabel(fmtMin(activeEnd)));
    } else if (nextSlot != null && nextStart != null) {
      parts.add(s.scheduleNextLabel(fmtMin(nextStart), describe(nextSlot)));
    }
    return parts.join(' / ');
  }

  // ── Editing ───────────────────────────────────────────────────────────────

  /// 既存スケジュールを直接編集する（グループの「編集」・アプリ行のタップ）。
  /// 既存/新規の選択は出さない — 既にあるスケジュールをそのまま開く。
  Future<void> _openScheduleEditor(List<String> pkgs) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AutoMoveScreen(
          settingsService: _ss,
          packageNames: pkgs,
          allApps: _apps,
        ),
      ),
    );
    if (mounted) _load();
  }

  /// スケジュールを複製する。内容だけを引き継いだ新しいスケジュールを開き
  /// （元のアプリは引き継がず登録アプリはゼロ）、直後にアプリ選択画面を出す。
  Future<void> _duplicateSchedule(List<AppConfig> group) async {
    final schedule = Map<String, dynamic>.from(
      _ss.autoMoveSchedule(group.first.packageName),
    );
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AutoMoveScreen(
          settingsService: _ss,
          packageNames: const [],
          allApps: _apps,
          initialSchedule: schedule,
          promptAppsOnOpen: true,
        ),
      ),
    );
    if (mounted) _load();
  }

  /// カスタム（＝スケジュール）を割り当てる。既存スケジュールがあれば
  /// 「既存に追加 / 新規作成」を選ばせる（ロック中アプリはゲート経由）。
  /// 使用回数・使用時間はスケジュールのスロット種別として内包される。
  Future<void> _editApps(List<String> pkgs, {String? forcedMode}) async {
    if (pkgs.isEmpty) return;
    final entry = await enterScheduleForApps(context, _ss, _apps, pkgs);
    if (entry == ScheduleEntryResult.cancelled) return;
    if (entry == ScheduleEntryResult.createNew && mounted) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => AutoMoveScreen(
            settingsService: _ss,
            packageNames: pkgs,
            allApps: _apps,
          ),
        ),
      );
    }
    if (mounted) _load();
  }

  /// グループのスケジュールを [pkgs] へ適用する（ロック中アプリはゲート経由）。
  /// 同じスケジュール実体に合流させるので、元と同じIDを渡す。
  Future<void> _copyScheduleToApps(String sourcePkg, List<String> pkgs) async {
    await applyScheduleToAppsWithGate(
      context,
      _ss,
      _ss.autoMoveSchedule(sourcePkg),
      pkgs,
      scheduleId: scheduleIdOf(_ss, sourcePkg),
    );
  }

  Future<void> _addAppsToScheduleGroup(List<AppConfig> group) async {
    final sourcePkg = group.first.packageName;
    final existing = group.map((a) => a.packageName).toSet();
    final candidates =
        _apps.where((a) => !existing.contains(a.packageName)).toList()..sort(
          (a, b) => _displayName(
            a,
          ).toLowerCase().compareTo(_displayName(b).toLowerCase()),
        );
    final selected = <String>{};
    final picked = await showDialog<List<String>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInner) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '既存のスケジュールに追加',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.white, fontSize: 14),
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
                        () => selected.addAll(
                          candidates.map((a) => a.packageName),
                        ),
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
                    itemCount: candidates.length,
                    itemBuilder: (_, i) {
                      final app = candidates[i];
                      final checked = selected.contains(app.packageName);
                      return CheckboxListTile(
                        dense: true,
                        value: checked,
                        activeColor: Colors.white,
                        checkColor: Colors.black,
                        title: Text(
                          _displayName(app),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                          ),
                        ),
                        subtitle: Text(
                          _modeNameOf(ctx, _ss.appMode(app.packageName)),
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 10,
                          ),
                        ),
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
              onPressed: selected.isEmpty
                  ? null
                  : () => Navigator.pop(ctx, selected.toList()),
              child: Text(
                S.of(ctx).actionAdd,
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
    if (picked == null || picked.isEmpty) return;
    await _copyScheduleToApps(sourcePkg, picked);
    if (mounted) _load();
  }

  /// 割り振りから外す → 位置保持（今のフロアに留まり、ノーマルへ）。
  Future<void> _releaseApp(String pkg, String name) async {
    final s = S.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: Text(
          name,
          style: const TextStyle(color: Colors.white, fontSize: 14),
        ),
        content: Text(
          s.releaseFromModeConfirm,
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              s.actionCancel,
              style: const TextStyle(color: Colors.white54),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              s.actionRelease,
              style: const TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await releaseAppsWithSchedulePrompt(context, _ss, _apps, [pkg]);
    if (mounted) _load();
  }

  /// このモードにアプリを追加する。一時的モードのときは期限つきの
  /// 上書きを、それ以外は所属モードの設定画面を開く。
  Future<void> _addApps() async {
    final picked = await showAppMultiSelectDialog(
      context,
      allApps: _apps,
      initial: const {},
      title: S.of(context).selectApp,
      settingsService: _ss,
      confirmLabel: S.of(context).actionConfigure,
    );
    if (picked == null || picked.isEmpty || !mounted) return;
    if (widget.mode == kModeTemp) {
      if (await _tempMoveApps(picked) && mounted) _load();
      return;
    }
    await _editApps(picked);
  }

  String _modeNameOf(BuildContext context, String mode) =>
      modeLabel(context, mode);

  /// 1アプリのモード変更。ホーム・設定と同じ共通シート
  /// （ノーマル / スケジュール / 使用回数 / 使用時間 / 一時的 / 解除）。
  Future<void> _showModeSheetFor(AppConfig app) async {
    final temp = tempStateOf(_ss, app);
    final current = _ss.appMode(app.packageName);
    final picked = await showModeSelectSheet(
      context,
      title: _displayName(app),
      currentMode: current,
      statusText: temp != null ? tempStateSummary(context, temp) : null,
      showRelease: current != 'normal',
      showTempRelease: temp != null,
    );
    if (picked == null || !mounted) return;
    switch (picked) {
      case 'normal':
        if (current == 'normal') {
          // すでにノーマル — フロア変更だけ
          await _showFloorPicker(app);
          return;
        }
        // フロア確定まで解除しない。キャンセルすれば元のモードのまま。
        await switchToNormalWithFloor(
          context,
          _ss,
          widget.appService,
          _apps,
          [app.packageName],
          initialFloor: app.floor,
        );
        if (mounted) _load();
        return;
      case kModeTemp:
        if (!await _tempMoveApps([app.packageName])) return;
        break;
      case kModeActionTempRelease:
        await clearTempMove(widget.appService, _ss, [app]);
        break;
      case kModeActionRelease:
        await releaseAppsWithSchedulePrompt(
            context, _ss, _apps, [app.packageName]);
        await clearTempMove(widget.appService, _ss, [app]);
        break;
      default:
        await _editApps([app.packageName], forcedMode: picked);
    }
    if (mounted) _load();
  }

  // ── Normal-mode floor picker (位置の手動変更) ─────────────────────────────

  Future<void> _showFloorPicker(AppConfig app) async {
    int selectedFloor = app.floor;
    final ug = _ss.undergroundFloors;
    final maxF = _ss.maxFloors;
    final floors = [
      for (int i = ug; i >= 1; i--) -i,
      for (int i = 1; i <= maxF; i++) i,
    ];
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInner) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          title: Text(
            S.of(ctx).moveFloorWithName(_displayName(app)),
            style: const TextStyle(color: Colors.white, fontSize: 14),
          ),
          content: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: floors.map((f) {
              final sel = selectedFloor == f;
              return GestureDetector(
                onTap: () => setInner(() => selectedFloor = f),
                child: Container(
                  width: 44,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: sel ? Colors.white : Colors.transparent,
                    border: Border.all(
                      color: sel ? Colors.white : Colors.white38,
                    ),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    floorLabel(f),
                    style: TextStyle(
                      color: sel ? Colors.black : Colors.white54,
                      fontSize: 12,
                    ),
                  ),
                ),
              );
            }).toList(),
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
              onPressed: () async {
                if (_ss.isFloorMoveLocked(app.packageName)) {
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (!mounted) return;
                  // ロック中はタイマー待ちか予約
                  final gate = await requestStrictAction(
                    context,
                    _ss,
                    key: 'floorMove',
                    blockedMessage: S.of(context).floorMoveLockedAll,
                    reservationKind: ReservationKinds.floorMove,
                    reservationData: {
                      'pkg': app.packageName,
                      'floor': selectedFloor,
                    },
                    reservationLabel: S
                        .of(context)
                        .reservationFloorMoveLabel(
                          _displayName(app),
                          floorLabel(selectedFloor),
                        ),
                  );
                  if (gate != StrictGateResult.allowed || !mounted) return;
                  // 一時移動中なら「本来のフロア」だけを書き換える
                  await widget.appService
                      .setPermanentFloor(app, selectedFloor);
                  _load();
                  return;
                }
                await widget.appService.setPermanentFloor(app, selectedFloor);
                if (ctx.mounted) Navigator.pop(ctx);
                _load();
              },
              child: Text(
                S.of(ctx).actionDone,
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 複数選択したアプリへの一括操作 ────────────────────────────────────────

  Future<void> _moveSelectedApps() async {
    if (_selectedPkgs.isEmpty) return;
    final pkgs = _selectedPkgs.toList();
    final floor = await showFloorSelectDialog(
      context,
      _ss,
      title: S.of(context).moveCount(pkgs.length),
    );
    if (floor == null || !mounted) return;

    if (!await applyFloorsWithStrictGate(
      context,
      _ss,
      widget.appService,
      {for (final pkg in pkgs) pkg: floor},
      _apps,
    )) {
      return;
    }
    if (!mounted) return;
    _endSelection();
    await _load();
  }

  /// 選択したアプリのモードをまとめて切り替える。
  Future<void> _switchModeForSelectedApps() async {
    if (_selectedPkgs.isEmpty) return;
    final pkgs = _selectedPkgs.toList();
    final currentModes = pkgs.map(_ss.appMode).toSet();
    final anyTemp = _selectedApps.any((a) => tempStateOf(_ss, a) != null);
    final picked = await showModeSelectSheet(
      context,
      title: S.of(context).modeSwitchCountTitle(pkgs.length),
      currentMode: currentModes.length == 1 ? currentModes.first : null,
      showRelease: currentModes.any((m) => m != 'normal'),
      showTempRelease: anyTemp,
    );
    if (picked == null || !mounted) return;

    switch (picked) {
      case 'normal':
        // フロア確定まで解除しない。キャンセルすれば元のモードのまま。
        await switchToNormalWithFloor(
            context, _ss, widget.appService, _apps, pkgs);
        break;
      case kModeTemp:
        if (!await _tempMoveApps(pkgs)) return;
        break;
      case kModeActionTempRelease:
        await clearTempMove(widget.appService, _ss, _selectedApps);
        break;
      case kModeActionRelease:
        await releaseAppsWithSchedulePrompt(context, _ss, _apps, pkgs);
        await clearTempMove(widget.appService, _ss, _selectedApps);
        break;
      default:
        // schedule / usageCount / usageTime は設定が要るので編集画面へ
        await _editApps(pkgs, forcedMode: picked);
        if (!mounted) return;
        _endSelection();
        return;
    }
    if (!mounted) return;
    _endSelection();
    await _load();
  }

  Future<void> _tempMoveSelectedApps() async {
    if (_selectedPkgs.isEmpty) return;
    if (!await _tempMoveApps(_selectedPkgs.toList()) || !mounted) return;
    _endSelection();
    await _load();
  }

  Future<void> _releaseSelectedApps() async {
    if (_selectedPkgs.isEmpty) return;
    if (!await _confirmRelease(_selectedPkgs.toList()) || !mounted) return;
    _endSelection();
    await _load();
  }

  /// 一時的モードのダイアログを出して適用する。戻り値 true = 適用した。
  Future<bool> _tempMoveApps(List<String> pkgs) async {
    final apps = _apps.where((a) => pkgs.contains(a.packageName)).toList();
    if (apps.isEmpty) return false;
    final single = apps.length == 1 ? apps.first : null;
    final spec = await showTempMoveDialog(
      context,
      settingsService: _ss,
      title: single != null
          ? '${S.of(context).tempMoveTitle} — ${_displayName(single)}'
          : S.of(context).tempMoveCountTitle(apps.length),
      currentMode: single != null ? _ss.appMode(single.packageName) : null,
      currentFloor: single?.floor,
    );
    if (spec == null) return false;
    await applyTempMoveWithStrictGate(context, _ss, widget.appService, apps, spec);
    return true;
  }

  Future<bool> _confirmRelease(List<String> pkgs) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: Text(
          S.of(ctx).actionRelease,
          style: const TextStyle(color: Colors.white, fontSize: 14),
        ),
        content: Text(
          S.of(ctx).releaseCountConfirm(pkgs.length),
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
              S.of(ctx).actionRelease,
              style: const TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return false;
    await releaseAppsWithSchedulePrompt(context, _ss, _apps, pkgs);
    await clearTempMove(
      widget.appService,
      _ss,
      _apps.where((a) => pkgs.contains(a.packageName)).toList(),
    );
    return true;
  }

  Future<void> _doRandomizeNormal() async {
    final s = S.of(context);
    final candidates = _members.where((a) => !a.isPinned).toList()
      ..sort(
        (a, b) => _displayName(
          a,
        ).toLowerCase().compareTo(_displayName(b).toLowerCase()),
      );
    if (candidates.isEmpty) return;

    final selected = <String>{for (final app in candidates) app.packageName};
    final targetFloors = <int>{
      for (int i = _ss.undergroundFloors; i >= 1; i--) -i,
      for (int i = 1; i <= _ss.maxFloors; i++) i,
    };
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInner) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          title: Text(
            s.randomPlacementSelectApps,
            style: const TextStyle(color: Colors.white, fontSize: 15),
          ),
          content: SizedBox(
            width: double.maxFinite,
            height: 420,
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    S.of(ctx).floorLabel,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (int i = _ss.undergroundFloors; i >= 1; i--)
                      FilterChip(
                        selected: targetFloors.contains(-i),
                        label: Text(floorLabel(-i)),
                        selectedColor: Colors.tealAccent,
                        backgroundColor: Colors.transparent,
                        checkmarkColor: Colors.black,
                        labelStyle: TextStyle(
                          color: targetFloors.contains(-i)
                              ? Colors.black
                              : Colors.white70,
                          fontSize: 12,
                        ),
                        side: const BorderSide(color: Colors.white38),
                        onSelected: (v) => setInner(() {
                          if (v) {
                            targetFloors.add(-i);
                          } else {
                            targetFloors.remove(-i);
                          }
                        }),
                      ),
                    for (int i = 1; i <= _ss.maxFloors; i++)
                      FilterChip(
                        selected: targetFloors.contains(i),
                        label: Text(floorLabel(i)),
                        selectedColor: Colors.tealAccent,
                        backgroundColor: Colors.transparent,
                        checkmarkColor: Colors.black,
                        labelStyle: TextStyle(
                          color: targetFloors.contains(i)
                              ? Colors.black
                              : Colors.white70,
                          fontSize: 12,
                        ),
                        side: const BorderSide(color: Colors.white38),
                        onSelected: (v) => setInner(() {
                          if (v) {
                            targetFloors.add(i);
                          } else {
                            targetFloors.remove(i);
                          }
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                const Divider(color: Colors.white12),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    TextButton(
                      onPressed: () => setInner(
                        () => selected.addAll(
                          candidates.map((a) => a.packageName),
                        ),
                      ),
                      child: Text(
                        s.actionAllSelect,
                        style: const TextStyle(
                          color: Colors.tealAccent,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => setInner(selected.clear),
                      child: Text(
                        s.actionAllDeselect,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    Text(
                      s.selectedItemsCount(selected.length, candidates.length),
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                const Divider(color: Colors.white12),
                Expanded(
                  child: ListView.builder(
                    itemCount: candidates.length,
                    itemBuilder: (_, i) {
                      final app = candidates[i];
                      final checked = selected.contains(app.packageName);
                      return CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: checked,
                        activeColor: Colors.tealAccent,
                        checkColor: Colors.black,
                        title: Text(
                          _displayName(app),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                          ),
                        ),
                        subtitle: Text(
                          floorLabel(app.floor),
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 11,
                          ),
                        ),
                        onChanged: (v) => setInner(() {
                          if (v == true) {
                            selected.add(app.packageName);
                          } else {
                            selected.remove(app.packageName);
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
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(
                s.actionCancel,
                style: const TextStyle(color: Colors.white54),
              ),
            ),
            TextButton(
              onPressed: selected.isEmpty || targetFloors.isEmpty
                  ? null
                  : () => Navigator.pop(ctx, true),
              child: Text(
                s.actionExecute,
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || selected.isEmpty || targetFloors.isEmpty) return;

    final fullMap = await widget.appService.buildRandomFloorMap(
      floors: targetFloors.toList(),
    );
    final floorMap = Map.fromEntries(
      fullMap.entries.where((e) => selected.contains(e.key)),
    );

    if (!await applyFloorsWithStrictGate(
      context,
      _ss,
      widget.appService,
      floorMap,
      _apps,
    )) {
      return;
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.randomDoneCount(floorMap.length))),
      );
      _load();
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final showAddFab = widget.mode != 'normal';
    return PopScope(
      // 選択中の戻るはまず選択解除
      canPop: !_selectionMode,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _selectionMode) _endSelection();
      },
      child: _buildScaffold(s, showAddFab),
    );
  }

  Widget _buildScaffold(S s, bool showAddFab) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(
          _selectionMode
              ? s.selectedCount(_selectedPkgs.length)
              : _modeName(context),
          style: const TextStyle(color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: _selectionMode
            ? [
                TextButton(
                  onPressed: () => setState(() {
                    _selectedPkgs.addAll(_members.map((a) => a.packageName));
                  }),
                  child: Text(
                    s.actionSelectAll,
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ),
                TextButton(
                  onPressed: _endSelection,
                  child: Text(
                    s.actionDeselectAll,
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ),
              ]
            : null,
      ),
      body: switch (widget.mode) {
        'normal' => _buildNormalList(),
        kModeTemp => _buildTempList(),
        _ => _buildGroupedList(),
      },
      bottomNavigationBar: _selectionMode && _selectedPkgs.isNotEmpty
          ? _buildSelectionBar()
          : null,
      floatingActionButton: (showAddFab && !_selectionMode)
          ? FloatingActionButton.extended(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
              onPressed: _addApps,
              icon: const Icon(Icons.add, size: 18),
              label: Text(
                s.addAppsToMode,
                style: const TextStyle(fontSize: 13),
              ),
            )
          : null,
    );
  }

  /// 複数選択中の一括操作バー。どのモードの一覧でも同じ操作を出す
  /// （フロア移動 / モード切替 / 一時的 / 割り振り解除）。
  Widget _buildSelectionBar() {
    final s = S.of(context);
    final anyAssigned = _selectedPkgs.any((p) => _ss.appMode(p) != 'normal');
    final anyTemp = _selectedApps.any((a) => tempStateOf(_ss, a) != null);
    return Container(
      color: const Color(0xFF141414),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: SafeArea(
        top: false,
        child: Wrap(
          alignment: WrapAlignment.spaceEvenly,
          spacing: 4,
          children: [
            // カスタム（スケジュール）ではフロアは自動制御なので直接変更は出さない
            if (widget.mode != 'custom')
              _barButton(Icons.stairs, s.floorChange, _moveSelectedApps),
            _barButton(Icons.layers, s.selectionMode, _switchModeForSelectedApps),
            _barButton(
              Icons.timelapse,
              anyTemp ? s.tempMoveExtend : s.selectionTemp,
              _tempMoveSelectedApps,
              color: Colors.orangeAccent,
            ),
            if (anyAssigned || anyTemp)
              _barButton(
                Icons.link_off,
                s.actionRelease,
                _releaseSelectedApps,
                color: Colors.redAccent,
              ),
          ],
        ),
      ),
    );
  }

  Widget _barButton(
    IconData icon,
    String label,
    VoidCallback onTap, {
    Color color = Colors.white70,
  }) {
    return TextButton.icon(
      style: TextButton.styleFrom(
        foregroundColor: color,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      ),
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label, style: const TextStyle(fontSize: 11)),
    );
  }

  /// 一時的モード: 期限つきの上書きが効いているアプリの一覧。
  Widget _buildTempList() {
    final s = S.of(context);
    final members = _members;
    if (members.isEmpty) {
      return Center(
        child: Text(
          s.modeTempNoApps,
          style: const TextStyle(color: Colors.white38, fontSize: 13),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        for (final app in members)
          Builder(
            builder: (_) {
              final temp = tempStateOf(_ss, app)!;
              final selected = _selectedPkgs.contains(app.packageName);
              return ListTile(
                dense: true,
                selected: selected,
                selectedTileColor: Colors.white.withValues(alpha: 0.05),
                leading: _selectionMode
                    ? Checkbox(
                        value: selected,
                        activeColor: Colors.white,
                        checkColor: Colors.black,
                        onChanged: (_) => _toggleSelected(app.packageName),
                      )
                    : null,
                title: Text(
                  _displayName(app),
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
                subtitle: Text(
                  tempStateSummary(context, temp),
                  style: const TextStyle(
                    color: Colors.orangeAccent,
                    fontSize: 10,
                  ),
                ),
                trailing: _selectionMode
                    ? null
                    : IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(
                          Icons.undo,
                          color: Colors.orangeAccent,
                          size: 18,
                        ),
                        onPressed: () async {
                          await clearTempMove(widget.appService, _ss, [app]);
                          if (mounted) _load();
                        },
                      ),
                onTap: () async {
                  if (_selectionMode) {
                    _toggleSelected(app.packageName);
                    return;
                  }
                  if (await _tempMoveApps([app.packageName]) && mounted) {
                    _load();
                  }
                },
                onLongPress: () => _startSelection([app.packageName]),
              );
            },
          ),
      ],
    );
  }

  /// ノーマルモード: 今と変わらないアプリ一覧（フロア表示・タップで移動）。
  Widget _buildNormalList() {
    final s = S.of(context);
    final members = _members;
    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Colors.white24),
              padding: const EdgeInsets.symmetric(vertical: 10),
            ),
            onPressed: members.any((a) => !a.isPinned)
                ? _doRandomizeNormal
                : null,
            icon: const Icon(Icons.shuffle, size: 17),
            label: Text(
              s.randomPlacement,
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ),
        if (members.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 80),
            child: Center(
              child: Text(
                s.modeNoApps,
                style: const TextStyle(color: Colors.white38, fontSize: 13),
              ),
            ),
          )
        else
          for (final app in members)
            Builder(
              builder: (_) {
                final temp = tempStateOf(_ss, app);
                final selected = _selectedPkgs.contains(app.packageName);
                return ListTile(
                  dense: true,
                  selected: selected,
                  selectedTileColor: Colors.white.withValues(alpha: 0.05),
                  leading: _selectionMode
                      ? Checkbox(
                          value: selected,
                          activeColor: Colors.white,
                          checkColor: Colors.black,
                          onChanged: (_) => _toggleSelected(app.packageName),
                        )
                      : null,
                  title: Text(
                    _displayName(app),
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                  ),
                  subtitle: temp != null
                      ? Text(
                          tempStateSummary(context, temp),
                          style: const TextStyle(
                            color: Colors.orangeAccent,
                            fontSize: 10,
                          ),
                        )
                      : null,
                  trailing: Text(
                    floorLabel(app.floor),
                    style: const TextStyle(color: Colors.white54, fontSize: 13),
                  ),
                  onTap: () {
                    if (_selectionMode) {
                      _toggleSelected(app.packageName);
                    } else {
                      _showModeSheetFor(app);
                    }
                  },
                  onLongPress: () => _startSelection([app.packageName]),
                );
              },
            ),
      ],
    );
  }

  /// スケジュール/使用回数/使用時間: 同一設定ごとのグループ一覧。
  Widget _buildGroupedList() {
    final s = S.of(context);
    final members = _members;

    // 保存されたスケジュール（アプリ0個。ライブに同じ実体が無いものだけ）
    final liveIds = members
        .where((a) => _ss.appMode(a.packageName) == 'schedule')
        .map((a) => scheduleIdOf(_ss, a.packageName))
        .toSet();
    final templates = widget.mode == 'custom'
        ? _ss.savedSchedules.where((t) => !liveIds.contains(t.id)).toList()
        : const <SavedSchedule>[];

    if (members.isEmpty && templates.isEmpty) {
      return Center(
        child: Text(
          s.modeNoApps,
          style: const TextStyle(color: Colors.white38, fontSize: 13),
        ),
      );
    }

    final groups = <String, List<AppConfig>>{};
    for (final app in members) {
      groups.putIfAbsent(_fingerprint(app.packageName), () => []).add(app);
    }
    final sortedEntries = groups.entries.toList()
      ..sort((a, b) => b.value.length.compareTo(a.value.length));

    return ListView(
      padding: const EdgeInsets.only(bottom: 88),
      children: [
        for (final entry in sortedEntries) ..._groupWidgets(s, entry),
        for (final tmpl in templates) ..._templateWidgets(s, tmpl),
      ],
    );
  }

  /// 保存されたスケジュール（アプリ0個）の行。追加・複製・削除ができる。
  List<Widget> _templateWidgets(S s, SavedSchedule tmpl) {
    final summary = _scheduleSummaryRaw(tmpl.schedule) ?? s.notSet;
    return [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            const Icon(Icons.bookmark_border, color: Colors.white38, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.scheduleTemplateLabel,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
                  if (summary.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        summary,
                        style: const TextStyle(
                          color: Colors.tealAccent,
                          fontSize: 11,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            _pillButton(s.actionAdd, Colors.tealAccent,
                () => _addAppsToTemplate(tmpl)),
            const SizedBox(width: 6),
            _pillButton(s.actionDuplicate, Colors.white70,
                () => _duplicateScheduleRaw(tmpl)),
            const SizedBox(width: 6),
            _pillButton(s.actionDelete, Colors.redAccent, () async {
              await _ss.removeSavedScheduleById(tmpl.id);
              if (mounted) _load();
            }),
          ],
        ),
      ),
      const Divider(color: Colors.white12, height: 1),
    ];
  }

  /// [repPkg] のスケジュールと同じ内容なのに別実体になっているスケジュールの
  /// ID一覧（自分自身は除く）。保存テンプレートも対象に含む。
  Set<String> _sameContentOtherScheduleIds(String repPkg) {
    final myId = scheduleIdOf(_ss, repPkg);
    final canon = _ss.scheduleCanonical(_ss.autoMoveSchedule(repPkg));
    final ids = <String>{};
    for (final a in _apps) {
      if (_ss.appMode(a.packageName) != 'schedule') continue;
      final id = scheduleIdOf(_ss, a.packageName);
      if (id == myId) continue;
      if (_ss.scheduleCanonical(_ss.autoMoveSchedule(a.packageName)) == canon) {
        ids.add(id);
      }
    }
    for (final t in _ss.savedSchedules) {
      if (t.id == myId) continue;
      if (_ss.scheduleCanonical(t.schedule) == canon) ids.add(t.id);
    }
    return ids;
  }

  /// 同じ条件の別スケジュールのうち、**選んだものだけ**をこのスケジュール実体に
  /// まとめる。内容は同じなのでフロアの挙動は変わらない（ゲート不要）。
  Future<void> _mergeSameSchedules(String repPkg) async {
    final myId = scheduleIdOf(_ss, repPkg);
    final otherIds = _sameContentOtherScheduleIds(repPkg);
    if (otherIds.isEmpty) return;

    // 候補をスケジュール実体ごとにまとめる（内容は同じなのでアプリで見分ける）
    final candidates = <(String, List<AppConfig>)>[];
    for (final id in otherIds) {
      final apps = _apps
          .where((a) =>
              _ss.appMode(a.packageName) == 'schedule' &&
              scheduleIdOf(_ss, a.packageName) == id)
          .toList();
      candidates.add((id, apps));
    }
    candidates.sort((a, b) => b.$2.length.compareTo(a.$2.length));

    final selected = <String>{};
    final picked = await showDialog<List<String>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInner) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                S.of(ctx).mergeSchedulesTitle,
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
              const SizedBox(height: 4),
              Text(
                S.of(ctx).mergeSchedulesPickHint,
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            height: 320,
            child: ListView.builder(
              itemCount: candidates.length,
              itemBuilder: (_, i) {
                final (id, apps) = candidates[i];
                final checked = selected.contains(id);
                return CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: checked,
                  activeColor: Colors.amberAccent,
                  checkColor: Colors.black,
                  title: Text(
                    apps.isEmpty
                        ? S.of(ctx).scheduleTemplateLabel
                        : S.of(ctx).groupAppsCount(apps.length),
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
                  subtitle: apps.isEmpty
                      ? null
                      : Text(
                          apps.map(_displayName).join(', '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 11,
                          ),
                        ),
                  onChanged: (_) => setInner(() {
                    if (checked) {
                      selected.remove(id);
                    } else {
                      selected.add(id);
                    }
                  }),
                );
              },
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
              onPressed: selected.isEmpty
                  ? null
                  : () => Navigator.pop(ctx, selected.toList()),
              child: Text(
                S.of(ctx).actionMerge,
                style: TextStyle(
                  color: selected.isEmpty
                      ? Colors.white24
                      : Colors.amberAccent,
                ),
              ),
            ),
          ],
        ),
      ),
    );
    if (picked == null || picked.isEmpty) return;

    // 選ばれた実体に属するアプリだけを合流させる
    for (final a in _apps) {
      if (_ss.appMode(a.packageName) != 'schedule') continue;
      if (!picked.contains(scheduleIdOf(_ss, a.packageName))) continue;
      await _ss.setAutoMoveScheduleId(a.packageName, myId);
    }
    // 選ばれた保存テンプレートは吸収されるので消す
    for (final id in picked) {
      await _ss.removeSavedScheduleById(id);
    }
    if (mounted) _load();
  }

  Widget _pillButton(String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          border: Border.all(color: color.withValues(alpha: 0.4)),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(label, style: TextStyle(color: color, fontSize: 11)),
      ),
    );
  }

  /// テンプレートにアプリを割り当てる（割り当てるとライブ化しテンプレートは消える）。
  Future<void> _addAppsToTemplate(SavedSchedule tmpl) async {
    final picked = await showAppMultiSelectDialog(
      context,
      allApps: _apps,
      initial: const {},
      title: S.of(context).selectApp,
      settingsService: _ss,
      confirmLabel: S.of(context).actionAdd,
    );
    if (picked == null || picked.isEmpty || !mounted) return;
    // 保存されていた実体をそのまま引き継ぐ
    await applyScheduleToAppsWithGate(
      context,
      _ss,
      tmpl.schedule,
      picked,
      scheduleId: tmpl.id,
    );
    if (mounted) _load();
  }

  /// テンプレートを複製（内容を引き継ぎ新しい編集画面＋アプリ選択）。
  /// 複製なので実体IDは引き継がない（別スケジュールになる）。
  Future<void> _duplicateScheduleRaw(SavedSchedule tmpl) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AutoMoveScreen(
          settingsService: _ss,
          packageNames: const [],
          allApps: _apps,
          initialSchedule: Map<String, dynamic>.from(tmpl.schedule),
          promptAppsOnOpen: true,
        ),
      ),
    );
    if (mounted) _load();
  }

  List<Widget> _groupWidgets(S s, MapEntry<String, List<AppConfig>> entry) {
    final fp = entry.key;
    final group = entry.value;
    final repPkg = group.first.packageName;
    final locked = _ss.isFloorMoveLocked(repPkg);
    final isExpanded = _expandedGroups.contains(fp);
    final summary = _groupSummary(repPkg);
    final isScheduleGroup = _ss.appMode(repPkg) == 'schedule';
    final groupPkgs = group.map((a) => a.packageName).toList();
    final groupSelected =
        _selectionMode && groupPkgs.every(_selectedPkgs.contains);
    // 同じ内容だが別実体になっているスケジュール（合体ボタンの対象）
    final mergeableIds = isScheduleGroup
        ? _sameContentOtherScheduleIds(repPkg)
        : const <String>{};

    return [
      Material(
        color: groupSelected
            ? Colors.white.withValues(alpha: 0.05)
            : Colors.transparent,
        child: InkWell(
          onTap: () {
            if (_selectionMode) {
              // 選択中はグループ単位でまとめて選択/解除
              setState(() {
                if (groupSelected) {
                  _selectedPkgs.removeAll(groupPkgs);
                  if (_selectedPkgs.isEmpty) _selectionMode = false;
                } else {
                  _selectedPkgs.addAll(groupPkgs);
                }
              });
              return;
            }
            setState(() {
              if (isExpanded) {
                _expandedGroups.remove(fp);
              } else {
                _expandedGroups.add(fp);
              }
            });
          },
          // グループごと複数選択に入る（カスタムのモード切り替え用）
          onLongPress: () => _startSelection(groupPkgs),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (_selectionMode)
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: Icon(
                          groupSelected
                              ? Icons.check_box
                              : Icons.check_box_outline_blank,
                          color: groupSelected ? Colors.white : Colors.white38,
                          size: 18,
                        ),
                      ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              if (locked)
                                const Padding(
                                  padding: EdgeInsets.only(right: 6),
                                  child: Icon(
                                    Icons.lock,
                                    color: Colors.orangeAccent,
                                    size: 14,
                                  ),
                                ),
                              Text(
                                s.groupAppsCount(group.length),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                          if (summary.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                summary,
                                style: const TextStyle(
                                  color: Colors.tealAccent,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    Icon(
                      isExpanded ? Icons.expand_less : Icons.expand_more,
                      color: Colors.white38,
                      size: 18,
                    ),
                  ],
                ),
                // ボタンは Wrap で折り返す（合体が出ると4つになるため）
                if (!_selectionMode) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _pillButton(s.actionEdit, Colors.tealAccent,
                          () => _openScheduleEditor(groupPkgs)),
                      if (isScheduleGroup)
                        _pillButton(s.actionAdd, Colors.white70,
                            () => _addAppsToScheduleGroup(group)),
                      if (isScheduleGroup)
                        _pillButton(s.actionDuplicate, Colors.white70,
                            () => _duplicateSchedule(group)),
                      // 同じ条件で別実体になっているスケジュールがあるときだけ
                      if (isScheduleGroup && mergeableIds.isNotEmpty)
                        _pillButton(s.actionMerge, Colors.amberAccent,
                            () => _mergeSameSchedules(repPkg)),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      if (isExpanded)
        for (final app in group)
          Builder(
            builder: (_) {
              final selected = _selectedPkgs.contains(app.packageName);
              return Material(
                color: selected
                    ? Colors.white.withValues(alpha: 0.06)
                    : Colors.white.withValues(alpha: 0.02),
                child: InkWell(
                  onTap: () => _selectionMode
                      ? _toggleSelected(app.packageName)
                      : _openScheduleEditor([app.packageName]),
                  onLongPress: () => _startSelection([app.packageName]),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(40, 8, 8, 8),
                    child: Row(
                      children: [
                        if (_selectionMode)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Icon(
                              selected
                                  ? Icons.check_box
                                  : Icons.check_box_outline_blank,
                              color: selected ? Colors.white : Colors.white38,
                              size: 16,
                            ),
                          ),
                        Expanded(
                          child: Text(
                            _displayName(app),
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        Text(
                          floorLabel(app.floor),
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 11,
                          ),
                        ),
                        if (!_selectionMode)
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(
                              Icons.close,
                              color: Colors.redAccent,
                              size: 16,
                            ),
                            onPressed: () =>
                                _releaseApp(app.packageName, _displayName(app)),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
      const Divider(color: Colors.white12, height: 1),
    ];
  }
}
