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
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('通知制限',
            style: TextStyle(color: Colors.white)),
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
                        ('allow', '許可'),
                        ('batch', 'バッチ'),
                        ('off', 'OFF'),
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

  String _blockLabel(String type) {
    switch (type) {
      case 'always': return '常時ブロック';
      case 'time_range': return '時間帯';
      case 'days': return '曜日';
      default: return 'なし';
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
        builder: (ctx, setInner) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          title: Text('${_displayName(app)} のブロック設定',
              style: const TextStyle(color: Colors.white, fontSize: 14)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Block type selector
                const Text('ブロック種類',
                    style: TextStyle(color: Colors.white54, fontSize: 12)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final t in [
                      ('none', 'なし'),
                      ('always', '常時'),
                      ('time_range', '時間帯'),
                      ('days', '曜日'),
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
                  const Text('時間帯',
                      style: TextStyle(color: Colors.white54, fontSize: 12)),
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
                  const Text('曜日',
                      style: TextStyle(color: Colors.white54, fontSize: 12)),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    children: [
                      for (final d in [(1, '月'), (2, '火'), (3, '水'), (4, '木'), (5, '金'), (6, '土'), (7, '日')])
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
                      '変更は ${cooldown.inMinutes}分${cooldown.inSeconds.remainder(60)}秒後に反映されます',
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
              child: const Text('キャンセル',
                  style: TextStyle(color: Colors.white54)),
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
              child: const Text('保存',
                  style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('アプリブロック',
            style: TextStyle(color: Colors.white)),
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
                    _blockLabel(blockType) +
                        (isBlocked ? '  ●ブロック中' : ''),
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

