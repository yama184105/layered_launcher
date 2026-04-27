import 'package:flutter/material.dart';
import '../../models/app_config.dart';
import '../../services/settings_service.dart';
import '../home/home_screen.dart' show floorLabel;

class AutoMoveScreen extends StatefulWidget {
  final SettingsService settingsService;
  final List<String> packageNames;
  final List<AppConfig> allApps;
  const AutoMoveScreen({
    super.key,
    required this.settingsService,
    required this.packageNames,
    required this.allApps,
  });

  @override
  State<AutoMoveScreen> createState() => _AutoMoveScreenState();
}

class _AutoMoveScreenState extends State<AutoMoveScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  late SettingsService _ss;

  // Mode B state
  int _intervalDays = 1;
  List<int> _intervalFloors = [1, 2, 3];

  // Mode A state — default + slot list per weekday
  final Map<int, _SlotConfig> _defaults = {};
  final Map<int, List<_SlotConfig>> _schedules = {};
  int _editingWeekday = 1;

  bool _isBulk = false;
  String _currentMode = 'none';

  static const _weekdayLabels = ['月', '火', '水', '木', '金', '土', '日'];

  @override
  void initState() {
    super.initState();
    _ss = widget.settingsService;
    _isBulk = widget.packageNames.length > 1;
    _tabCtrl = TabController(length: 2, vsync: this);

    final pkg = widget.packageNames.first;
    _currentMode = _ss.autoMoveMode(pkg);

    _intervalDays = _ss.autoMoveIntervalDays(pkg);
    _intervalFloors = _ss.autoMoveIntervalFloors(pkg);

    _loadSchedule(pkg);

    if (_currentMode == 'schedule') {
      _tabCtrl.index = 0;
    } else if (_currentMode == 'interval') {
      _tabCtrl.index = 1;
    }
  }

  void _loadSchedule(String pkg) {
    _defaults.clear();
    _schedules.clear();
    final raw = _ss.autoMoveSchedule(pkg);
    for (int wd = 1; wd <= 7; wd++) {
      _defaults[wd] = _SlotConfig();
      _schedules[wd] = [];
      final key = wd.toString();
      if (!raw.containsKey(key)) continue;
      final dayData = Map<String, dynamic>.from(raw[key] as Map);
      if (dayData['default'] is Map) {
        _defaults[wd] = _SlotConfig.fromMap(
            Map<String, dynamic>.from(dayData['default'] as Map));
      }
      final slots = (dayData['slots'] as List?) ?? [];
      for (final s in slots) {
        if (s is! Map) continue;
        final m = Map<String, dynamic>.from(s);
        final cfg = _SlotConfig.fromMap(m);
        // 旧形式互換: 0〜1440 をカバーする単一スロットはデフォルトとして扱わず、
        // そのままスケジュールに残す（ユーザーが整理できる）。ただし0〜1440単独で
        // default が無い場合はそれをデフォルト化する。
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
      _schedules[wd]!
          .sort((a, b) => a.startMinute.compareTo(b.startMinute));
    }
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
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

  Future<void> _save(String mode) async {
    if (mode == 'schedule') {
      // 全曜日の重複・不正チェック
      for (int wd = 1; wd <= 7; wd++) {
        final slots = _schedules[wd] ?? const [];
        for (int i = 0; i < slots.length; i++) {
          final a = slots[i];
          if (a.startMinute >= a.endMinute) {
            _showSnack('${_weekdayLabels[wd - 1]}曜日のスケジュールに不正な時刻があります');
            return;
          }
          for (int j = i + 1; j < slots.length; j++) {
            final b = slots[j];
            if (a.startMinute < b.endMinute && a.endMinute > b.startMinute) {
              _showSnack(
                  '${_weekdayLabels[wd - 1]}曜日のスケジュールに時間帯重複があります');
              return;
            }
          }
        }
      }
    }

    for (final pkg in widget.packageNames) {
      if (_ss.isFloorMoveLocked(pkg)) {
        final confirmed = await _showStrictConfirmDialog();
        if (!confirmed) return;
      }

      await _ss.setAutoMoveMode(pkg, mode);

      if (mode == 'interval') {
        await _ss.setAutoMoveIntervalDays(pkg, _intervalDays);
        await _ss.setAutoMoveIntervalFloors(pkg, _intervalFloors);
      } else if (mode == 'schedule') {
        final map = <String, dynamic>{};
        for (int wd = 1; wd <= 7; wd++) {
          final defaultCfg = _defaults[wd] ?? _SlotConfig();
          final slots = _schedules[wd] ?? const <_SlotConfig>[];
          map[wd.toString()] = {
            'default': defaultCfg.toMap(),
            'slots': slots.map((s) => s.toMap()).toList(),
          };
        }
        await _ss.setAutoMoveSchedule(pkg, map);
      }
    }
    if (mounted) Navigator.pop(context, true);
  }

  Future<bool> _showStrictConfirmDialog() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('ストリクトモード',
            style: TextStyle(color: Colors.white, fontSize: 15)),
        content: const Text(
          'このアプリはフロア移動ロック中です。ブロック/タイマーを適用しますか？',
          style: TextStyle(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('キャンセル',
                style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('適用', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final title = _isBulk
        ? '自動移動 (${widget.packageNames.length}アプリ)'
        : '自動移動 - ${_appName(widget.packageNames.first)}';
    final bottomPad = MediaQuery.of(context).viewPadding.bottom;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: const Color(0xFF111111),
        title: Text(title,
            style: const TextStyle(color: Colors.white, fontSize: 14)),
        iconTheme: const IconThemeData(color: Colors.white),
        bottom: TabBar(
          controller: _tabCtrl,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white38,
          tabs: const [
            Tab(text: 'スケジュール制'),
            Tab(text: '日数間隔ランダム'),
          ],
        ),
        actions: [
          if (_currentMode != 'none')
            TextButton(
              onPressed: () async {
                for (final pkg in widget.packageNames) {
                  await _ss.clearAutoMove(pkg);
                }
                if (mounted) Navigator.pop(context, true);
              },
              child: const Text('解除',
                  style: TextStyle(color: Colors.redAccent, fontSize: 12)),
            ),
        ],
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          _buildScheduleTab(bottomPad),
          _buildIntervalTab(bottomPad),
        ],
      ),
    );
  }

  // ── Mode B: Interval Random Tab ─────────────────────────────────────────

  Widget _buildIntervalTab(double bottomPad) {
    return ListView(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomPad),
      children: [
        const Text('指定日数ごとにランダムなフロアに配置',
            style: TextStyle(color: Colors.white70, fontSize: 13)),
        const SizedBox(height: 16),
        Row(
          children: [
            const Text('間隔: ',
                style: TextStyle(color: Colors.white, fontSize: 14)),
            SizedBox(
              width: 60,
              child: TextField(
                controller:
                    TextEditingController(text: _intervalDays.toString()),
                style: const TextStyle(color: Colors.white, fontSize: 14),
                keyboardType: TextInputType.number,
                decoration: _fieldDeco(),
                onChanged: (v) {
                  final n = int.tryParse(v);
                  if (n != null && n >= 0) setState(() => _intervalDays = n);
                },
              ),
            ),
            const Text(' 日ごと',
                style: TextStyle(color: Colors.white, fontSize: 14)),
            const SizedBox(width: 8),
            const Text('(0=毎日)',
                style: TextStyle(color: Colors.white38, fontSize: 11)),
          ],
        ),
        const SizedBox(height: 20),
        const Text('対象フロア:',
            style: TextStyle(color: Colors.white, fontSize: 14)),
        const SizedBox(height: 8),
        _buildFloorChips(_intervalFloors, (floors) {
          setState(() => _intervalFloors = floors);
        }),
        const SizedBox(height: 32),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: Colors.black,
          ),
          onPressed:
              _intervalFloors.isEmpty ? null : () => _save('interval'),
          child: const Text('保存'),
        ),
      ],
    );
  }

  // ── Mode A: Schedule Tab ────────────────────────────────────────────────

  Widget _buildScheduleTab(double bottomPad) {
    return Column(
      children: [
        // Weekday selector
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: selected ? Colors.white : Colors.transparent,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(_weekdayLabels[i],
                      style: TextStyle(
                        color: selected ? Colors.black : Colors.white54,
                        fontSize: 13,
                        fontWeight:
                            selected ? FontWeight.bold : FontWeight.normal,
                      )),
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
              _buildDefaultSection(),
              const SizedBox(height: 20),
              _buildScheduleListSection(),
              const SizedBox(height: 12),
            ],
          ),
        ),

        // Bottom buttons
        Padding(
          padding: EdgeInsets.fromLTRB(12, 8, 12, 12 + bottomPad),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: const BorderSide(color: Colors.white24),
                  ),
                  onPressed: _showCopyDialog,
                  child: const Text('他の曜日にコピー',
                      style: TextStyle(fontSize: 12)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                  ),
                  onPressed: () => _save('schedule'),
                  child: const Text('保存'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDefaultSection() {
    final cfg = _defaults[_editingWeekday] ??= _SlotConfig();
    // Default is fixed-only — random/shuffle is reserved for slots & mode B.
    if (cfg.type != 'fixed') {
      cfg.type = 'fixed';
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('デフォルトフロア',
            style: TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w500)),
        const SizedBox(height: 4),
        const Text('スケジュール外の時間帯に適用されるフロアです',
            style: TextStyle(color: Colors.white38, fontSize: 12)),
        const SizedBox(height: 8),
        _buildFloorChipsSingle(cfg.floor, (f) {
          setState(() => cfg.floor = f);
        }),
      ],
    );
  }

  Widget _buildScheduleListSection() {
    final slots = _schedules[_editingWeekday] ?? const [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text('スケジュール',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w500)),
            ),
            GestureDetector(
              onTap: () => _showSlotEditDialog(),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Text('＋ 追加',
                    style:
                        TextStyle(color: Colors.tealAccent, fontSize: 12)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        if (slots.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('スケジュールなし（デフォルトフロアが常に適用されます）',
                style: TextStyle(color: Colors.white38, fontSize: 11)),
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
    final detail = cfg.type == 'fixed'
        ? '→ ${floorLabel(cfg.floor)}'
        : '→ ランダム (${cfg.floors.length}フロア)';
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
                    Text(timeLabel,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 14)),
                    const SizedBox(height: 2),
                    Text(detail,
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 12)),
                  ],
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                    minWidth: 32, minHeight: 32),
                icon: const Icon(Icons.close,
                    color: Colors.redAccent, size: 18),
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

  // ── Slot add/edit dialog ────────────────────────────────────────────────

  Future<void> _showSlotEditDialog({int? editingIndex}) async {
    final isEdit = editingIndex != null;
    final source =
        isEdit ? _schedules[_editingWeekday]![editingIndex] : null;
    final draft = source?.copy() ??
        _SlotConfig(startMinute: 9 * 60, endMinute: 17 * 60);

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInner) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          title: Text(isEdit ? 'スケジュール編集' : 'スケジュール追加',
              style:
                  const TextStyle(color: Colors.white, fontSize: 14)),
          contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          content: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(ctx).size.width),
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
                          '開始',
                          draft.startMinute,
                          (m) => setInner(() => draft.startMinute = m),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _timePickerButton(
                          ctx,
                          '終了',
                          draft.endMinute,
                          (m) => setInner(() => draft.endMinute = m),
                        ),
                      ),
                    ],
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
              child: const Text('キャンセル',
                  style: TextStyle(color: Colors.white54)),
            ),
            TextButton(
              onPressed: () {
                if (draft.startMinute >= draft.endMinute) {
                  _showSnack('開始時刻は終了時刻より前にしてください');
                  return;
                }
                if (_hasOverlap(_editingWeekday, draft,
                    editingIndex: editingIndex)) {
                  _showSnack('時間帯が重複しています');
                  return;
                }
                if (isEdit) {
                  _schedules[_editingWeekday]![editingIndex] = draft;
                } else {
                  _schedules[_editingWeekday]!.add(draft);
                }
                _schedules[_editingWeekday]!.sort(
                    (a, b) => a.startMinute.compareTo(b.startMinute));
                Navigator.pop(ctx);
                setState(() {});
              },
              child: Text(isEdit ? '保存' : '追加',
                  style: const TextStyle(color: Colors.tealAccent)),
            ),
          ],
        ),
      ),
    );
  }

  /// Shown at the top of the slot add/edit dialog so the user can see what
  /// other time bands are already taken on the same weekday and pick a free
  /// window. [editingIndex] excludes the slot currently being edited so the
  /// user doesn't see their own row.
  Widget _buildExistingSlotsHint(int? editingIndex) {
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
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('登録済みスケジュール',
              style: TextStyle(color: Colors.white54, fontSize: 11)),
          const SizedBox(height: 4),
          for (final entry in others)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 1),
              child: Text(
                '  ${_fmtTime(entry.$1.startMinute)}〜${_fmtTime(entry.$1.endMinute)}'
                '  →  ${entry.$1.type == 'fixed' ? floorLabel(entry.$1.floor) : 'ランダム(${entry.$1.floors.length}フロア)'}',
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
        padding:
            const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.07),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(
                    color: Colors.white54, fontSize: 11)),
            const SizedBox(height: 4),
            Text(_fmtTime(minutes),
                style: const TextStyle(
                    color: Colors.white, fontSize: 16)),
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

  // ── Reusable type+floor editor (used by default section and dialog) ────

  Widget _buildTypeAndFloorEditor(
    _SlotConfig cfg,
    void Function(VoidCallback) setter,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _chip('固定フロア', cfg.type == 'fixed', () {
              setter(() => cfg.type = 'fixed');
            }),
            const SizedBox(width: 8),
            _chip('ランダムフロア', cfg.type == 'random', () {
              setter(() => cfg.type = 'random');
            }),
          ],
        ),
        const SizedBox(height: 8),
        if (cfg.type == 'fixed') ...[
          const Text('配置先フロア:',
              style: TextStyle(color: Colors.white54, fontSize: 12)),
          const SizedBox(height: 4),
          _buildFloorChipsSingle(cfg.floor, (f) {
            setter(() => cfg.floor = f);
          }),
        ] else ...[
          const Text('対象フロア:',
              style: TextStyle(color: Colors.white54, fontSize: 12)),
          const SizedBox(height: 4),
          _buildFloorChips(cfg.floors, (floors) {
            setter(() => cfg.floors = floors);
          }),
          const SizedBox(height: 8),
          const Text('シャッフル方式:',
              style: TextStyle(color: Colors.white54, fontSize: 12)),
          const SizedBox(height: 4),
          _chip('時間帯の最初に1回', cfg.shuffleMode == 'once', () {
            setter(() => cfg.shuffleMode = 'once');
          }),
          const SizedBox(height: 4),
          _chip('一定間隔で繰り返し', cfg.shuffleMode == 'repeat', () {
            setter(() => cfg.shuffleMode = 'repeat');
          }),
          if (cfg.shuffleMode == 'repeat') ...[
            const SizedBox(height: 4),
            _buildRepeatIntervalRow(cfg),
          ],
          const SizedBox(height: 4),
          _chip('指定回数実行', cfg.shuffleMode == 'count', () {
            setter(() => cfg.shuffleMode = 'count');
          }),
          if (cfg.shuffleMode == 'count') ...[
            const SizedBox(height: 4),
            Row(
              children: [
                const Text('回数: ',
                    style: TextStyle(
                        color: Colors.white54, fontSize: 12)),
                SizedBox(
                  width: 50,
                  child: TextField(
                    controller: TextEditingController(
                        text: cfg.shuffleCount.toString()),
                    style: const TextStyle(
                        color: Colors.white, fontSize: 13),
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
        ],
      ],
    );
  }

  // ── Shared widgets ──────────────────────────────────────────────────────

  Widget _buildRepeatIntervalRow(_SlotConfig cfg) {
    return Row(
      children: [
        _smallInput('日', cfg.repeatDays, (v) => cfg.repeatDays = v),
        const SizedBox(width: 6),
        _smallInput('時間', cfg.repeatHours, (v) => cfg.repeatHours = v),
        const SizedBox(width: 6),
        _smallInput('分', cfg.repeatMinutes, (v) => cfg.repeatMinutes = v),
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
        Text(label,
            style: const TextStyle(color: Colors.white38, fontSize: 10)),
      ],
    );
  }

  InputDecoration _fieldDeco() {
    return InputDecoration(
      filled: true,
      fillColor: Colors.white.withOpacity(0.07),
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: BorderSide.none,
      ),
    );
  }

  InputDecoration _smallFieldDeco() {
    return InputDecoration(
      filled: true,
      fillColor: Colors.white.withOpacity(0.07),
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
          color: selected ? Colors.white : Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: selected ? Colors.white : Colors.white24),
        ),
        child: Text(label,
            style: TextStyle(
              color: selected ? Colors.black : Colors.white54,
              fontSize: 11,
            )),
      ),
    );
  }

  Widget _buildFloorChipsSingle(
      int selectedFloor, void Function(int) onChanged) {
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
              color:
                  isSelected ? Colors.white : Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                  color: isSelected ? Colors.white : Colors.white24),
            ),
            child: Text(floorLabel(f),
                style: TextStyle(
                  color: isSelected ? Colors.black : Colors.white54,
                  fontSize: 11,
                )),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildFloorChips(
      List<int> selected, void Function(List<int>) onChanged) {
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
              color:
                  isSelected ? Colors.white : Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                  color: isSelected ? Colors.white : Colors.white24),
            ),
            child: Text(floorLabel(f),
                style: TextStyle(
                  color: isSelected ? Colors.black : Colors.white54,
                  fontSize: 11,
                )),
          ),
        );
      }).toList(),
    );
  }

  void _showCopyDialog() {
    final targets = <int>{};
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInner) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          title: const Text('コピー先の曜日',
              style: TextStyle(color: Colors.white, fontSize: 14)),
          content: Wrap(
            alignment: WrapAlignment.start,
            spacing: 8,
            runSpacing: 8,
            children: [
              for (int i = 0; i < 7; i++)
                if (i + 1 != _editingWeekday)
                  Builder(builder: (_) {
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
                          color: selected ? Colors.white : Colors.transparent,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                              color: selected ? Colors.white : Colors.white24),
                        ),
                        child: Text(_weekdayLabels[i],
                            style: TextStyle(
                                color: selected ? Colors.black : Colors.white54)),
                      ),
                    );
                  }),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('キャンセル',
                  style: TextStyle(color: Colors.white54)),
            ),
            TextButton(
              onPressed: () {
                final srcDefault =
                    _defaults[_editingWeekday] ?? _SlotConfig();
                final srcSlots =
                    _schedules[_editingWeekday] ?? const <_SlotConfig>[];
                for (final wd in targets) {
                  _defaults[wd] = srcDefault.copy();
                  _schedules[wd] =
                      srcSlots.map((c) => c.copy()).toList();
                }
                Navigator.pop(ctx);
                setState(() {});
              },
              child:
                  const Text('コピー', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Slot config model ─────────────────────────────────────────────────────

class _SlotConfig {
  int startMinute;
  int endMinute;
  String type; // 'fixed' | 'random'
  int floor;
  List<int> floors;
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
      floors: (m['floors'] as List?)
              ?.map((e) => (e as num).toInt())
              .toList() ??
          [1, 2, 3],
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
        'shuffleMode': shuffleMode,
        'repeatDays': repeatDays,
        'repeatHours': repeatHours,
        'repeatMinutes': repeatMinutes,
        'shuffleCount': shuffleCount,
      };

  _SlotConfig copy() => _SlotConfig.fromMap(toMap());
}
