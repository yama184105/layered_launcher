part of 'settings_screen.dart';


// ── Notification Settings Screen ─────────────────────────────────────────────

class _NotificationSettingsScreen extends StatefulWidget {
  final AppService appService;
  final SettingsService settingsService;
  const _NotificationSettingsScreen(
      {required this.appService, required this.settingsService});

  @override
  State<_NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<_NotificationSettingsScreen> {
  List<AppConfig> _apps = [];
  bool _loading = true;
  bool _selectionMode = false;
  final Set<String> _selected = {};
  SettingsService get _ss => widget.settingsService;

  @override
  void initState() {
    super.initState();
    widget.appService.getAllApps().then((apps) {
      if (!mounted) return;
      apps.sort((a, b) => _displayName(a)
          .toLowerCase()
          .compareTo(_displayName(b).toLowerCase()));
      setState(() {
        _apps = apps;
        _loading = false;
      });
    });
  }

  String _displayName(AppConfig app) =>
      (app.customName?.isNotEmpty == true) ? app.customName! : app.appName;

  void _toggleSelection(String pkg) {
    setState(() {
      if (_selected.contains(pkg)) {
        _selected.remove(pkg);
      } else {
        _selected.add(pkg);
      }
      if (_selected.isEmpty) _selectionMode = false;
    });
  }

  Future<void> _applyBulkMode(String mode) async {
    if (_selected.isEmpty) return;
    final pkgs = _selected.toList();
    for (final pkg in pkgs) {
      await _ss.setNotifModeForApp(pkg, mode);
    }
    if (!mounted) return;
    setState(() {
      _selectionMode = false;
      _selected.clear();
    });
  }

  Widget _modeChip(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(left: 4),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.transparent,
          border: Border.all(
              color: selected ? Colors.white : Colors.white24),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(label,
            style: TextStyle(
                color: selected ? Colors.black : Colors.white54,
                fontSize: 11)),
      ),
    );
  }

  Widget _bulkActionBar() {
    final s = S.of(context);
    final allSelected = _selected.length == _apps.length;
    return Container(
      color: const Color(0xFF1A1A1A),
      padding: EdgeInsets.fromLTRB(
          12, 8, 12, 8 + MediaQuery.of(context).padding.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(s.selectedCount(_selected.length),
                  style: const TextStyle(color: Colors.white, fontSize: 13)),
              const Spacer(),
              TextButton(
                onPressed: () => setState(() {
                  if (allSelected) {
                    _selected.clear();
                  } else {
                    _selected
                      ..clear()
                      ..addAll(_apps.map((a) => a.packageName));
                  }
                }),
                child: Text(
                    allSelected ? s.actionDeselectAll : s.actionSelectAll,
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 12)),
              ),
              TextButton(
                onPressed: () => setState(() {
                  _selectionMode = false;
                  _selected.clear();
                }),
                child: Text(s.actionCancel,
                    style: const TextStyle(
                        color: Colors.white54, fontSize: 12)),
              ),
            ],
          ),
          Wrap(
            alignment: WrapAlignment.spaceEvenly,
            spacing: 8,
            children: [
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white24),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 6),
                ),
                onPressed: () => _applyBulkMode('allow'),
                child: Text(s.notificationModeAllow,
                    style: const TextStyle(fontSize: 12)),
              ),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.tealAccent,
                  side: const BorderSide(color: Colors.tealAccent),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 6),
                ),
                onPressed: () => _applyBulkMode('batch'),
                child: Text(s.notificationModeBatch,
                    style: const TextStyle(fontSize: 12)),
              ),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.redAccent,
                  side: const BorderSide(color: Colors.redAccent),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 6),
                ),
                onPressed: () => _applyBulkMode('off'),
                child: Text(s.actionOff,
                    style: const TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: _selectionMode
            ? Text(s.selectedCount(_selected.length),
                style: const TextStyle(color: Colors.white))
            : Text(s.notificationSettingsTitle,
                style: const TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: !_selectionMode
            ? [
                IconButton(
                  icon: const Icon(Icons.checklist,
                      color: Colors.white70, size: 20),
                  tooltip: s.actionSelectAll,
                  onPressed: () => setState(() => _selectionMode = true),
                ),
              ]
            : null,
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Colors.white))
          : Column(
              children: [
                Expanded(
                  child: ListView.builder(
                    itemCount: _apps.length,
                    itemBuilder: (_, i) {
                      final app = _apps[i];
                      final pkg = app.packageName;
                      final mode = _ss.notifModeForApp(pkg);
                      final isChecked = _selected.contains(pkg);
                      return ListTile(
                        onTap: _selectionMode
                            ? () => _toggleSelection(pkg)
                            : null,
                        onLongPress: () {
                          setState(() {
                            _selectionMode = true;
                            _selected.add(pkg);
                          });
                        },
                        selected: isChecked,
                        selectedTileColor: Colors.white.withOpacity(0.05),
                        leading: _selectionMode
                            ? Checkbox(
                                value: isChecked,
                                activeColor: Colors.tealAccent,
                                checkColor: Colors.black,
                                onChanged: (_) => _toggleSelection(pkg),
                              )
                            : null,
                        title: Text(_displayName(app),
                            style: const TextStyle(
                                color: Colors.white, fontSize: 14)),
                        trailing: _selectionMode
                            ? null
                            : Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _modeChip(s.notificationModeAllow,
                                      mode == 'allow', () async {
                                    await _ss.setNotifModeForApp(pkg, 'allow');
                                    setState(() {});
                                  }),
                                  _modeChip(s.notificationModeBatch,
                                      mode == 'batch', () async {
                                    await _ss.setNotifModeForApp(pkg, 'batch');
                                    setState(() {});
                                  }),
                                  _modeChip(s.actionOff, mode == 'off',
                                      () async {
                                    await _ss.setNotifModeForApp(pkg, 'off');
                                    setState(() {});
                                  }),
                                ],
                              ),
                      );
                    },
                  ),
                ),
                if (_selectionMode) _bulkActionBar(),
              ],
            ),
    );
  }
}

