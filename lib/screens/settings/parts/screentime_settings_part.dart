part of '../settings_screen.dart';

extension ScreenTimeSettingsMethods on _SettingsScreenState {
  List<Widget> _screenTimeSettingRows() {
    final s = S.of(context);
    final ss = _ss;
    return [
      _settingRow(s.mindfulDelaySettings, '', () {
        Navigator.push(context, MaterialPageRoute(
          builder: (_) => _MindfulDelaySettingsScreen(appService: _as, settingsService: ss),
        )).then((_) => _load());
      }),
      _rowDivider,
      _expandableRow(
        key: 'screentime_notif',
        title: s.notificationSection,
        summary: s.batchGroupCount(ss.batchGroups.length),
        children: [
          _settingRow(s.notificationLimit, '', () {
            Navigator.push(context, MaterialPageRoute(
              builder: (_) => _NotificationSettingsScreen(
                  appService: _as, settingsService: ss),
            ));
          }),
          _rowDivider,
          _settingRow(s.batchGroupsTitle,
              s.batchGroupCount(ss.batchGroups.length), () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => _BatchGroupsScreen(
                    appService: _as, settingsService: ss),
              ),
            );
            setState(() {});
          }),
          _rowDivider,
          _settingRow(s.batchPendingTitle, '', () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => _BatchPendingScreen(appService: _as),
              ),
            );
            if (mounted) setState(() {});
          }),
          _rowDivider,
          _settingRow(s.blockedHistoryTitle, '', () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => _BlockedHistoryScreen(appService: _as),
              ),
            );
            if (mounted) setState(() {});
          }),
          _rowDivider,
          _quickLauncherToggleRow(),
        ],
      ),
      _rowDivider,
      _settingRow(s.appBlock, '', () {
        Navigator.push(context, MaterialPageRoute(
          builder: (_) => _AppBlockScreen(appService: _as, settingsService: ss),
        ));
      }),
      _rowDivider,
      _settingRow(
        s.lastUsedDisplay,
        ss.lastUsedDisplayApps.isEmpty
            ? s.notSet
            : s.displayedInAppsCount(ss.lastUsedDisplayApps.length),
        () async {
          await showLastUsedDisplayPicker();
        },
      ),
    ];
  }

  /// Persistent quick-launcher notification toggle + source selector.
  /// Posts/cancels the kotlin-side notification on flip. The source picker
  /// lets the user choose what populates the expanded view (favorites vs.
  /// floor 1 vs. ...).
  Widget _quickLauncherToggleRow() {
    final ss = _ss;
    final enabled = ss.quickLauncherEnabled;
    final prominent = ss.quickLauncherProminent;
    final showDividers = ss.quickLauncherShowDividers;
    final source = ss.quickLauncherSource;
    final customCount = ss.quickLauncherCustomApps.length;
    final sourceLabel = switch (source) {
      'floor1' => '1F のアプリ',
      'custom' => 'カスタム ($customCount)',
      _ => 'お気に入り',
    };

    Future<void> resync({
      required bool enabled,
      required bool prominent,
      required bool showDividers,
      required String source,
    }) async {
      final apps = await _as.resolveQuickLauncherApps(
        source,
        customPackages: ss.quickLauncherCustomApps,
      );
      await ss.onQuickLauncherChanged
          ?.call(enabled, prominent, showDividers, apps);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          contentPadding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
          title: const Text(
            '通知シェードからクイック起動',
            style: TextStyle(color: Colors.white, fontSize: 14),
          ),
          subtitle: const Text(
            '常駐通知を展開してアプリを起動',
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
          activeColor: Colors.tealAccent,
          value: enabled,
          onChanged: (v) async {
            await ss.setQuickLauncherEnabled(v);
            await resync(
                enabled: v,
                prominent: prominent,
                showDividers: showDividers,
                source: source);
            if (mounted) setState(() {});
          },
        ),
        if (enabled) ...[
          Padding(
            padding: const EdgeInsets.only(left: 16, right: 16, bottom: 4),
            child: Row(
              children: [
                const Text(
                  '表示するアプリ:',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () async {
                    final choice = await showDialog<String>(
                      context: context,
                      builder: (ctx) => SimpleDialog(
                        backgroundColor: const Color(0xFF1A1A1A),
                        title: const Text(
                          '表示するアプリ',
                          style: TextStyle(color: Colors.white, fontSize: 14),
                        ),
                        children: [
                          SimpleDialogOption(
                            onPressed: () => Navigator.pop(ctx, 'favorites'),
                            child: const Text(
                              'お気に入り',
                              style: TextStyle(color: Colors.white),
                            ),
                          ),
                          SimpleDialogOption(
                            onPressed: () => Navigator.pop(ctx, 'floor1'),
                            child: const Text(
                              '1F のアプリ',
                              style: TextStyle(color: Colors.white),
                            ),
                          ),
                          SimpleDialogOption(
                            onPressed: () => Navigator.pop(ctx, 'custom'),
                            child: const Text(
                              'カスタム (一覧から選ぶ)',
                              style: TextStyle(color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                    );
                    if (choice != null && choice != source) {
                      await ss.setQuickLauncherSource(choice);
                      await resync(
                          enabled: enabled,
                          prominent: prominent,
                          showDividers: showDividers,
                          source: choice);
                      if (mounted) setState(() {});
                    }
                  },
                  child: Text(
                    sourceLabel,
                    style: const TextStyle(
                      color: Colors.tealAccent,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (source == 'custom')
            Padding(
              padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
              child: TextButton(
                style: TextButton.styleFrom(
                  backgroundColor: Colors.white.withOpacity(0.05),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => _QuickLauncherAppPickerScreen(
                        appService: _as,
                        settingsService: ss,
                      ),
                    ),
                  );
                  await resync(
                      enabled: enabled,
                      prominent: prominent,
                      showDividers: showDividers,
                      source: 'custom');
                  if (mounted) setState(() {});
                },
                child: const Text(
                  'カスタムアプリ一覧を編集',
                  style: TextStyle(color: Colors.tealAccent, fontSize: 13),
                ),
              ),
            ),
          SwitchListTile(
            contentPadding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            title: const Text(
              'アプリ間に区切り線を表示',
              style: TextStyle(color: Colors.white, fontSize: 13),
            ),
            subtitle: const Text(
              '通知内の各アプリ行の境界を分かりやすくする',
              style: TextStyle(color: Colors.white54, fontSize: 11),
            ),
            activeColor: Colors.tealAccent,
            dense: true,
            value: showDividers,
            onChanged: (v) async {
              await ss.setQuickLauncherShowDividers(v);
              await resync(
                  enabled: enabled,
                  prominent: prominent,
                  showDividers: v,
                  source: source);
              if (mounted) setState(() {});
            },
          ),
          SwitchListTile(
            contentPadding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            title: const Text(
              '展開状態で表示',
              style: TextStyle(color: Colors.white, fontSize: 13),
            ),
            subtitle: const Text(
              'ヘッズアップ通知で目立たせ、シェード内でも展開済みになりやすく',
              style: TextStyle(color: Colors.white54, fontSize: 11),
            ),
            activeColor: Colors.tealAccent,
            dense: true,
            value: prominent,
            onChanged: (v) async {
              await ss.setQuickLauncherProminent(v);
              await resync(
                  enabled: enabled,
                  prominent: v,
                  showDividers: showDividers,
                  source: source);
              if (mounted) setState(() {});
            },
          ),
        ],
      ],
    );
  }
}

// ── Quick Launcher App Picker ────────────────────────────────────────────────

/// Lets the user pick which apps appear in the persistent quick-launcher
/// notification when source == 'custom'. Selection order is preserved so
/// the user can prioritise their most-used apps at the top of the
/// notification list.
class _QuickLauncherAppPickerScreen extends StatefulWidget {
  final AppService appService;
  final SettingsService settingsService;

  const _QuickLauncherAppPickerScreen({
    required this.appService,
    required this.settingsService,
  });

  @override
  State<_QuickLauncherAppPickerScreen> createState() =>
      _QuickLauncherAppPickerScreenState();
}

class _QuickLauncherAppPickerScreenState
    extends State<_QuickLauncherAppPickerScreen> {
  List<AppConfig> _allApps = [];
  List<String> _selected = [];
  String _query = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _selected = List.from(widget.settingsService.quickLauncherCustomApps);
    _load();
  }

  Future<void> _load() async {
    final apps = await widget.appService.getAllApps();
    apps.sort((a, b) =>
        _label(a).toLowerCase().compareTo(_label(b).toLowerCase()));
    if (!mounted) return;
    setState(() {
      _allApps = apps;
      _loading = false;
    });
  }

  String _label(AppConfig a) =>
      (a.customName != null && a.customName!.isNotEmpty)
          ? a.customName!
          : a.appName;

  Future<void> _save() async {
    await widget.settingsService.setQuickLauncherCustomApps(_selected);
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _query.isEmpty
        ? _allApps
        : _allApps.where((a) =>
            _label(a).toLowerCase().contains(_query.toLowerCase())).toList();

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('クイック起動アプリ (${_selected.length})',
            style: const TextStyle(fontSize: 16)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: TextField(
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: '検索',
                      hintStyle:
                          const TextStyle(color: Colors.white38, fontSize: 13),
                      prefixIcon:
                          const Icon(Icons.search, color: Colors.white38),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.05),
                      contentPadding: EdgeInsets.zero,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onChanged: (v) => setState(() => _query = v),
                  ),
                ),
                if (_selected.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Row(
                      children: [
                        Text('選択順 (上から通知に並ぶ): ${_selected.length}件',
                            style: const TextStyle(
                                color: Colors.white54, fontSize: 11)),
                        const Spacer(),
                        TextButton(
                          onPressed: () async {
                            setState(() => _selected.clear());
                            await _save();
                          },
                          child: const Text('全解除',
                              style: TextStyle(
                                  color: Colors.redAccent, fontSize: 12)),
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (_, i) {
                      final app = filtered[i];
                      final pkg = app.packageName;
                      final isSelected = _selected.contains(pkg);
                      final orderIdx = isSelected ? _selected.indexOf(pkg) : -1;
                      return Material(
                        color: isSelected
                            ? Colors.tealAccent.withOpacity(0.08)
                            : Colors.transparent,
                        child: InkWell(
                          onTap: () async {
                            setState(() {
                              if (isSelected) {
                                _selected.remove(pkg);
                              } else {
                                _selected.add(pkg);
                              }
                            });
                            await _save();
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 4),
                            child: Row(
                              children: [
                                Icon(
                                  isSelected
                                      ? Icons.check_box
                                      : Icons.check_box_outline_blank,
                                  color: isSelected
                                      ? Colors.tealAccent
                                      : Colors.white38,
                                  size: 22,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    _label(app),
                                    style: TextStyle(
                                      color: isSelected
                                          ? Colors.tealAccent
                                          : Colors.white,
                                      fontSize: 15,
                                      fontWeight: isSelected
                                          ? FontWeight.w500
                                          : FontWeight.normal,
                                    ),
                                  ),
                                ),
                                if (isSelected)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.tealAccent.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      '#${orderIdx + 1}',
                                      style: const TextStyle(
                                        color: Colors.tealAccent,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}

// ── Mindful Delay Settings Screen ────────────────────────────────────────────

class _MindfulDelaySettingsScreen extends StatefulWidget {
  final AppService appService;
  final SettingsService settingsService;

  const _MindfulDelaySettingsScreen({
    required this.appService,
    required this.settingsService,
  });

  @override
  State<_MindfulDelaySettingsScreen> createState() =>
      _MindfulDelaySettingsScreenState();
}

class _MindfulDelaySettingsScreenState
    extends State<_MindfulDelaySettingsScreen> {
  List<AppConfig> _apps = [];
  bool _loading = true;
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';
  final TextEditingController _customSecsCtrl = TextEditingController();

  SettingsService get _ss => widget.settingsService;
  AppService get _as => widget.appService;

  @override
  void initState() {
    super.initState();
    _searchCtrl
        .addListener(() => setState(() => _searchQuery = _searchCtrl.text));
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _customSecsCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final apps = await _as.getAllApps();
    if (!mounted) return;
    setState(() {
      _apps = apps;
      _loading = false;
    });
  }

  String _displayName(AppConfig app) =>
      (app.customName?.isNotEmpty == true) ? app.customName! : app.appName;

  List<AppConfig> get _filteredApps {
    final sorted = List<AppConfig>.from(_apps)
      ..sort((a, b) => _displayName(a).compareTo(_displayName(b)));
    if (_searchQuery.isEmpty) return sorted;
    final q = _searchQuery.toLowerCase();
    return sorted
        .where((a) =>
            _displayName(a).toLowerCase().contains(q) ||
            a.appName.toLowerCase().contains(q))
        .toList();
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 8, bottom: 6),
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.transparent,
          border:
              Border.all(color: selected ? Colors.white : Colors.white38),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          label,
          style: TextStyle(
              color: selected ? Colors.black : Colors.white70,
              fontSize: 12),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const presetSecs = [3, 5, 10, 30, 60];
    final customSecs = _ss.mindfulDelaySeconds;
    final isCustom = !presetSecs.contains(customSecs);

    final s = S.of(context);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(s.mindfulDelaySettings,
            style: const TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Column(
        children: [
          // ── Global settings ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Global toggle
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(s.mindfulDelayEnable,
                      style: const TextStyle(color: Colors.white, fontSize: 14)),
                  subtitle: Text(s.mindfulDelayHelp,
                      style: const TextStyle(color: Colors.white38, fontSize: 11)),
                  activeColor: Colors.tealAccent,
                  value: _ss.mindfulDelayEnabled,
                  onChanged: (v) async {
                    await _ss.setMindfulDelayEnabled(v);
                    setState(() {});
                  },
                ),
                const Divider(color: Colors.white12),
                const SizedBox(height: 8),
                Text(s.waitTime,
                    style: const TextStyle(color: Colors.white70, fontSize: 13)),
                const SizedBox(height: 8),
                Wrap(
                  children: [
                    ...presetSecs.map((sec) => _chip(
                          sec < 60 ? s.secondsShort(sec) : s.minutesShortGeneric(sec ~/ 60),
                          customSecs == sec && !isCustom,
                          () async {
                            await _ss.setMindfulDelaySeconds(sec);
                            setState(() {});
                          },
                        )),
                    _chip(
                        s.speedCustom,
                        isCustom,
                        () async {
                          _customSecsCtrl.text =
                              isCustom ? '$customSecs' : '';
                          final result = await showDialog<int>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              backgroundColor: const Color(0xFF1A1A1A),
                              title: Text(S.of(ctx).customSeconds,
                                  style: const TextStyle(color: Colors.white)),
                              content: TextField(
                                controller: _customSecsCtrl,
                                keyboardType: TextInputType.number,
                                autofocus: true,
                                style: const TextStyle(
                                    color: Colors.white),
                                decoration: InputDecoration(
                                  hintText: S.of(ctx).enterSecondsHint,
                                  hintStyle: const TextStyle(
                                      color: Colors.white38),
                                  filled: true,
                                  fillColor:
                                      Colors.white.withOpacity(0.07),
                                  border: OutlineInputBorder(
                                    borderRadius:
                                        BorderRadius.circular(4),
                                    borderSide: BorderSide.none,
                                  ),
                                ),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(ctx),
                                  child: Text(S.of(ctx).actionCancel,
                                      style: const TextStyle(
                                          color: Colors.white54)),
                                ),
                                TextButton(
                                  onPressed: () {
                                    final v = int.tryParse(
                                        _customSecsCtrl.text);
                                    if (v != null && v > 0) {
                                      Navigator.pop(ctx, v);
                                    }
                                  },
                                  child: Text(S.of(ctx).actionDone,
                                      style: const TextStyle(
                                          color: Colors.white)),
                                ),
                              ],
                            ),
                          );
                          if (result != null) {
                            await _ss.setMindfulDelaySeconds(result);
                            setState(() {});
                          }
                        }),
                  ],
                ),
                const SizedBox(height: 12),
                Text(s.afterTimeoutAction,
                    style: const TextStyle(color: Colors.white70, fontSize: 13)),
                const SizedBox(height: 8),
                ...[
                  ('launch', s.launchDirectly),
                  ('confirm', s.showConfirmAgain),
                  ('cancel', s.cancelToHome),
                ].map((opt) {
                  final sel = _ss.mindfulDelayAction == opt.$1;
                  return InkWell(
                    onTap: () async {
                      await _ss.setMindfulDelayAction(opt.$1);
                      setState(() {});
                    },
                    child: Padding(
                      padding:
                          const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          Radio<String>(
                            value: opt.$1,
                            groupValue: _ss.mindfulDelayAction,
                            activeColor: Colors.white,
                            fillColor: WidgetStateProperty.all(
                                sel
                                    ? Colors.white
                                    : Colors.white38),
                            onChanged: (v) async {
                              if (v != null) {
                                await _ss.setMindfulDelayAction(v);
                                setState(() {});
                              }
                            },
                          ),
                          Text(opt.$2,
                              style: TextStyle(
                                  color: sel
                                      ? Colors.white
                                      : Colors.white70,
                                  fontSize: 14)),
                        ],
                      ),
                    ),
                  );
                }),
                const Divider(color: Colors.white12),
                const SizedBox(height: 4),
              ],
            ),
          ),
          // ── App list ──
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
            child: TextField(
              controller: _searchCtrl,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                hintText: s.appSearchHint,
                hintStyle: const TextStyle(
                    color: Colors.white38, fontSize: 13),
                prefixIcon: const Icon(Icons.search,
                    color: Colors.white38, size: 18),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear,
                            color: Colors.white38, size: 18),
                        onPressed: _searchCtrl.clear,
                      )
                    : null,
                filled: true,
                fillColor: Colors.white.withOpacity(0.07),
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 6),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                s.appliedToAppsCount(_filteredApps.where((a) => a.mindfulDelay).length),
                style: const TextStyle(
                    color: Colors.white54, fontSize: 12),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(
                    child:
                        CircularProgressIndicator(color: Colors.white))
                : ListView.builder(
                    itemCount: _filteredApps.length,
                    itemBuilder: (_, i) {
                      final app = _filteredApps[i];
                      return SwitchListTile(
                        title: Text(
                          _displayName(app),
                          style: const TextStyle(
                              color: Colors.white, fontSize: 14),
                        ),
                        subtitle: Text(
                          floorLabel(app.floor),
                          style: const TextStyle(
                              color: Colors.white38, fontSize: 12),
                        ),
                        activeColor: Colors.tealAccent,
                        value: app.mindfulDelay,
                        onChanged: (v) async {
                          app.mindfulDelay = v;
                          await _as.saveConfig(app);
                          setState(() {});
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

