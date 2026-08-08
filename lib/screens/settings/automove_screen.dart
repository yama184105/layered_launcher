import 'package:flutter/material.dart';
import '../../l10n/s.dart';
import '../../models/app_config.dart';
import '../../services/settings_service.dart';
import '../home/home_screen.dart' show floorLabel;
import '../modes/mode_actions.dart'
    show showAppMultiSelectDialog, usageRangeLabels;
import '../strict/strict_gate.dart' show applyScheduleToAppsWithGate;

/// スケジュールモードの編集画面。
/// 1日を時間帯（スロット）に区切り、各スロットで行き先フロアを決める。
/// スロット外は「デフォルト」設定に従う（既定は位置保持）。
class AutoMoveScreen extends StatefulWidget {
  final SettingsService settingsService;
  final List<String> packageNames;
  final List<AppConfig> allApps;

  /// 指定するとこのスケジュール内容を初期値として読み込む（複製用）。
  /// このとき packageNames は空でよく、保存前に対象アプリを選ぶ。
  final Map<String, dynamic>? initialSchedule;

  /// 開いた直後に対象アプリの選択画面を出す（複製直後の「アプリを追加」）。
  final bool promptAppsOnOpen;

  const AutoMoveScreen({
    super.key,
    required this.settingsService,
    required this.packageNames,
    required this.allApps,
    this.initialSchedule,
    this.promptAppsOnOpen = false,
  });

  @override
  State<AutoMoveScreen> createState() => _AutoMoveScreenState();
}

class _AutoMoveScreenState extends State<AutoMoveScreen> {
  late SettingsService _ss;

  // default + slot list per weekday (1..7)
  final Map<int, _SlotConfig> _defaults = {};
  final Map<int, List<_SlotConfig>> _schedules = {};
  int _editingWeekday = 1;

  /// true = 毎日同じ設定。false = 曜日ごとに別々の設定を持つ。
  bool _dailyMode = true;

  bool _isBulk = false;
  bool _hasExisting = false;

  /// この設定を適用するアプリ。開いたあとでも複数選択で増減できる。
  late List<String> _targetPkgs;

  /// 編集中のスケジュール実体ID。null なら保存時に新しい実体になる
  /// （＝複製や新規作成。内容が同じでも別スケジュールとして扱う）。
  String? _scheduleId;

  List<String> _weekdayLabels(BuildContext context) {
    final s = S.of(context);
    return [
      s.weekdayMon,
      s.weekdayTue,
      s.weekdayWed,
      s.weekdayThu,
      s.weekdayFri,
      s.weekdaySat,
      s.weekdaySun,
    ];
  }

