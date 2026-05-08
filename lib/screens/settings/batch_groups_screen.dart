part of 'settings_screen.dart';

// ── Batch Groups: list screen ────────────────────────────────────────────────

class _BatchGroupsScreen extends StatefulWidget {
  final AppService appService;
  final SettingsService settingsService;
  const _BatchGroupsScreen({
    required this.appService,
    required this.settingsService,
  });
  @override
  State<_BatchGroupsScreen> createState() => _BatchGroupsScreenState();
}

class _BatchGroupsScreenState extends State<_BatchGroupsScreen> {
  List<AppConfig> _apps = [];
  bool _loading = true;
  SettingsService get _ss => widget.settingsService;

  @override
  void initState() {
    super.initState();
    widget.appService.getAllApps().then((apps) {
      if (!mounted) return;
      setState(() {
        _apps = apps;
        _loading = false;
      });
    });
  }

  String _displayName(String pkg) {
    final app = _apps.firstWhere(
      (a) => a.packageName == pkg,
      orElse: () => AppConfig(packageName: pkg, appName: pkg, floor: 1),
    );
    return (app.customName?.isNotEmpty == true)
        ? app.customName!
        : app.appName;
  }

  Future<void> _editGroup(Map<String, dynamic>? existing) async {
    final result = await Navigator.push<_BatchGroupResult>(
      context,
      MaterialPageRoute(
        builder: (_) => _BatchGroupEditScreen(
          appService: widget.appService,
          settingsService: _ss,
          existing: existing,
        ),
      ),
    );
    if (result == null || !mounted) return;
    final groups = _ss.batchGroups;
    if (result.delete) {
      groups.removeWhere((g) => g['id'] == result.group['id']);
    } else {
      final idx = groups.indexWhere((g) => g['id'] == result.group['id']);
      if (idx >= 0) {
        groups[idx] = result.group;
      } else {
        groups.add(result.group);
      }
    }
    await _ss.setBatchGroups(groups);
    setState(() {});
  }

  String _scheduleSummary(BuildContext context, Map<String, dynamic> g) {
    final s = S.of(context);
    final type = g['scheduleType'] as String? ?? 'interval';
    final appCount =
        ((g['apps'] as List?) ?? const []).length;
    switch (type) {
      case 'interval':
        final mins = (g['intervalMinutes'] as num?)?.toInt() ?? 240;
        if (mins % 60 == 0) {
          return s.batchGroupSummaryHourly(mins ~/ 60, appCount);
        }
        return s.batchGroupSummaryInterval(mins, appCount);
      case 'fixed':
        final times = ((g['times'] as List?) ?? const []).length;
        return s.batchGroupSummaryFixed(times, appCount);
      case 'dailyOnce':
        final t = g['time'] as Map?;
        if (t == null) return s.batchGroupNoTimes;
        final h = (t['h'] as num?)?.toInt() ?? 7;
        final m = (t['m'] as num?)?.toInt() ?? 0;
        final label = '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
        return s.batchGroupSummaryDaily(label, appCount);
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final groups = _ss.batchGroups;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(s.batchGroupsTitle,
            style: const TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Text(s.batchGroupsHelp,
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 12)),
                ),
                const Divider(color: Colors.white12, height: 1),
                if (groups.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
                    child: Text(s.batchGroupNoGroups,
                        style: const TextStyle(
                            color: Colors.white38, fontSize: 13)),
                  ),
                for (final g in groups)
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 4),
                    title: Text(
                      (g['name'] as String?)?.isNotEmpty == true
                          ? g['name'] as String
                          : s.batchGroupNewName,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 14),
                    ),
                    subtitle: Text(_scheduleSummary(context, g),
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 12)),
                    trailing: const Icon(Icons.chevron_right,
                        color: Colors.white24, size: 18),
                    onTap: () => _editGroup(g),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white70,
                      side: const BorderSide(color: Colors.white24),
                    ),
                    icon: const Icon(Icons.add, size: 16),
                    label: Text(s.batchGroupAdd,
                        style: const TextStyle(fontSize: 13)),
                    onPressed: () => _editGroup(null),
                  ),
                ),
              ],
            ),
    );
  }
}

// Helper return type — group object + delete flag.
class _BatchGroupResult {
  final Map<String, dynamic> group;
  final bool delete;
  const _BatchGroupResult(this.group, {this.delete = false});
}

// ── Batch Group: edit screen ─────────────────────────────────────────────────