// ── App Block Screen ──────────────────────────────────────────────────────────

class _AppBlockScreen extends StatefulWidget {
  final AppService appService;
  final SettingsService settingsService;
  const _AppBlockScreen(
      {required this.appService, required this.settingsService});

  @override
  State<_AppBlockScreen> createState() => _AppBlockScreenState();
}

class _AppBlockScreenState extends State<_AppBlockScreen> {
  List<AppConfig> _apps = [];
  bool _loading = true;
  SettingsService get _ss => widget.settingsService;

  @override
  void initState() {
    super.initState();
    widget.appService.getAllApps().then((apps) {
      if (mounted) setState(() { _apps = apps; _loading = false; });
    });
  }

  String _displayName(AppConfig app) =>
      (app.customName?.isNotEmpty == true) ? app.customName! : app.appName;

  String _blockLabel(BuildContext context, String type) {
    final s = S.of(context);
    switch (type) {
      case 'always': return s.blockTypeAlways;
      case 'time_range': return s.blockTypeTimeRange;
      case 'days': return s.blockTypeDays;
      default: return s.noBlockLabel;
    }
  }

  Future<void> _editBlock(AppConfig app) async {
    final pkg = app.packageName;
    String blockType = _ss.blockTypeForApp(pkg);
    int startMin = _ss.blockStartForApp(pkg);
    int endMin = _ss.blockEndForApp(pkg);
    List<int> days = List.from(_ss.blockDaysForApp(pkg));
    final cooldown = _ss.blockCooldownRemaining(pkg);

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInner) {
          final s = S.of(ctx);
          return AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          title: Text(s.blockSettingsForApp(_displayName(app)),
              style: const TextStyle(color: Colors.white, fontSize: 14)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Block type selector
                Text(s.blockTypeLabel,
                    style: const TextStyle(color: Colors.white54, fontSize: 12)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final t in [
                      ('none', s.blockOptionNone),
                      ('always', s.blockOptionAlways),
                      ('time_range', s.timeRangeLabel),
                      ('days', s.weekdaysLabel),
                    ])
                      GestureDetector(
                        onTap: cooldown != null
                            ? null
                            : () => setInner(() => blockType = t.$1),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 7),
                          decoration: BoxDecoration(
                            color: blockType == t.$1
                                ? Colors.white
                                : Colors.transparent,
                            border: Border.all(
                                color: cooldown != null
                                    ? Colors.white12
                                    : (blockType == t.$1
                                        ? Colors.white
                                        : Colors.white38)),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(t.$2,
                              style: TextStyle(
                                  color: blockType == t.$1
                                      ? Colors.black
                                      : (cooldown != null
                                          ? Colors.white24
                                          : Colors.white70),
                                  fontSize: 12)),
                        ),
                      ),
                  ],
                ),
                // Time range
                if (blockType == 'time_range') ...[
                  const SizedBox(height: 10),
                  Text(s.timeRangeLabel,
                      style: const TextStyle(color: Colors.white54, fontSize: 12)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      DropdownButton<int>(
                        dropdownColor: const Color(0xFF1A1A1A),
                        value: startMin ~/ 60,
                        items: List.generate(24, (h) => DropdownMenuItem(
                          value: h,
                          child: Text('${h.toString().padLeft(2, '0')}:${(startMin % 60).toString().padLeft(2, '0')}',
                              style: const TextStyle(color: Colors.white, fontSize: 13)),
                        )),
                        onChanged: (v) => setInner(() => startMin = (v ?? 0) * 60 + startMin % 60),
                      ),
                      const Text(' 〜 ', style: TextStyle(color: Colors.white54)),
                      DropdownButton<int>(
                        dropdownColor: const Color(0xFF1A1A1A),
                        value: endMin ~/ 60,
                        items: List.generate(24, (h) => DropdownMenuItem(
                          value: h,
                          child: Text('${h.toString().padLeft(2, '0')}:${(endMin % 60).toString().padLeft(2, '0')}',
                              style: const TextStyle(color: Colors.white, fontSize: 13)),
                        )),
                        onChanged: (v) => setInner(() => endMin = (v ?? 0) * 60 + endMin % 60),
                      ),
                    ],
                  ),
                ],
                // Days
                if (blockType == 'days') ...[
                  const SizedBox(height: 10),
                  Text(s.weekdaysLabel,
                      style: const TextStyle(color: Colors.white54, fontSize: 12)),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    children: [
                      for (final d in [
                        (1, s.weekdayMon),
                        (2, s.weekdayTue),
                        (3, s.weekdayWed),
                        (4, s.weekdayThu),
                        (5, s.weekdayFri),
                        (6, s.weekdaySat),
                        (7, s.weekdaySun),
                      ])
                        GestureDetector(
                          onTap: () => setInner(() {
                            if (days.contains(d.$1)) {
                              days.remove(d.$1);
                            } else {
                              days.add(d.$1);
                            }
                          }),
                          child: Container(
                            width: 32,
                            height: 32,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: days.contains(d.$1)
                                  ? Colors.white
                                  : Colors.transparent,
                              border: Border.all(color: Colors.white38),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(d.$2,
                                style: TextStyle(
                                    color: days.contains(d.$1)
                                        ? Colors.black
                                        : Colors.white70,
                                    fontSize: 12)),
                          ),
                        ),
                    ],
                  ),
                ],
                // Cooldown indicator
                if (cooldown != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.amber.withOpacity(0.08),
                      border:
                          Border.all(color: Colors.amber.withOpacity(0.5)),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      s.blockChangeAfter(cooldown.inMinutes, cooldown.inSeconds.remainder(60)),
                      style: const TextStyle(
                          color: Colors.amber, fontSize: 12),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(s.actionCancel,
                  style: const TextStyle(color: Colors.white54)),
            ),
            TextButton(
              onPressed: cooldown != null
                  ? null
                  : () async {
                      if (blockType != _ss.blockTypeForApp(pkg)) {
                        await _ss.requestBlockChange(pkg, blockType);
                      }
                      if (blockType == 'time_range') {
                        await _ss.setBlockStartForApp(pkg, startMin);
                        await _ss.setBlockEndForApp(pkg, endMin);
                      }
                      if (blockType == 'days') {
                        await _ss.setBlockDaysForApp(pkg, days);
                      }
                      if (mounted) setState(() {});
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
              child: Text(s.actionSave,
                  style: const TextStyle(color: Colors.white)),
            ),
          ],
        );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(s.appBlockTitle,
            style: const TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Colors.white))
          : ListView.builder(
              itemCount: _apps.length,
              itemBuilder: (_, i) {
                final app = _apps[i];
                final blockType = _ss.blockTypeForApp(app.packageName);
                final isBlocked = _ss.isAppBlocked(app.packageName);
                return ListTile(
                  title: Text(_displayName(app),
                      style: const TextStyle(
                          color: Colors.white, fontSize: 14)),
                  subtitle: Text(
                    _blockLabel(context, blockType) +
                        (isBlocked ? s.blockedNow : ''),
                    style: TextStyle(
                      color: isBlocked ? Colors.redAccent : Colors.white38,
                      fontSize: 12,
                    ),
                  ),
                  trailing: const Icon(Icons.chevron_right,
                      color: Colors.white38, size: 18),
                  onTap: () => _editBlock(app),
                );
              },
            ),
    );
  }
}

