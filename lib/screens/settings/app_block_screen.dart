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
  final NativeService _native = NativeService();
  bool _listenerEnabled = false;
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
    _refreshListenerState();
  }

  Future<void> _refreshListenerState() async {
    final v = await _native.isNotificationServiceEnabled();
    if (!mounted) return;
    setState(() => _listenerEnabled = v);
  }

  /// Asks the user to grant notification listener access. Returns whether
  /// the listener is now enabled (false if user dismissed the dialog or
  /// returned without enabling).
  Future<bool> _ensureListenerOrPrompt() async {
    if (_listenerEnabled) return true;
    final ok = await _native.isNotificationServiceEnabled();
    if (ok) {
      if (mounted) setState(() => _listenerEnabled = true);
      return true;
    }
    if (!mounted) return false;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: Text(S.of(ctx).notificationAccessTitle,
            style: const TextStyle(color: Colors.white)),
        content: Text(S.of(ctx).notificationAccessMessage,
            style:
                const TextStyle(color: Colors.white70, fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(S.of(ctx).actionLater,
                style: const TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(S.of(ctx).openSettings,
                style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (go == true) {
      await _native.openNotificationAccessSettings();
      // We can't await the user, just refresh next time the screen
      // becomes visible — for now, optimistically mark dirty so the
      // banner re-checks.
      Future.delayed(const Duration(seconds: 1), _refreshListenerState);
    }
    return false;
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

  Future<void> _setMode(String pkg, String mode) async {
    await _ss.setNotifModeForApp(pkg, mode);
    if (mode == 'batch' || mode == 'off') {
      // Don't block the UI — fire-and-check.
      unawaited(_ensureListenerOrPrompt());
    }
    if (mounted) setState(() {});
  }

  Future<void> _applyBulkMode(String mode) async {
    if (_selected.isEmpty) return;
    final pkgs = _selected.toList();
    for (final pkg in pkgs) {
      await _ss.setNotifModeForApp(pkg, mode);
    }
    if (mode == 'batch' || mode == 'off') {
      unawaited(_ensureListenerOrPrompt());
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

  /// Persistent banner that explains the notification-access requirement.
  /// Visible when the listener is disabled — without it neither OFF nor
  /// batch capture can do anything.
  Widget _accessBanner() {
    final s = S.of(context);
    return Material(
      color: Colors.amber.withOpacity(0.10),
      child: InkWell(
        onTap: () async {
          await _native.openNotificationAccessSettings();
          Future.delayed(const Duration(seconds: 1), _refreshListenerState);
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
          child: Row(
            children: [
              const Icon(Icons.warning_amber_rounded,
                  color: Colors.amber, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(s.notificationAccessMessage,
                    style: const TextStyle(
                        color: Colors.amber, fontSize: 12)),
              ),
              const SizedBox(width: 6),
              Text(s.openSettings,
                  style: const TextStyle(
                      color: Colors.amber,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }

  /// Header strip that lets the user pick the default mode applied to apps
  /// without an explicit per-app override.
  Widget _defaultModeHeader() {
    final s = S.of(context);
    final current = _ss.defaultNotifMode;
    Widget chip(String value, String label, Color color) {
      final selected = current == value;
      return GestureDetector(
        onTap: () async {
          await _ss.setDefaultNotifMode(value);
          if (mounted) setState(() {});
        },
        child: Container(
          margin: const EdgeInsets.only(left: 4),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: selected ? color.withOpacity(0.20) : Colors.transparent,
            border: Border.all(
                color: selected ? color : Colors.white24),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(label,
              style: TextStyle(
                  color: selected ? color : Colors.white54,
                  fontSize: 11)),
        ),
      );
    }

    return Container(
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.white12),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.defaultNotifModeLabel,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 13)),
                const SizedBox(height: 2),
                Text(s.defaultNotifModeHint,
                    style: const TextStyle(
                        color: Colors.white38, fontSize: 11)),
              ],
            ),
          ),
          chip('allow', s.notificationModeAllow, Colors.white),
          chip('batch', s.notificationModeBatch, Colors.tealAccent),
          chip('off', s.actionOff, Colors.redAccent),
        ],
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
                if (!_listenerEnabled) _accessBanner(),
                _defaultModeHeader(),
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
                                      mode == 'allow',
                                      () => _setMode(pkg, 'allow')),
                                  _modeChip(s.notificationModeBatch,
                                      mode == 'batch',
                                      () => _setMode(pkg, 'batch')),
                                  _modeChip(s.actionOff, mode == 'off',
                                      () => _setMode(pkg, 'off')),
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


// ── Blocked History Screen ──────────────────────────────────────────────────
// Shows the list of notifications that were intercepted and dismissed
// because their source app is in OFF mode. Newest first. Persistent —
// survives app restarts (stored in SharedPreferences on the native side,
// capped to MAX_BLOCKED_HISTORY entries).

class _BlockedHistoryScreen extends StatefulWidget {
  final AppService appService;
  const _BlockedHistoryScreen({required this.appService});
  @override
  State<_BlockedHistoryScreen> createState() => _BlockedHistoryScreenState();
}

class _BlockedHistoryScreenState extends State<_BlockedHistoryScreen> {
  final NativeService _native = NativeService();
  List<Map<String, dynamic>> _history = [];
  Map<String, String> _appLabels = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final hist = await _native.getBlockedHistory();
    final apps = await widget.appService.getAllApps();
    final labels = <String, String>{};
    for (final a in apps) {
      labels[a.packageName] =
          (a.customName?.isNotEmpty == true) ? a.customName! : a.appName;
    }
    if (!mounted) return;
    setState(() {
      _history = hist.reversed.toList(); // newest first
      _appLabels = labels;
      _loading = false;
    });
  }

  Future<void> _clear() async {
    final s = S.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        content: Text(s.blockedHistoryClearConfirm,
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
    if (ok != true || !mounted) return;
    await _native.clearBlockedHistory();
    if (!mounted) return;
    setState(() => _history = []);
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(s.blockedHistoryTitle,
            style: const TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (_history.isNotEmpty)
            TextButton(
              onPressed: _clear,
              child: Text(s.blockedHistoryClear,
                  style: const TextStyle(
                      color: Colors.redAccent, fontSize: 12)),
            ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Colors.white))
          : _history.isEmpty
              ? Center(
                  child: Text(s.blockedHistoryEmpty,
                      style: const TextStyle(
                          color: Colors.white38, fontSize: 13)))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    itemCount: _history.length + 1,
                    separatorBuilder: (_, __) => const Divider(
                        height: 1,
                        color: Colors.white12,
                        indent: 16,
                        endIndent: 16),
                    itemBuilder: (_, i) {
                      if (i == 0) {
                        return Padding(
                          padding:
                              const EdgeInsets.fromLTRB(16, 12, 16, 8),
                          child: Text(
                              s.blockedHistoryCount(_history.length),
                              style: const TextStyle(
                                  color: Colors.white54, fontSize: 12)),
                        );
                      }
                      final e = _history[i - 1];
                      final pkg = e['pkg'] as String? ?? '';
                      final label = _appLabels[pkg] ?? pkg;
                      final title = (e['title'] as String?) ?? '';
                      final text = (e['text'] as String?) ?? '';
                      final blockedAt = (e['blockedAt'] as num?)?.toInt() ?? 0;
                      final rel = formatLastUsedRelative(context, blockedAt);
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 4),
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                title.isNotEmpty ? title : label,
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 14),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (rel != null)
                              Padding(
                                padding: const EdgeInsets.only(left: 8),
                                child: Text(rel,
                                    style: const TextStyle(
                                        color: Colors.white38,
                                        fontSize: 11)),
                              ),
                          ],
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (text.isNotEmpty)
                              Text(text,
                                  style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 12),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 2),
                            Text(label,
                                style: const TextStyle(
                                    color: Colors.white38, fontSize: 11)),
                          ],
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}

// ── Batch Pending Screen ────────────────────────────────────────────────────
// Shows what's currently queued for each batch group along with the next
// scheduled delivery time. Useful for verifying that batch capture is
// actually intercepting the apps the user expects, and for previewing
// what will be re-posted at the next fire.

class _BatchPendingScreen extends StatefulWidget {
  final AppService appService;
  const _BatchPendingScreen({required this.appService});
  @override
  State<_BatchPendingScreen> createState() => _BatchPendingScreenState();
}

class _BatchPendingScreenState extends State<_BatchPendingScreen> {
  final NativeService _native = NativeService();
  List<Map<String, dynamic>> _queues = [];
  Map<String, String> _appLabels = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final qs = await _native.getBatchQueues();
    final apps = await widget.appService.getAllApps();
    final labels = <String, String>{};
    for (final a in apps) {
      labels[a.packageName] =
          (a.customName?.isNotEmpty == true) ? a.customName! : a.appName;
    }
    if (!mounted) return;
    setState(() {
      _queues = qs;
      _appLabels = labels;
      _loading = false;
    });
  }

  String _fmtNextFire(int? ms, S s) {
    if (ms == null || ms <= 0) return s.batchPendingNoFireScheduled;
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dtDay = DateTime(dt.year, dt.month, dt.day);
    final hm =
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    if (dtDay == today) return s.batchPendingNextFire(hm);
    final tomorrow = today.add(const Duration(days: 1));
    if (dtDay == tomorrow) return s.batchPendingNextFire('${hm} (+1d)');
    return s.batchPendingNextFire('${dt.month}/${dt.day} $hm');
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(s.batchPendingTitle,
            style: const TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white70),
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Colors.white))
          : _queues.isEmpty
              ? Center(
                  child: Text(s.batchPendingNoGroups,
                      style: const TextStyle(
                          color: Colors.white38, fontSize: 13)))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    children: [
                      for (final g in _queues) _groupSection(s, g),
                    ],
                  ),
                ),
    );
  }

  Widget _groupSection(S s, Map<String, dynamic> g) {
    final name = (g['name'] as String?)?.isNotEmpty == true
        ? g['name'] as String
        : s.batchGroupNewName;
    final items = (g['items'] as List?)?.cast<Map<String, dynamic>>() ??
        const <Map<String, dynamic>>[];
    final nextFireMs = (g['nextFireMs'] as num?)?.toInt();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          color: Colors.white.withOpacity(0.04),
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Row(
            children: [
              Expanded(
                child: Text(name,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w500)),
              ),
              Text(s.batchPendingItems(items.length),
                  style: const TextStyle(color: Colors.white54, fontSize: 12)),
              const SizedBox(width: 8),
              Text(_fmtNextFire(nextFireMs, s),
                  style:
                      const TextStyle(color: Colors.tealAccent, fontSize: 11)),
            ],
          ),
        ),
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
            child: Text(s.batchPendingGroupEmpty,
                style: const TextStyle(color: Colors.white24, fontSize: 12)),
          )
        else
          for (final it in items.reversed) _itemRow(it),
        const Divider(color: Colors.white12, height: 1),
      ],
    );
  }

  Widget _itemRow(Map<String, dynamic> it) {
    final pkg = it['pkg'] as String? ?? '';
    final title = it['title'] as String? ?? '';
    final text = it['text'] as String? ?? '';
    final postedAt = (it['postedAt'] as num?)?.toInt() ?? 0;
    final label = _appLabels[pkg] ?? pkg;
    final rel = formatLastUsedRelative(context, postedAt);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(title.isNotEmpty ? title : label,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
              if (rel != null)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Text(rel,
                      style: const TextStyle(
                          color: Colors.white38, fontSize: 11)),
                ),
            ],
          ),
          if (text.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(text,
                  style: const TextStyle(
                      color: Colors.white70, fontSize: 12),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(label,
                style: const TextStyle(color: Colors.white38, fontSize: 11)),
          ),
        ],
      ),
    );
  }
}