class _BatchGroupEditScreen extends StatefulWidget {
  final AppService appService;
  final SettingsService settingsService;
  final Map<String, dynamic>? existing;
  const _BatchGroupEditScreen({
    required this.appService,
    required this.settingsService,
    required this.existing,
  });
  @override
  State<_BatchGroupEditScreen> createState() => _BatchGroupEditScreenState();
}

class _BatchGroupEditScreenState extends State<_BatchGroupEditScreen> {
  late TextEditingController _nameCtrl;
  late String _id;
  late List<String> _apps;
  late String _scheduleType; // 'interval' | 'fixed' | 'dailyOnce'
  late int _intervalMinutes;
  late List<Map<String, int>> _times; // for 'fixed'
  late Map<String, int> _dailyTime; // for 'dailyOnce'
  late Set<int> _weekdays;

  List<AppConfig> _allApps = [];
  bool _loading = true;
  SettingsService get _ss => widget.settingsService;

  @override
  void initState() {
    super.initState();
    final src = widget.existing;
    _id = (src?['id'] as String?) ?? GestureSettings.newBatchGroupId();
    _nameCtrl = TextEditingController(
        text: (src?['name'] as String?) ?? '');
    _apps = ((src?['apps'] as List?) ?? const [])
        .map((e) => e.toString())
        .toList();
    _scheduleType = (src?['scheduleType'] as String?) ?? 'interval';
    _intervalMinutes = (src?['intervalMinutes'] as num?)?.toInt() ?? 240;
    _times = ((src?['times'] as List?) ?? const [])
        .map((e) => {
              'h': (e['h'] as num).toInt(),
              'm': (e['m'] as num).toInt(),
            })
        .toList();
    final dailyT = src?['time'] as Map?;
    _dailyTime = dailyT != null
        ? {
            'h': (dailyT['h'] as num).toInt(),
            'm': (dailyT['m'] as num).toInt(),
          }
        : {'h': 7, 'm': 0};
    _weekdays = ((src?['weekdays'] as List?) ?? const [1, 2, 3, 4, 5, 6, 7])
        .cast<num>()
        .map((e) => e.toInt())
        .toSet();
    widget.appService.getAllApps().then((apps) {
      if (!mounted) return;
      setState(() {
        _allApps = apps;
        _loading = false;
      });
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  String _displayName(AppConfig app) =>
      (app.customName?.isNotEmpty == true) ? app.customName! : app.appName;

  String _fmtTime(int h, int m) =>
      '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';

  Future<void> _pickApps() async {
    final selected = Set<String>.from(_apps);
    // Only batch-mode apps are eligible candidates.
    final batchApps = _ss.batchApps;
    final candidates = _allApps
        .where((a) => batchApps.contains(a.packageName))
        .toList()
      ..sort((a, b) => _displayName(a)
          .toLowerCase()
          .compareTo(_displayName(b).toLowerCase()));

    final result = await showDialog<List<String>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInner) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          title: Text(S.of(ctx).batchGroupApps,
              style: const TextStyle(color: Colors.white, fontSize: 14)),
          content: SizedBox(
            width: double.maxFinite,
            height: 400,
            child: candidates.isEmpty
                ? Center(
                    child: Text(S.of(ctx).noEmergencyRegistered,
                        style: const TextStyle(color: Colors.white38)))
                : ListView.builder(
                    itemCount: candidates.length,
                    itemBuilder: (_, i) {
                      final app = candidates[i];
                      final checked = selected.contains(app.packageName);
                      return CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        activeColor: Colors.tealAccent,
                        checkColor: Colors.black,
                        title: Text(_displayName(app),
                            style: const TextStyle(
                                color: Colors.white, fontSize: 13)),
                        value: checked,
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
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(S.of(ctx).actionCancel,
                  style: const TextStyle(color: Colors.white54)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, selected.toList()),
              child: Text(S.of(ctx).actionSave,
                  style: const TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
    if (result != null) setState(() => _apps = result);
  }

  Future<void> _pickTime({Map<String, int>? initial,
      required ValueChanged<Map<String, int>> onPicked}) async {
    final init = TimeOfDay(
      hour: initial?['h'] ?? 7,
      minute: initial?['m'] ?? 0,
    );
    final picked = await showTimePicker(
      context: context,
      initialTime: init,
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
      onPicked({'h': picked.hour, 'm': picked.minute});
    }
  }

  Future<void> _pickInterval() async {
    final s = S.of(context);
    final ctrl =
        TextEditingController(text: _intervalMinutes.toString());
    int v = _intervalMinutes;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: Text(s.batchGroupScheduleInterval,
            style: const TextStyle(color: Colors.white, fontSize: 14)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Quick presets.
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final mins in const [30, 60, 120, 240, 360, 480])
                  GestureDetector(
                    onTap: () {
                      ctrl.text = mins.toString();
                      v = mins;
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.white38),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        mins % 60 == 0
                            ? s.batchGroupHourlyLabel(mins ~/ 60)
                            : s.batchGroupIntervalLabel(mins),
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 11),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              style:
                  const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                filled: true,
                fillColor: Colors.white.withOpacity(0.07),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide.none,
                ),
                suffixText: '分',
                suffixStyle:
                    const TextStyle(color: Colors.white38, fontSize: 12),
              ),
              onChanged: (s) => v = int.tryParse(s) ?? v,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(s.actionCancel,
                style: const TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () {
              v = int.tryParse(ctrl.text) ?? v;
              if (v < 1) v = 1;
              setState(() => _intervalMinutes = v);
              Navigator.pop(ctx);
            },
            child: Text(s.actionSave,
                style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _save() {
    // For 'dailyOnce' mode we always want a single time; we already keep
    // _dailyTime maintained, no extra normalization needed.
    final group = <String, dynamic>{
      'id': _id,
      'name': _nameCtrl.text.trim().isEmpty
          ? S.of(context).batchGroupNewName
          : _nameCtrl.text.trim(),
      'apps': _apps,
      'scheduleType': _scheduleType,
      'intervalMinutes': _intervalMinutes,
      'times': _times,
      'time': _dailyTime,
      'weekdays': _weekdays.toList()..sort(),
      'lastFireAt':
          (widget.existing?['lastFireAt'] as num?)?.toInt() ?? 0,
    };
    Navigator.pop(context, _BatchGroupResult(group));
  }

  Future<void> _delete() async {
    final s = S.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        content: Text(s.batchGroupDeleteConfirm(_nameCtrl.text),
            style: const TextStyle(color: Colors.white70, fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(s.actionCancel,
                style: const TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(s.actionDelete,
                style: const TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    Navigator.pop(
      context,
      _BatchGroupResult(
        widget.existing ?? {'id': _id},
        delete: true,
      ),
    );
  }

  Widget _typeChip(String label, String value) {
    final sel = _scheduleType == value;
    return GestureDetector(
      onTap: () => setState(() => _scheduleType = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: sel ? Colors.white : Colors.transparent,
          border: Border.all(color: sel ? Colors.white : Colors.white38),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(label,
            style: TextStyle(
                color: sel ? Colors.black : Colors.white70, fontSize: 12)),
      ),
    );
  }

  Widget _weekdayChip(int wd, String label) {
    final sel = _weekdays.contains(wd);
    return GestureDetector(
      onTap: () => setState(() {
        if (sel) {
          // Don't let the user empty the set — at least one day must be on.
          if (_weekdays.length > 1) _weekdays.remove(wd);
        } else {
          _weekdays.add(wd);
        }
      }),
      child: Container(
        width: 36,
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: sel ? Colors.tealAccent : Colors.transparent,
          border: Border.all(color: sel ? Colors.tealAccent : Colors.white38),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(label,
            style: TextStyle(
                color: sel ? Colors.black : Colors.white70, fontSize: 11)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final isEdit = widget.existing != null;
    final wd = [
      (1, s.weekdayMon),
      (2, s.weekdayTue),
      (3, s.weekdayWed),
      (4, s.weekdayThu),
      (5, s.weekdayFri),
      (6, s.weekdaySat),
      (7, s.weekdaySun),
    ];

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(_nameCtrl.text.isNotEmpty
            ? _nameCtrl.text
            : s.batchGroupNewName,
            style: const TextStyle(color: Colors.white, fontSize: 16)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (isEdit)
            IconButton(
              icon: const Icon(Icons.delete_outline,
                  color: Colors.redAccent),
              onPressed: _delete,
            ),
          TextButton(
            onPressed: _save,
            child: Text(s.actionSave,
                style: const TextStyle(color: Colors.tealAccent)),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                // Name
                Text(s.batchGroupName,
                    style:
                        const TextStyle(color: Colors.white54, fontSize: 12)),
                const SizedBox(height: 4),
                TextField(
                  controller: _nameCtrl,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: s.batchGroupNameHint,
                    hintStyle:
                        const TextStyle(color: Colors.white38),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.07),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 16),

                // Apps
                Row(
                  children: [
                    Expanded(
                      child: Text(s.batchGroupApps,
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 12)),
                    ),
                    Text(s.batchGroupAppsCount(_apps.length),
                        style: const TextStyle(
                            color: Colors.white38, fontSize: 11)),
                  ],
                ),
                const SizedBox(height: 4),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: const BorderSide(color: Colors.white24),
                  ),
                  icon: const Icon(Icons.apps, size: 14),
                  label: Text(
                    _apps.isEmpty
                        ? s.batchGroupNoApps
                        : _apps
                            .take(3)
                            .map((p) => _displayName(_allAppConfigForPkg(p)))
                            .join(', ') +
                            (_apps.length > 3 ? '...' : ''),
                    style: const TextStyle(fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                  onPressed: _pickApps,
                ),
                const SizedBox(height: 16),

                // Schedule type
                Text(s.batchGroupSchedule,
                    style: const TextStyle(color: Colors.white54, fontSize: 12)),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _typeChip(s.batchGroupScheduleInterval, 'interval'),
                    _typeChip(s.batchGroupScheduleFixed, 'fixed'),
                    _typeChip(s.batchGroupScheduleDailyOnce, 'dailyOnce'),
                  ],
                ),
                const SizedBox(height: 12),

                // Schedule details
                if (_scheduleType == 'interval')
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white70,
                      side: const BorderSide(color: Colors.white24),
                    ),
                    onPressed: _pickInterval,
                    child: Text(
                      _intervalMinutes % 60 == 0
                          ? s.batchGroupHourlyLabel(_intervalMinutes ~/ 60)
                          : s.batchGroupIntervalLabel(_intervalMinutes),
                      style: const TextStyle(fontSize: 12),
                    ),
                  )
                else if (_scheduleType == 'fixed') ...[
                  Text(s.batchGroupTimesLabel,
                      style:
                          const TextStyle(color: Colors.white54, fontSize: 12)),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (int i = 0; i < _times.length; i++)
                        _TimeChip(
                          label: _fmtTime(_times[i]['h']!, _times[i]['m']!),
                          onTap: () => _pickTime(
                            initial: _times[i],
                            onPicked: (t) =>
                                setState(() => _times[i] = t),
                          ),
                          onDelete: () =>
                              setState(() => _times.removeAt(i)),
                        ),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white70,
                          side: const BorderSide(color: Colors.white24),
                        ),
                        icon: const Icon(Icons.add, size: 14),
                        label: Text(s.batchGroupAddTime,
                            style: const TextStyle(fontSize: 12)),
                        onPressed: () => _pickTime(
                          initial: const {'h': 12, 'm': 0},
                          onPicked: (t) => setState(() => _times.add(t)),
                        ),
                      ),
                    ],
                  ),
                ] else if (_scheduleType == 'dailyOnce') ...[
                  Text(s.batchGroupTime,
                      style:
                          const TextStyle(color: Colors.white54, fontSize: 12)),
                  const SizedBox(height: 4),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white70,
                      side: const BorderSide(color: Colors.white24),
                    ),
                    onPressed: () => _pickTime(
                      initial: _dailyTime,
                      onPicked: (t) =>
                          setState(() => _dailyTime = t),
                    ),
                    child: Text(
                      _fmtTime(_dailyTime['h']!, _dailyTime['m']!),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],

                const SizedBox(height: 20),

                // Weekdays
                Row(
                  children: [
                    Expanded(
                      child: Text(s.batchGroupWeekdays,
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 12)),
                    ),
                    if (_weekdays.length == 7)
                      Text(s.batchGroupEveryDay,
                          style: const TextStyle(
                              color: Colors.white38, fontSize: 11)),
                  ],
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final p in wd) _weekdayChip(p.$1, p.$2),
                  ],
                ),
              ],
            ),
    );
  }

  AppConfig _allAppConfigForPkg(String pkg) => _allApps.firstWhere(
        (a) => a.packageName == pkg,
        orElse: () => AppConfig(packageName: pkg, appName: pkg, floor: 1),
      );
}

class _TimeChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  const _TimeChip({
    required this.label,
    required this.onTap,
    required this.onDelete,
  });
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.tealAccent.withOpacity(0.6)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 6),
              child: Text(label,
                  style: const TextStyle(
                      color: Colors.tealAccent, fontSize: 12)),
            ),
          ),
          GestureDetector(
            onTap: onDelete,
            child: const Padding(
              padding:
                  EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              child: Icon(Icons.close,
                  color: Colors.redAccent, size: 14),
            ),
          ),
        ],
      ),
    );
  }
}