  @override
  void initState() {
    super.initState();
    _ss = widget.settingsService;
    _targetPkgs = List<String>.from(widget.packageNames);
    _isBulk = _targetPkgs.length > 1;

    final Map<String, dynamic> raw;
    if (widget.initialSchedule != null) {
      // 複製: 内容だけ引き継ぎ、対象アプリはゼロから選び直す。
      // ID は引き継がない → 同じ内容でも別スケジュールになる。
      _hasExisting = false;
      _scheduleId = null;
      raw = widget.initialSchedule!;
    } else if (_targetPkgs.isNotEmpty) {
      final pkg = _targetPkgs.first;
      _hasExisting = _ss.appMode(pkg) == 'schedule' ||
          _ss.autoMoveMode(pkg) == 'schedule';
      _scheduleId = _ss.autoMoveScheduleId(pkg); // 既存を編集 → 同じ実体のまま
      raw = _ss.autoMoveSchedule(pkg);
    } else {
      _hasExisting = false;
      raw = const <String, dynamic>{};
    }
    _loadScheduleFromRaw(raw);
    _dailyMode = _allWeekdaysIdentical();

    if (widget.promptAppsOnOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _pickTargetApps();
      });
    }
  }

  void _loadScheduleFromRaw(Map<String, dynamic> raw) {
    _defaults.clear();
    _schedules.clear();
    for (int wd = 1; wd <= 7; wd++) {
      // 既定は位置保持（設定が無い曜日はフロアを動かさない）
      _schedules[wd] = [];
      final key = wd.toString();
      if (!raw.containsKey(key)) continue;
      final dayData = Map<String, dynamic>.from(raw[key] as Map);
      if (dayData['default'] is Map) {
        _defaults[wd] = _SlotConfig.fromMap(
          Map<String, dynamic>.from(dayData['default'] as Map),
        );
      }
      final slots = (dayData['slots'] as List?) ?? [];
      for (final s in slots) {
        if (s is! Map) continue;
        final m = Map<String, dynamic>.from(s);
        final cfg = _SlotConfig.fromMap(m);
        // 旧形式の互換: 0〜1440 の1件だけでデフォルト未設定ならそれを既定とみなす
        if (slots.length == 1 &&
            cfg.startMinute == 0 &&
            cfg.endMinute == 1440 &&
            dayData['default'] == null) {
          _defaults[wd] = cfg;
          continue;
        }
        if (cfg.endMinute > cfg.startMinute) {
          _schedules[wd]!.add(cfg);
        }
      }
      _schedules[wd]!.sort((a, b) => a.startMinute.compareTo(b.startMinute));
    }
  }

  bool _allWeekdaysIdentical() {
    String dayKey(int wd) {
      final d = _defaults[wd] ?? _SlotConfig(type: 'keep');
      final slots = _schedules[wd] ?? const <_SlotConfig>[];
      return '${d.toMap()}|${slots.map((s) => s.toMap()).toList()}';
    }

    final first = dayKey(1);
    for (int wd = 2; wd <= 7; wd++) {
      if (dayKey(wd) != first) return false;
    }
    return true;
  }

  int get _maxFloor => _ss.maxFloors;
  int get _minFloor => -(_ss.undergroundFloors);

  List<int> get _allFloorOptions {
    final floors = <int>[];
    for (int f = _minFloor; f <= _maxFloor; f++) {
      if (f == 0) continue;
      floors.add(f);
    }
    return floors;
  }

  String _appName(String pkg) {
    final app = widget.allApps.firstWhere(
      (a) => a.packageName == pkg,
      orElse: () => AppConfig(packageName: pkg, appName: pkg, floor: 1),
    );
    return (app.customName?.isNotEmpty == true) ? app.customName! : app.appName;
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
        backgroundColor: const Color(0xFF333333),
      ),
    );
  }

  bool _hasOverlap(int weekday, _SlotConfig newSlot, {int? editingIndex}) {
    final slots = _schedules[weekday] ?? const [];
    for (int i = 0; i < slots.length; i++) {
      if (i == editingIndex) continue;
      final s = slots[i];
      if (newSlot.startMinute < s.endMinute &&
          newSlot.endMinute > s.startMinute) {
        return true;
      }
    }
    return false;
  }

  Future<void> _save() async {
    final s = S.of(context);
    final wdLabels = _weekdayLabels(context);

    // 複製直後などで対象アプリが未選択なら保存できない
    if (_targetPkgs.isEmpty) {
      _showSnack(s.selectTargetAppsFirst);
      return;
    }

    // 毎日モードなら編集中の曜日の内容を全曜日へコピーする
    if (_dailyMode) {
      final srcDefault =
          _defaults[_editingWeekday] ?? _SlotConfig(type: 'keep');
      final srcSlots = _schedules[_editingWeekday] ?? const <_SlotConfig>[];
      for (int wd = 1; wd <= 7; wd++) {
        _defaults[wd] = srcDefault.copy();
        _schedules[wd] = srcSlots.map((c) => c.copy()).toList();
      }
    }

    // 全曜日ぶんのスロットの重なりと時刻の前後をチェック
    for (int wd = 1; wd <= 7; wd++) {
      final slots = _schedules[wd] ?? const [];
      for (int i = 0; i < slots.length; i++) {
        final a = slots[i];
        if (a.startMinute >= a.endMinute) {
          _showSnack(s.weekdayScheduleInvalid(wdLabels[wd - 1]));
          return;
        }
        for (int j = i + 1; j < slots.length; j++) {
          final b = slots[j];
          if (a.startMinute < b.endMinute && a.endMinute > b.startMinute) {
            _showSnack(s.weekdayScheduleOverlap(wdLabels[wd - 1]));
            return;
          }
        }
      }
    }

    final map = <String, dynamic>{};
    for (int wd = 1; wd <= 7; wd++) {
      final defaultCfg = _defaults[wd] ?? _SlotConfig(type: 'keep');
      final slots = _schedules[wd] ?? const <_SlotConfig>[];
      map[wd.toString()] = {
        'default': defaultCfg.toMap(),
        'slots': slots.map((s) => s.toMap()).toList(),
      };
    }
    // 移動ロック中のアプリはゲート（待つか予約）を挟む。ロックしていない
    // アプリは即時に割り当てる。（applyScheduleToApps が appMode='schedule'
    // 設定と使用回数/使用時間ルールの破棄まで行う）
    final ok = await applyScheduleToAppsWithGate(
      context,
      _ss,
      map,
      _targetPkgs,
      scheduleId: _scheduleId,
    );
    if (ok && mounted) Navigator.pop(context, true);
  }

  /// 対象アプリを選び直す（このスケジュールを他のアプリにも適用する）。
  Future<void> _pickTargetApps() async {
    final picked = await showAppMultiSelectDialog(
      context,
      allApps: widget.allApps,
      initial: _targetPkgs.toSet(),
      title: S.of(context).targetAppsSelect,
      settingsService: _ss,
      confirmLabel: S.of(context).actionDone,
    );
    if (picked == null || picked.isEmpty || !mounted) return;
    setState(() {
      _targetPkgs = picked;
      _isBulk = picked.length > 1;
    });
  }

  Future<void> _release() async {
    for (final pkg in _targetPkgs) {
      await _ss.releaseFromMode(pkg); // 闖ｴ蜥ｲ・ｽ・ｮ闖ｫ譎・亜邵ｺ・ｧ normal 邵ｺ・ｸ
    }
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final title = _isBulk
        ? s.automoveTitleMulti(_targetPkgs.length)
        : s.automoveTitleSingle(_appName(_targetPkgs.first));
    final bottomPad = MediaQuery.of(context).viewPadding.bottom;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: const Color(0xFF111111),
        title: Text(
          title,
          style: const TextStyle(color: Colors.white, fontSize: 14),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          // 開いたあとから対象アプリを複数選択できる
          TextButton.icon(
            onPressed: _pickTargetApps,
            icon: const Icon(Icons.checklist, size: 16, color: Colors.white70),
            label: Text(
              s.targetAppsCount(_targetPkgs.length),
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
          if (_hasExisting)
            TextButton(
              onPressed: _release,
              child: Text(
                s.actionRelease,
                style: const TextStyle(color: Colors.redAccent, fontSize: 12),
              ),
            ),
        ],
      ),
      body: _buildScheduleBody(bottomPad),
    );
  }

  // ── Schedule body ───────────────────────────────────────────

  Widget _buildScheduleBody(double bottomPad) {
    final s = S.of(context);
    final wdLabels = _weekdayLabels(context);
    return Column(
      children: [
        // 雎亥叙蠕・/ 隴匁㊧蠕玖崕・･ toggle
        Container(
          color: const Color(0xFF111111),
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
          child: Row(
            children: [
              _chip(s.scheduleEveryDay, _dailyMode, () {
                if (_dailyMode) return;
                setState(() => _dailyMode = true);
              }),
              const SizedBox(width: 8),
              _chip(s.scheduleByWeekday, !_dailyMode, () {
                if (!_dailyMode) return;
                setState(() {
                  final srcDefault =
                      _defaults[_editingWeekday] ?? _SlotConfig(type: 'keep');
                  final srcSlots =
                      _schedules[_editingWeekday] ?? const <_SlotConfig>[];
                  for (int wd = 1; wd <= 7; wd++) {
                    _defaults[wd] = srcDefault.copy();
                    _schedules[wd] = srcSlots.map((c) => c.copy()).toList();
                  }
                  _dailyMode = false;
                });
              }),
            ],
          ),
        ),

        // ── Weekday selector () ─────────────────────────────────────
        if (!_dailyMode)
          Container(
            color: const Color(0xFF111111),
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: List.generate(7, (i) {
                final wd = i + 1;
                final selected = _editingWeekday == wd;
                return GestureDetector(
                  onTap: () => setState(() => _editingWeekday = wd),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: selected ? Colors.white : Colors.transparent,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      wdLabels[i],
                      style: TextStyle(
                        color: selected ? Colors.black : Colors.white54,
                        fontSize: 13,
                        fontWeight: selected
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),

        // Body
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            children: [
              _buildScheduleListSection(),
              const SizedBox(height: 20),
              _buildDefaultSection(),
              const SizedBox(height: 12),
            ],
          ),
        ),

        // Bottom buttons
        Padding(
          padding: EdgeInsets.fromLTRB(12, 8, 12, 12 + bottomPad),
          child: Row(
            children: [
              if (!_dailyMode) ...[
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white70,
                      side: const BorderSide(color: Colors.white24),
                    ),
                    onPressed: _showCopyDialog,
                    child: Text(
                      S.of(context).copyToOtherDays,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                  ),
                  onPressed: _save,
                  child: Text(S.of(context).actionSave),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDefaultSection() {
    final s = S.of(context);
    final cfg = _defaults[_editingWeekday] ??= _SlotConfig(type: 'keep');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          s.defaultFloorLabel,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          s.defaultKeepDesc,
          style: const TextStyle(color: Colors.white38, fontSize: 12),
        ),
        const SizedBox(height: 8),
        // スロットと同じ種別（位置保持/固定/ランダム/使用回数/使用時間）を選べる
        _buildTypeAndFloorEditor(cfg, setState, includeKeep: true),
      ],
    );
  }

  Widget _buildScheduleListSection() {
    final s = S.of(context);
    final slots = _schedules[_editingWeekday] ?? const [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                s.scheduleLabel,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            GestureDetector(
              onTap: () => _showSlotEditDialog(),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Text(
                  s.addSchedule,
                  style: const TextStyle(
                    color: Colors.tealAccent,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        if (slots.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              s.noScheduleHint,
              style: const TextStyle(color: Colors.white38, fontSize: 11),
            ),
          )
        else
          ...slots.asMap().entries.map((e) {
            return _scheduleCard(e.key, e.value);
          }),
      ],
    );
  }

  Widget _scheduleCard(int idx, _SlotConfig cfg) {
    final timeLabel =
        '${_fmtTime(cfg.startMinute)} 〜 ${_fmtTime(cfg.endMinute)}';
    final detail = _slotDetail(cfg);
    return Card(
      color: const Color(0xFF1A1A1A),
      margin: const EdgeInsets.only(bottom: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () => _showSlotEditDialog(editingIndex: idx),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      timeLabel,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      detail,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                icon: const Icon(
                  Icons.close,
                  color: Colors.redAccent,
                  size: 18,
                ),
                onPressed: () {
                  setState(() {
                    _schedules[_editingWeekday]!.removeAt(idx);
                  });
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _slotDetail(_SlotConfig cfg) {
    final s = S.of(context);
    if (cfg.type == 'keep') return s.keepPosition;
    if (cfg.type == 'fixed') return s.scheduleArrowFloor(floorLabel(cfg.floor));
    if (cfg.type == 'random') return s.scheduleArrowRandom(cfg.floors.length);
    final rules = cfg.type == 'usageTime' ? cfg.timeRules : cfg.countRules;
    if (rules.isEmpty) return s.notSet;
    return usageRangeLabels(
      s,
      rules,
      isTime: cfg.type == 'usageTime',
    ).join(' / ');
  }

  // ── Slot add/edit dialog ────────────────────────────────────

  Future<void> _showSlotEditDialog({int? editingIndex}) async {
    final isEdit = editingIndex != null;
    final source = isEdit ? _schedules[_editingWeekday]![editingIndex] : null;
    final draft =
        source?.copy() ?? _SlotConfig(startMinute: 9 * 60, endMinute: 17 * 60);

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInner) {
          final s = S.of(ctx);
          return AlertDialog(
            backgroundColor: const Color(0xFF1A1A1A),
            title: Text(
              isEdit ? s.scheduleEdit : s.scheduleAdd,
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
            contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            content: SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(ctx).size.width,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildExistingSlotsHint(editingIndex),
                    Row(
                      children: [
                        Expanded(
                          child: _timePickerButton(
                            ctx,
                            s.startTimeLabel,
                            draft.startMinute,
                            (m) => setInner(() => draft.startMinute = m),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _timePickerButton(
                            ctx,
                            s.endTimeLabel,
                            draft.endMinute,
                            (m) => setInner(() => draft.endMinute = m),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // 0:00〜24:00 を一発で入れる
                    Align(
                      alignment: Alignment.centerLeft,
                      child: _chip(
                        s.allDay,
                        draft.startMinute == 0 && draft.endMinute == 1440,
                        () => setInner(() {
                          draft.startMinute = 0;
                          draft.endMinute = 1440;
                        }),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildTypeAndFloorEditor(draft, setInner),
                    const SizedBox(height: 8),
                  ],
                ),
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
                onPressed: () {
                  if (draft.startMinute >= draft.endMinute) {
                    _showSnack(s.startMustBeBeforeEnd);
                    return;
                  }
                  if (_hasOverlap(
                    _editingWeekday,
                    draft,
                    editingIndex: editingIndex,
                  )) {
                    _showSnack(s.timeRangeOverlap);
                    return;
                  }
                  if (isEdit) {
                    _schedules[_editingWeekday]![editingIndex] = draft;
                  } else {
                    _schedules[_editingWeekday]!.add(draft);
                  }
                  _schedules[_editingWeekday]!.sort(
                    (a, b) => a.startMinute.compareTo(b.startMinute),
                  );
                  Navigator.pop(ctx);
                  setState(() {});
                },
                child: Text(
                  isEdit ? s.actionSave : s.actionAdd,
                  style: const TextStyle(color: Colors.tealAccent),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Shown at the top of the slot add/edit dialog so the user can see what
  /// other time bands are already taken on the same weekday and pick a free
  /// window. [editingIndex] excludes the slot currently being edited so the
  /// user doesn't see their own row.
  Widget _buildExistingSlotsHint(int? editingIndex) {
    final s = S.of(context);
    final slots = _schedules[_editingWeekday] ?? const <_SlotConfig>[];
    final others = <(_SlotConfig, int)>[];
    for (int i = 0; i < slots.length; i++) {
      if (i == editingIndex) continue;
      others.add((slots[i], i));
    }
    others.sort((a, b) => a.$1.startMinute.compareTo(b.$1.startMinute));
    if (others.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            s.registeredSchedules,
            style: const TextStyle(color: Colors.white54, fontSize: 11),
          ),
          const SizedBox(height: 4),
          for (final entry in others)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 1),
              child: Text(
                '  ${_fmtTime(entry.$1.startMinute)}-${_fmtTime(entry.$1.endMinute)}'
                '  ${_slotDetail(entry.$1)}',
                style: const TextStyle(color: Colors.white70, fontSize: 11),
              ),
            ),
        ],
      ),
    );
  }

  Widget _timePickerButton(
    BuildContext context,
    String label,
    int minutes,
    ValueChanged<int> onChanged,
  ) {
    final h = (minutes ~/ 60).clamp(0, 23);
    final m = (minutes % 60).clamp(0, 59);
    return GestureDetector(
      onTap: () async {
        final picked = await showTimePicker(
          context: context,
          initialTime: TimeOfDay(hour: h, minute: m),
          initialEntryMode: TimePickerEntryMode.input,
          builder: (ctx, child) => Theme(
            data: ThemeData.dark().copyWith(
              colorScheme: const ColorScheme.dark(
                primary: Colors.tealAccent,
                onPrimary: Colors.black,
                surface: Color(0xFF1A1A1A),
                onSurface: Colors.white,
              ),
            ),
            child: child ?? const SizedBox.shrink(),
          ),
        );
        if (picked != null) {
          onChanged(picked.hour * 60 + picked.minute);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(color: Colors.white54, fontSize: 11),
            ),
            const SizedBox(height: 4),
            Text(
              _fmtTime(minutes),
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }

  String _fmtTime(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

  // ── Reusable type+floor editor (used by the slot dialog) ────

  Widget _buildTypeAndFloorEditor(
    _SlotConfig cfg,
    void Function(VoidCallback) setter, {
    bool includeKeep = false,
  }) {
    final s = S.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 4〜5個のチップが横にはみ出すので Wrap で折り返す
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (includeKeep)
              _chip(s.keepPosition, cfg.type == 'keep', () {
                setter(() => cfg.type = 'keep');
              }),
            _chip(s.fixedFloor, cfg.type == 'fixed', () {
              setter(() => cfg.type = 'fixed');
            }),
            _chip(s.randomFloor, cfg.type == 'random', () {
              setter(() => cfg.type = 'random');
            }),
            _chip(s.modeUsageCount, cfg.type == 'usageCount', () {
              setter(() => cfg.type = 'usageCount');
            }),
            _chip(s.modeUsageTime, cfg.type == 'usageTime', () {
              setter(() => cfg.type = 'usageTime');
            }),
          ],
        ),
        const SizedBox(height: 8),
        if (cfg.type == 'fixed') ...[
          Text(
            s.placementFloorLabel,
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(height: 4),
          _buildFloorChipsSingle(cfg.floor, (f) {
            setter(() => cfg.floor = f);
          }),
        ] else if (cfg.type == 'random') ...[
          Text(
            s.targetFloorsLabel,
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(height: 4),
          _buildFloorChips(cfg.floors, (floors) {
            setter(() => cfg.floors = floors);
          }),
          const SizedBox(height: 8),
          Text(
            s.shuffleModeLabel,
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(height: 4),
          _chip(s.shuffleOnceAtStart, cfg.shuffleMode == 'once', () {
            setter(() => cfg.shuffleMode = 'once');
          }),
          const SizedBox(height: 4),
          _chip(s.shuffleRepeatInterval, cfg.shuffleMode == 'repeat', () {
            setter(() => cfg.shuffleMode = 'repeat');
          }),
          if (cfg.shuffleMode == 'repeat') ...[
            const SizedBox(height: 4),
            _buildRepeatIntervalRow(cfg),
          ],
          const SizedBox(height: 4),
          _chip(s.shuffleSpecifiedCount, cfg.shuffleMode == 'count', () {
            setter(() => cfg.shuffleMode = 'count');
          }),
          if (cfg.shuffleMode == 'count') ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Text(
                  s.countLabel,
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
                SizedBox(
                  width: 50,
                  child: TextField(
                    controller: TextEditingController(
                      text: cfg.shuffleCount.toString(),
                    ),
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    keyboardType: TextInputType.number,
                    decoration: _smallFieldDeco(),
                    onChanged: (v) {
                      final n = int.tryParse(v);
                      if (n != null && n > 0) cfg.shuffleCount = n;
                    },
                  ),
                ),
              ],
            ),
          ],
        ] else if (cfg.type == 'usageCount') ...[
          _buildRulesEditor(
            rules: cfg.countRules,
            isTime: false,
            setter: setter,
          ),
        ] else if (cfg.type == 'usageTime') ...[
          _buildRulesEditor(rules: cfg.timeRules, isTime: true, setter: setter),
        ],
      ],
    );
  }

  // ── Shared widgets ──────────────────────────────────────────

  Widget _buildRulesEditor({
    required List<Map<String, int>> rules,
    required bool isTime,
    required void Function(VoidCallback) setter,
  }) {
    final s = S.of(context);
    Future<void> editRule({Map<String, int>? existing, int? index}) async {
      int threshold = existing?['threshold'] ?? (isTime ? 30 : 5);
      int floor = existing?['floor'] ?? 1;
      final ctrl = TextEditingController(text: threshold.toString());
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setInner) => AlertDialog(
            backgroundColor: const Color(0xFF1A1A1A),
            title: Text(
              existing == null ? s.ruleAdd : s.ruleEdit,
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isTime ? s.rangeStartTimeLabel : s.rangeStartCountLabel,
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
                const SizedBox(height: 4),
                TextField(
                  controller: ctrl,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.07),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: BorderSide.none,
                    ),
                    suffixText: isTime ? s.minutesSuffix : s.thresholdSuffix,
                    suffixStyle: const TextStyle(
                      color: Colors.white38,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  s.targetFloorLabel,
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
                const SizedBox(height: 4),
                _buildFloorChipsSingle(floor, (f) {
                  setInner(() => floor = f);
                }),
              ],
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
                  s.actionSave,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      );
      if (ok != true) return;
      threshold = int.tryParse(ctrl.text) ?? threshold;
      setter(() {
        final newRule = {'threshold': threshold, 'floor': floor};
        if (index == null) {
          rules.add(newRule);
        } else {
          rules[index] = newRule;
        }
        rules.sort((a, b) => a['threshold']!.compareTo(b['threshold']!));
      });
    }

    // 区間表示のラベル（rules はしきい値昇順で保持されている）
    final rangeLabels = usageRangeLabels(s, rules, isTime: isTime);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          isTime ? s.usageTimeRangeHelp : s.usageCountRangeHelp,
          style: const TextStyle(color: Colors.white54, fontSize: 12),
        ),
        const SizedBox(height: 6),
        for (final entry in rules.asMap().entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () =>
                        editRule(existing: entry.value, index: entry.key),
                    child: Text(
                      entry.key < rangeLabels.length
                          ? rangeLabels[entry.key]
                          : '',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(
                    Icons.close,
                    color: Colors.redAccent,
                    size: 16,
                  ),
                  onPressed: () => setter(() => rules.removeAt(entry.key)),
                ),
              ],
            ),
          ),
        TextButton.icon(
          style: TextButton.styleFrom(
            foregroundColor: Colors.tealAccent,
            padding: EdgeInsets.zero,
          ),
          onPressed: () => editRule(),
          icon: const Icon(Icons.add, size: 16),
          label: Text(s.ruleAdd, style: const TextStyle(fontSize: 12)),
        ),
      ],
    );
  }

  Widget _buildRepeatIntervalRow(_SlotConfig cfg) {
    final s = S.of(context);
    return Row(
      children: [
        _smallInput(
          s.intervalDayUnit,
          cfg.repeatDays,
          (v) => cfg.repeatDays = v,
        ),
        const SizedBox(width: 6),
        _smallInput(
          s.intervalHourUnit,
          cfg.repeatHours,
          (v) => cfg.repeatHours = v,
        ),
        const SizedBox(width: 6),
        _smallInput(
          s.intervalMinuteUnit,
          cfg.repeatMinutes,
          (v) => cfg.repeatMinutes = v,
        ),
      ],
    );
  }

  Widget _smallInput(String label, int value, void Function(int) onChanged) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 36,
          child: TextField(
            controller: TextEditingController(text: value.toString()),
            style: const TextStyle(color: Colors.white, fontSize: 12),
            keyboardType: TextInputType.number,
            decoration: _smallFieldDeco(),
            onChanged: (v) {
              final n = int.tryParse(v);
              if (n != null && n >= 0) onChanged(n);
            },
          ),
        ),
        const SizedBox(width: 2),
        Text(
          label,
          style: const TextStyle(color: Colors.white38, fontSize: 10),
        ),
      ],
    );
  }

  InputDecoration _smallFieldDeco() {
    return InputDecoration(
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.07),
      contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: BorderSide.none,
      ),
      isDense: true,
    );
  }

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
            fontSize: 11,
          ),
        ),
      ),
    );
  }

  Widget _buildFloorChipsSingle(
    int selectedFloor,
    void Function(int) onChanged,
  ) {
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: _allFloorOptions.map((f) {
        final isSelected = f == selectedFloor;
        return GestureDetector(
          onTap: () => onChanged(f),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: isSelected ? Colors.white : Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: isSelected ? Colors.white : Colors.white24,
              ),
            ),
            child: Text(
              floorLabel(f),
              style: TextStyle(
                color: isSelected ? Colors.black : Colors.white54,
                fontSize: 11,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildFloorChips(
    List<int> selected,
    void Function(List<int>) onChanged,
  ) {
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: _allFloorOptions.map((f) {
        final isSelected = selected.contains(f);
        return GestureDetector(
          onTap: () {
            final newList = List<int>.from(selected);
            if (isSelected) {
              newList.remove(f);
            } else {
              newList.add(f);
            }
            onChanged(newList);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: isSelected ? Colors.white : Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: isSelected ? Colors.white : Colors.white24,
              ),
            ),
            child: Text(
              floorLabel(f),
              style: TextStyle(
                color: isSelected ? Colors.black : Colors.white54,
                fontSize: 11,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  void _showCopyDialog() {
    final wdLabels = _weekdayLabels(context);
    final targets = <int>{};
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInner) {
          final s = S.of(ctx);
          return AlertDialog(
            backgroundColor: const Color(0xFF1A1A1A),
            title: Text(
              s.copyToWeekdaysTitle,
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
            content: Wrap(
              alignment: WrapAlignment.start,
              spacing: 8,
              runSpacing: 8,
              children: [
                for (int i = 0; i < 7; i++)
                  if (i + 1 != _editingWeekday)
                    Builder(
                      builder: (_) {
                        final wd = i + 1;
                        final selected = targets.contains(wd);
                        return GestureDetector(
                          onTap: () {
                            setInner(() {
                              if (selected) {
                                targets.remove(wd);
                              } else {
                                targets.add(wd);
                              }
                            });
                          },
                          child: Container(
                            width: 44,
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: selected
                                  ? Colors.white
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: selected ? Colors.white : Colors.white24,
                              ),
                            ),
                            child: Text(
                              wdLabels[i],
                              style: TextStyle(
                                color: selected ? Colors.black : Colors.white54,
                              ),
                            ),
                          ),
                        );
                      },
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
              TextButton(
                onPressed: () {
                  final srcDefault =
                      _defaults[_editingWeekday] ?? _SlotConfig(type: 'keep');
                  final srcSlots =
                      _schedules[_editingWeekday] ?? const <_SlotConfig>[];
                  for (final wd in targets) {
                    _defaults[wd] = srcDefault.copy();
                    _schedules[wd] = srcSlots.map((c) => c.copy()).toList();
                  }
                  Navigator.pop(ctx);
                  setState(() {});
                },
                child: Text(
                  s.actionCopy,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ── Slot config model ───────────────────────────────────────

class _SlotConfig {
  int startMinute;
  int endMinute;
  String
  type; // 'fixed' | 'random' | 'keep'（keep は動かさない＝位置保持）
  int floor;
  List<int> floors;
  List<Map<String, int>> countRules;
  List<Map<String, int>> timeRules;
  String shuffleMode; // 'once' | 'repeat' | 'count'
  int repeatDays;
  int repeatHours;
  int repeatMinutes;
  int shuffleCount;

  _SlotConfig({
    this.startMinute = 0,
    this.endMinute = 1440,
    this.type = 'fixed',
    this.floor = 1,
    this.floors = const [1, 2, 3],
    this.countRules = const [],
    this.timeRules = const [],
    this.shuffleMode = 'once',
    this.repeatDays = 0,
    this.repeatHours = 1,
    this.repeatMinutes = 0,
    this.shuffleCount = 3,
  });

  factory _SlotConfig.fromMap(Map<String, dynamic> m) {
    return _SlotConfig(
      startMinute: (m['startMinute'] as num?)?.toInt() ?? 0,
      endMinute: (m['endMinute'] as num?)?.toInt() ?? 1440,
      type: (m['type'] as String?) ?? 'fixed',
      floor: (m['floor'] as num?)?.toInt() ?? 1,
      floors:
          (m['floors'] as List?)?.map((e) => (e as num).toInt()).toList() ??
          [1, 2, 3],
      countRules: ((m['countRules'] as List?) ?? const []).map((e) {
        final r = e as Map;
        return {
          'threshold': (r['threshold'] as num).toInt(),
          'floor': (r['floor'] as num).toInt(),
        };
      }).toList(),
      timeRules: ((m['timeRules'] as List?) ?? const []).map((e) {
        final r = e as Map;
        return {
          'threshold': (r['threshold'] as num).toInt(),
          'floor': (r['floor'] as num).toInt(),
        };
      }).toList(),
      shuffleMode: (m['shuffleMode'] as String?) ?? 'once',
      repeatDays: (m['repeatDays'] as num?)?.toInt() ?? 0,
      repeatHours: (m['repeatHours'] as num?)?.toInt() ?? 1,
      repeatMinutes: (m['repeatMinutes'] as num?)?.toInt() ?? 0,
      shuffleCount: (m['shuffleCount'] as num?)?.toInt() ?? 3,
    );
  }

  Map<String, dynamic> toMap() => {
    'startMinute': startMinute,
    'endMinute': endMinute,
    'type': type,
    'floor': floor,
    'floors': List<int>.from(floors),
    'countRules': countRules.map((r) => Map<String, int>.from(r)).toList(),
    'timeRules': timeRules.map((r) => Map<String, int>.from(r)).toList(),
    'shuffleMode': shuffleMode,
    'repeatDays': repeatDays,
    'repeatHours': repeatHours,
    'repeatMinutes': repeatMinutes,
    'shuffleCount': shuffleCount,
  };

  _SlotConfig copy() => _SlotConfig.fromMap(toMap());
}
