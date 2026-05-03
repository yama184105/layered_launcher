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

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(s.notificationSettingsTitle,
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
                final mode = _ss.notifModeForApp(app.packageName);
                return ListTile(
                  title: Text(_displayName(app),
                      style: const TextStyle(
                          color: Colors.white, fontSize: 14)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final m in [
                        ('allow', s.notificationModeAllow),
                        ('batch', s.notificationModeBatch),
                        ('off', s.actionOff),
                      ])
                        GestureDetector(
                          onTap: () async {
                            await _ss.setNotifModeForApp(
                                app.packageName, m.$1);
                            setState(() {});
                          },
                          child: Container(
                            margin: const EdgeInsets.only(left: 4),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 5),
                            decoration: BoxDecoration(
                              color: mode == m.$1
                                  ? Colors.white
                                  : Colors.transparent,
                              border: Border.all(
                                  color: mode == m.$1
                                      ? Colors.white
                                      : Colors.white24),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(m.$2,
                                style: TextStyle(
                                    color: mode == m.$1
                                        ? Colors.black
                                        : Colors.white54,
                                    fontSize: 11)),
                          ),
                        ),
                    ],
                  ),
                );
              },
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

