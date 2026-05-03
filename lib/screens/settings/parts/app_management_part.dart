part of '../settings_screen.dart';

extension AppManagementMethods on _SettingsScreenState {
  List<Widget> _appMgmtSettingRows() {
    final s = S.of(context);
    final ss = _ss;
    final limitLabels = <String, String>{
      'unlimited': s.unlimited,
      'daily': s.periodOnceDaily,
      'weekly': s.periodOnceWeekly,
      'yearly': s.periodOnceYearly,
    };
    final current = ss.emergencyLimit;
    final emgAppCount = ss.getEmergencyApps().length;
    final emgSummary =
        s.emergencySummary(limitLabels[current] ?? current, emgAppCount);

    return [
      _settingRow(s.appList, '', () {
        Navigator.push(context, MaterialPageRoute(
          builder: (_) => _AppListScreen(appService: _as, settingsService: ss),
        )).then((_) => _load());
      }),
      _rowDivider,
      _settingRow(s.randomPlacement, '', _doRandomize),
      _rowDivider,
      _settingRow(s.floorOptimizationProposal, '', _doFloorOptimization),
      _rowDivider,
      _expandableRow(
        key: 'appmgmt_emergency',
        title: s.emergencyMode,
        summary: emgSummary,
        children: _emergencyChildren(ss, current, limitLabels),
      ),
      _rowDivider,
      _settingRow(
        s.lastUsedDisplay,
        ss.lastUsedDisplayApps.isEmpty
            ? s.notSet
            : s.displayedInAppsCount(ss.lastUsedDisplayApps.length),
        () async {
          final granted = await _native.isUsageStatsPermissionGranted();
          if (!granted) {
            if (!mounted) return;
            final go = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                backgroundColor: const Color(0xFF1A1A1A),
                title: Text(S.of(ctx).usageStatsAccessRequired,
                    style: const TextStyle(color: Colors.white, fontSize: 14)),
                content: Text(
                  S.of(ctx).usageStatsAccessExplanation,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: Text(S.of(ctx).actionCancel,
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
            if (go == true) await _native.openUsageStatsSettings();
            return;
          }
          await _showLockAppSelector(
              'lastUsedDisplayApps',
              ss.lastUsedDisplayApps,
              (v) => ss.setLastUsedDisplayApps(v));
          setState(() {});
        },
      ),
    ];
  }

  List<Widget> _emergencyChildren(SettingsService ss, String current,
      Map<String, String> limitLabels) {
    final s = S.of(context);
    return [
      _expandableRow(
        key: 'emg_limits',
        title: s.emergencyUsageLimit,
        summary: _emgLimitsSummary(ss),
        children: _emgLimitChildren(ss),
      ),
      _rowDivider,
      _settingRow(
        s.emergencyAppsRegister,
        ss.getEmergencyApps().isEmpty
            ? s.notRegistered
            : s.registeredCount(ss.getEmergencyApps().length),
        () async {
          await _showLockAppSelector(
              'emergencyApps',
              ss.getEmergencyApps(),
              (v) => ss.setEmergencyApps(v));
          setState(() {});
        },
      ),
      _rowDivider,
      _settingRow(s.emergencyFontColor, '', () async {
        final colors = [
          (0xFFFF5252, s.colorRed),
          (0xFFFF9800, s.colorOrange),
          (0xFFFFEB3B, s.colorYellow),
          (0xFFFFFFFF, s.colorWhiteNoDistinction),
          (0xFF69F0AE, s.colorGreen),
          (0xFF40C4FF, s.colorLightBlue),
        ];
        final v = await showDialog<int>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF1A1A1A),
            title: Text(S.of(ctx).emergencyFontColorTitle,
                style: const TextStyle(color: Colors.white, fontSize: 14)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: colors
                  .map((c) => ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                                color: Color(c.$1),
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white24))),
                        title: Text(c.$2,
                            style: TextStyle(color: Color(c.$1), fontSize: 13)),
                        trailing: ss.emergencyAppFontColor == c.$1
                            ? const Icon(Icons.check,
                                color: Colors.tealAccent, size: 18)
                            : null,
                        onTap: () => Navigator.pop(ctx, c.$1),
                      ))
                  .toList(),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(S.of(ctx).actionCancel,
                      style: const TextStyle(color: Colors.white54))),
            ],
          ),
        );
        if (v != null) {
          await ss.setEmergencyAppFontColor(v);
          setState(() {});
        }
      }),
      _rowDivider,
      _settingRow(
        s.emergencyDisplayMethod,
        ss.emergencyAppDisplayMode == 'section'
            ? s.emergencyDisplaySection
            : s.emergencyDisplayNormal,
        () async {
          final v = await _showOptionsDialog(s.emergencyDisplayMethodTitle, [
            ('section', s.emergencyDisplaySectionDesc),
            ('normal', s.emergencyDisplayNormalDesc),
          ], ss.emergencyAppDisplayMode);
          if (v != null) {
            await ss.setEmergencyAppDisplayMode(v);
            setState(() {});
          }
        },
      ),
      _rowDivider,
      SwitchListTile(
        contentPadding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
        title: Text(s.emergencySectionIndex,
            style: const TextStyle(color: Colors.white, fontSize: 14)),
        subtitle: Text(s.emergencySectionIndexDesc,
            style: const TextStyle(color: Colors.white54, fontSize: 12)),
        activeColor: Colors.tealAccent,
        value: ss.emergencyAppShowIndex,
        onChanged: (v) async {
          await ss.setEmergencyAppShowIndex(v);
          setState(() {});
        },
      ),
    ];
  }

  // ── Emergency-mode usage limits ──────────────────────────────────────────

  String _emgLimitsSummary(SettingsService ss) {
    final s = S.of(context);
    final all = ss.capSummary(ss.emergencyCapAll);
    final pick = ss.capSummary(ss.emergencyCapPick);
    final regGlobal = ss.capSummary(ss.emergencyCapRegisteredGlobal);
    return s.emergencyLimitsSummary(all, pick, regGlobal);
  }

  List<Widget> _emgLimitChildren(SettingsService ss) {
    final s = S.of(context);
    return [
      _settingRow(
        s.emergencyShowAllOn1F,
        ss.capSummary(ss.emergencyCapAll),
        () async {
          final cap = ss.emergencyCapAll;
          final result = await _showCapDialog(
              s.emergencyShowAllOn1FLimit,
              (cap['count'] as num?)?.toInt() ?? 0,
              cap['period'] as String? ?? 'weekly');
          if (result == null) return;
          await ss.setEmergencyCapAll(result.$1, result.$2);
          setState(() {});
        },
      ),
      _rowDivider,
      _settingRow(
        s.emergencyAppListPick,
        ss.capSummary(ss.emergencyCapPick),
        () async {
          final cap = ss.emergencyCapPick;
          final result = await _showCapDialog(
              s.emergencyAppListPickLimit,
              (cap['count'] as num?)?.toInt() ?? 0,
              cap['period'] as String? ?? 'daily');
          if (result == null) return;
          await ss.setEmergencyCapPick(result.$1, result.$2);
          setState(() {});
        },
      ),
      _rowDivider,
      _expandableRow(
        key: 'emg_limits_registered',
        title: s.emergencyRegistered,
        summary: s.emergencyRegisteredSummary(
          ss.capSummary(ss.emergencyCapRegisteredGlobal),
          _emgPerAppCount(ss),
          ss.emergencyCapFolders.length,
        ),
        children: [
          _settingRow(
            s.emergencyGlobalLimit,
            ss.capSummary(ss.emergencyCapRegisteredGlobal),
            () async {
              final cap = ss.emergencyCapRegisteredGlobal;
              final result = await _showCapDialog(
                  s.emergencyRegisteredGlobalLimit,
                  (cap['count'] as num?)?.toInt() ?? 0,
                  cap['period'] as String? ?? 'daily');
              if (result == null) return;
              await ss.setEmergencyCapRegisteredGlobal(
                  result.$1, result.$2);
              setState(() {});
            },
          ),
          _rowDivider,
          _settingRow(
            s.emergencyPerAppLimit,
            s.perAppLimitCount(_emgPerAppCount(ss)),
            () => _showPerAppCapsScreen(ss),
          ),
          _rowDivider,
          _settingRow(
            s.emergencyFolderLimit,
            s.folderCount(ss.emergencyCapFolders.length),
            () => _showFolderCapsScreen(ss),
          ),
        ],
      ),
    ];
  }

  int _emgPerAppCount(SettingsService ss) {
    int n = 0;
    for (final pkg in ss.getEmergencyApps()) {
      if (ss.emergencyCapForApp(pkg) != null) n++;
    }
    return n;
  }

  /// Returns (count, period) or null on cancel. count==0 means unlimited.
  Future<(int, String)?> _showCapDialog(
      String title, int initialCount, String initialPeriod) async {
    int count = initialCount.clamp(0, 999);
    String period = initialPeriod;
    final s = S.of(context);
    final periods = <(String, String)>[
      ('hourly', s.periodHourly),
      ('daily', s.periodDaily),
      ('weekly', s.periodWeekly),
      ('monthly', s.periodMonthly),
      ('yearly', s.periodYearly),
    ];
    final ctrl = TextEditingController(
        text: initialCount > 0 ? initialCount.toString() : '');
    return showDialog<(int, String)>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInner) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          title: Text(title,
              style: const TextStyle(color: Colors.white, fontSize: 14)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(S.of(ctx).countWithEmptyUnlimitedHint,
                  style: const TextStyle(color: Colors.white54, fontSize: 12)),
              const SizedBox(height: 6),
              TextField(
                controller: ctrl,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  hintText: S.of(ctx).unlimited,
                  hintStyle: const TextStyle(color: Colors.white38),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.07),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: BorderSide.none),
                ),
                onChanged: (v) {
                  count = int.tryParse(v) ?? 0;
                },
              ),
              const SizedBox(height: 12),
              Text(S.of(ctx).periodLabel,
                  style: const TextStyle(color: Colors.white54, fontSize: 12)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: periods.map((p) {
                  final sel = period == p.$1;
                  return GestureDetector(
                    onTap: () => setInner(() => period = p.$1),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: sel ? Colors.white : Colors.transparent,
                        border: Border.all(
                            color: sel ? Colors.white : Colors.white38),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(p.$2,
                          style: TextStyle(
                              color: sel ? Colors.black : Colors.white70,
                              fontSize: 11)),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(S.of(ctx).actionCancel,
                  style: const TextStyle(color: Colors.white54)),
            ),
            TextButton(
              onPressed: () {
                final c = int.tryParse(ctrl.text) ?? 0;
                Navigator.pop(ctx, (c < 0 ? 0 : c, period));
              },
              child: Text(S.of(ctx).actionSave,
                  style: const TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  void _showPerAppCapsScreen(SettingsService ss) {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => _EmergencyPerAppCapsScreen(
          settingsService: ss, allApps: _apps),
    )).then((_) => setState(() {}));
  }

  void _showFolderCapsScreen(SettingsService ss) {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => _EmergencyFolderCapsScreen(
          settingsService: ss, allApps: _apps),
    )).then((_) => setState(() {}));
  }

  Future<void> _doRandomize() async {
    if (_ss.isLockCooldownActive) {
      _showSnack(S.of(context).changeProcessingTryLater);
      return;
    }
    // Show app selection dialog
    final nonPinned = _apps.where((a) => !a.isPinned).toList()
      ..sort((a, b) => a.appName.compareTo(b.appName));
    final selected = <String>{for (final a in nonPinned) a.packageName};

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInner) {
          final s = S.of(ctx);
          return AlertDialog(
            backgroundColor: const Color(0xFF1A1A1A),
            title: Text(s.randomPlacementSelectApps,
                style: const TextStyle(color: Colors.white, fontSize: 15)),
            content: SizedBox(
              width: double.maxFinite,
              height: 420,
              child: Column(
                children: [
                  Row(
                    children: [
                      TextButton(
                        onPressed: () => setInner(() => selected.addAll(nonPinned.map((a) => a.packageName))),
                        child: Text(s.actionAllSelect, style: const TextStyle(color: Colors.tealAccent, fontSize: 12)),
                      ),
                      TextButton(
                        onPressed: () => setInner(() => selected.clear()),
                        child: Text(s.actionAllDeselect, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                      ),
                      Expanded(
                        child: Text(s.selectedItemsCount(selected.length, nonPinned.length),
                            textAlign: TextAlign.right,
                            style: const TextStyle(color: Colors.white38, fontSize: 12)),
                      ),
                    ],
                  ),
                  const Divider(color: Colors.white12),
                  Expanded(
                    child: ListView.builder(
                      itemCount: nonPinned.length,
                      itemBuilder: (_, i) {
                        final app = nonPinned[i];
                        final isSelected = selected.contains(app.packageName);
                        return CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          value: isSelected,
                          activeColor: Colors.tealAccent,
                          checkColor: Colors.black,
                          title: Text(app.appName,
                              style: const TextStyle(color: Colors.white, fontSize: 13)),
                          subtitle: Text(floorLabel(app.floor),
                              style: const TextStyle(color: Colors.white38, fontSize: 11)),
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
                  child: Text(s.actionCancel, style: const TextStyle(color: Colors.white54))),
              TextButton(
                  onPressed: selected.isEmpty ? null : () => Navigator.pop(ctx, true),
                  child: Text(s.actionExecute, style: const TextStyle(color: Colors.white))),
            ],
          );
        },
      ),
    );
    if (confirmed != true || selected.isEmpty) return;

    final fullMap = await _as.buildRandomFloorMap();
    // Filter to only selected packages
    final floorMap = Map.fromEntries(fullMap.entries.where((e) => selected.contains(e.key)));

    if (_ss.lockModeEnabled) {
      for (final e in floorMap.entries) {
        await _ss.requestFloorChange(e.key, e.value);
      }
      if (mounted) _showSnack(S.of(context).randomScheduledCount(floorMap.length));
    } else {
      await _as.applyFloorMap(floorMap);
      if (mounted) _showSnack(S.of(context).randomDoneCount(floorMap.length));
    }
    await _load();
  }

  // ── usage-based floor optimization ───────────────────────────

  Future<void> _doFloorOptimization() async {
    final stats = await _native.getUsageStats30Days();
    if (!mounted) return;

    final suggestions = <Map<String, dynamic>>[];

    final s = S.of(context);
    for (final app in _apps) {
      final usage = stats[app.packageName] ?? 0;
      // Apps with >60 min on floor 2+ → suggest floor 1
      if (usage > 60 && app.floor >= 2) {
        suggestions.add({
          'app': app,
          'currentFloor': app.floor,
          'suggestedFloor': 1,
          'reason': s.minutesUsedToFloor1(usage),
          'approved': true,
        });
      }
      // Apps with 0 minutes on floor 1 → suggest higher floor
      else if (usage == 0 && app.floor == 1) {
        suggestions.add({
          'app': app,
          'currentFloor': app.floor,
          'suggestedFloor': 3,
          'reason': s.noUsageToFloor3,
          'approved': true,
        });
      }
    }

    if (suggestions.isEmpty) {
      _showSnack(s.floorOptimizationNoProposals);
      return;
    }

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInner) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          title: Text(S.of(ctx).floorOptimizationProposalDialog,
              style: const TextStyle(color: Colors.white)),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: suggestions.length,
              itemBuilder: (_, i) {
                final s = suggestions[i];
                final app = s['app'] as AppConfig;
                return Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_displayName(app),
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 13)),
                          Text(s['reason'] as String,
                              style: const TextStyle(
                                  color: Colors.white54,
                                  fontSize: 11)),
                        ],
                      ),
                    ),
                    Switch(
                      value: s['approved'] as bool,
                      activeColor: Colors.greenAccent,
                      onChanged: (v) =>
                          setInner(() => s['approved'] = v),
                    ),
                  ],
                );
              },
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(S.of(ctx).actionCancel,
                    style: const TextStyle(color: Colors.white54))),
            TextButton(
              onPressed: () async {
                for (final sg in suggestions) {
                  if (sg['approved'] == true) {
                    final app = sg['app'] as AppConfig;
                    final newFloor = sg['suggestedFloor'] as int;
                    if (_ss.lockModeEnabled) {
                      await _ss.requestFloorChange(
                          app.packageName, newFloor);
                    } else {
                      app.floor = newFloor;
                      await _as.saveConfig(app);
                    }
                  }
                }
                if (ctx.mounted) Navigator.pop(ctx);
                await _load();
                if (mounted) _showSnack(S.of(context).floorOptimizationDone);
              },
              child: Text(S.of(ctx).actionApply,
                  style: const TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

}

// ── App List Screen ───────────────────────────────────────────────────────────

class _AppListScreen extends StatefulWidget {
  final AppService appService;
  final SettingsService settingsService;

  const _AppListScreen({
    required this.appService,
    required this.settingsService,
  });

  @override
  State<_AppListScreen> createState() => _AppListScreenState();
}

class _AppListScreenState extends State<_AppListScreen> {
  List<AppConfig> _apps = [];
  bool _loading = true;
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';
  bool _selectionMode = false;
  final Set<String> _selectedPkgs = {};
  int? _filterFloor; // null = all floors

  AppService get _as => widget.appService;
  SettingsService get _ss => widget.settingsService;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(
        () => setState(() => _searchQuery = _searchCtrl.text));
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
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
    var list = List<AppConfig>.from(_apps);
    if (_filterFloor != null) {
      list = list.where((a) => a.floor == _filterFloor).toList();
    }
    list.sort((a, b) => _displayName(a).compareTo(_displayName(b)));
    if (_searchQuery.isEmpty) return list;
    final q = _searchQuery.toLowerCase();
    return list
        .where((a) =>
            _displayName(a).toLowerCase().contains(q) ||
            a.appName.toLowerCase().contains(q))
        .toList();
  }

  Widget _buildFloorFilterBar() {
    final maxFloors = widget.settingsService.maxFloors;
    final underFloors = widget.settingsService.undergroundFloors;
    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          _floorChip(null, S.of(context).allFloors),
          // Underground floors (deepest first → BnF .. B1F).
          for (int i = underFloors; i >= 1; i--)
            _floorChip(-i, floorLabel(-i)),
          // Above-ground floors (1F .. mF).
          for (int i = 1; i <= maxFloors; i++) _floorChip(i, floorLabel(i)),
        ],
      ),
    );
  }

  Widget _floorChip(int? floor, String label) {
    final sel = _filterFloor == floor;
    return GestureDetector(
      onTap: () => setState(() => _filterFloor = floor),
      child: Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: sel ? Colors.white : Colors.transparent,
          border: Border.all(color: sel ? Colors.white : Colors.white38),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(label,
            style: TextStyle(
                color: sel ? Colors.black : Colors.white70, fontSize: 12)),
      ),
    );
  }

  Widget _buildAppTile(AppConfig app) {
    final now = DateTime.now();
    final activeEmg = app.isEmergency &&
        app.emergencyUntil != null &&
        app.emergencyUntil!.isAfter(now);
    final pending = _ss.pendingFloorChanges?[app.packageName];
    final dFloor = pending ?? app.floor;
    final hasPending = pending != null;
    final folder =
        app.folderName?.isNotEmpty == true ? app.folderName! : null;
    final isBatch = _ss.batchApps.contains(app.packageName);
    final isSelected = _selectedPkgs.contains(app.packageName);
    final isBlocked = _ss.blockTypeForApp(app.packageName) != 'none';

    return ListTile(
      leading: _selectionMode
          ? SizedBox(
              width: 24,
              height: 24,
              child: Checkbox(
                value: isSelected,
                activeColor: Colors.white,
                checkColor: Colors.black,
                side: const BorderSide(color: Colors.white38),
                onChanged: (_) => setState(() {
                  if (isSelected) {
                    _selectedPkgs.remove(app.packageName);
                  } else {
                    _selectedPkgs.add(app.packageName);
                  }
                }),
              ),
            )
          : null,
      title: Text(
        _displayName(app),
        style: TextStyle(
          color: activeEmg ? Colors.redAccent : Colors.white,
          fontSize: 15,
        ),
      ),
      subtitle: Wrap(
        spacing: 6,
        children: [
          Text(
            floorLabel(dFloor),
            style: TextStyle(
              color: hasPending ? Colors.amber : Colors.white38,
              fontSize: 12,
            ),
          ),
          if (hasPending)
            Text(S.of(context).pendingChange,
                style: const TextStyle(color: Colors.amber, fontSize: 11)),
          if (folder != null)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.folder, color: Colors.white54, size: 13),
                const SizedBox(width: 2),
                Text(folder,
                    style: const TextStyle(
                        color: Colors.white54, fontSize: 11)),
              ],
            ),
          if (app.isPinned)
            const Icon(Icons.push_pin,
                color: Colors.blueAccent, size: 13),
          if (app.mindfulDelay)
            Text(S.of(context).delayBadge,
                style: const TextStyle(color: Colors.tealAccent, fontSize: 11)),
          if (isBatch)
            Text(S.of(context).batchBadge,
                style: const TextStyle(
                    color: Colors.purpleAccent, fontSize: 11)),
          if (isBlocked)
            Text(S.of(context).blockBadge,
                style: const TextStyle(
                    color: Colors.redAccent, fontSize: 11)),
          if (activeEmg)
            Text(S.of(context).emergencyActiveBadge,
                style: const TextStyle(color: Colors.redAccent, fontSize: 11)),
          if (_ss.isEmergencyApp(app.packageName) && !activeEmg)
            Text(S.of(context).emergencyDesignatedBadge,
                style: const TextStyle(color: Colors.white24, fontSize: 11)),
        ],
      ),
      selected: isSelected,
      selectedTileColor: Colors.white.withOpacity(0.05),
      trailing: _selectionMode
          ? null
          : const Icon(Icons.chevron_right,
              color: Colors.white38, size: 18),
      onTap: () async {
        if (_selectionMode) {
          setState(() {
            if (isSelected) {
              _selectedPkgs.remove(app.packageName);
            } else {
              _selectedPkgs.add(app.packageName);
            }
          });
        } else {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => _AppDetailScreen(
                app: app,
                appService: _as,
                settingsService: _ss,
                allApps: _apps,
              ),
            ),
          );
          await _load();
        }
      },
      onLongPress: () {
        if (!_selectionMode) {
          setState(() {
            _selectionMode = true;
            _selectedPkgs.add(app.packageName);
          });
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredApps;
    final s = S.of(context);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: _selectionMode
            ? Text(s.selectedCount(_selectedPkgs.length),
                style: const TextStyle(color: Colors.white))
            : Text(s.appList,
                style: const TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: _selectionMode
            ? [
                TextButton(
                  onPressed: () => setState(() {
                    _selectedPkgs.addAll(filtered.map((a) => a.packageName));
                  }),
                  child: Text(s.actionSelectAll,
                      style: const TextStyle(color: Colors.white70, fontSize: 13)),
                ),
                TextButton(
                  onPressed: () => setState(() {
                    _selectionMode = false;
                    _selectedPkgs.clear();
                  }),
                  child: Text(s.actionDeselectAll,
                      style: const TextStyle(color: Colors.white70, fontSize: 13)),
                ),
              ]
            : null,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              controller: _searchCtrl,
              style:
                  const TextStyle(color: Colors.white, fontSize: 14),
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
          _buildFloorFilterBar(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                s.appListCount(filtered.length),
                style: const TextStyle(
                    color: Colors.white54, fontSize: 12),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(
                        color: Colors.white))
                : ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (_, i) => _buildAppTile(filtered[i]),
                  ),
          ),
          // Bulk operations bottom bar
          if (_selectionMode && _selectedPkgs.isNotEmpty)
            Container(
              color: const Color(0xFF1A1A1A),
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
              child: SafeArea(
                top: false,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    // Floor change
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white12,
                          foregroundColor: Colors.white),
                      icon: const Icon(Icons.layers, size: 16),
                      label: Text(s.floorChange, style: const TextStyle(fontSize: 12)),
                      onPressed: () async {
                        int? selectedFloor;
                        final result = await showDialog<int>(
                          context: context,
                          builder: (ctx) => StatefulBuilder(
                            builder: (ctx, si) => AlertDialog(
                              backgroundColor: const Color(0xFF1A1A1A),
                              title: Text(S.of(ctx).moveCount(_selectedPkgs.length),
                                  style: const TextStyle(color: Colors.white, fontSize: 14)),
                              content: Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: List.generate(10, (i) {
                                  final f = i + 1;
                                  final sel = selectedFloor == f;
                                  return GestureDetector(
                                    onTap: () => si(() => selectedFloor = f),
                                    child: Container(
                                      width: 44,
                                      height: 36,
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: sel ? Colors.white : Colors.transparent,
                                        border: Border.all(color: sel ? Colors.white : Colors.white38),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(floorLabel(f),
                                          style: TextStyle(color: sel ? Colors.black : Colors.white54, fontSize: 12)),
                                    ),
                                  );
                                }),
                              ),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(ctx), child: Text(S.of(ctx).actionCancel, style: const TextStyle(color: Colors.white54))),
                                TextButton(
                                  onPressed: selectedFloor != null ? () => Navigator.pop(ctx, selectedFloor) : null,
                                  child: Text(S.of(ctx).actionMove, style: const TextStyle(color: Colors.white)),
                                ),
                              ],
                            ),
                          ),
                        );
                        if (result != null && mounted) {
                          for (final pkg in _selectedPkgs) {
                            final app = _apps.firstWhere((a) => a.packageName == pkg, orElse: () => AppConfig(packageName: pkg, appName: pkg, floor: 1));
                            if (_ss.lockModeEnabled) {
                              await _ss.requestFloorChange(pkg, result);
                            } else {
                              app.floor = result;
                              await _as.saveConfig(app);
                            }
                          }
                          setState(() { _selectionMode = false; _selectedPkgs.clear(); });
                          await _load();
                        }
                      },
                    ),
                    // Mindful delay toggle
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white12,
                          foregroundColor: Colors.white),
                      icon: const Icon(Icons.hourglass_bottom, size: 16),
                      label: Text(s.delaySwitch, style: const TextStyle(fontSize: 12)),
                      onPressed: () async {
                        // Toggle: if all selected have delay, turn off; otherwise turn on
                        final allOn = _selectedPkgs.every((pkg) {
                          final app = _apps.firstWhere((a) => a.packageName == pkg, orElse: () => AppConfig(packageName: pkg, appName: pkg));
                          return app.mindfulDelay;
                        });
                        for (final pkg in _selectedPkgs) {
                          final app = _apps.firstWhere((a) => a.packageName == pkg, orElse: () => AppConfig(packageName: pkg, appName: pkg));
                          app.mindfulDelay = !allOn;
                          await _as.saveConfig(app);
                        }
                        setState(() { _selectionMode = false; _selectedPkgs.clear(); });
                        await _load();
                      },
                    ),
                    // Pin toggle
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white12,
                          foregroundColor: Colors.white),
                      icon: const Icon(Icons.push_pin, size: 16),
                      label: Text(s.pinSwitch, style: const TextStyle(fontSize: 12)),
                      onPressed: () async {
                        final allPinned = _selectedPkgs.every((pkg) {
                          final app = _apps.firstWhere((a) => a.packageName == pkg, orElse: () => AppConfig(packageName: pkg, appName: pkg));
                          return app.isPinned;
                        });
                        for (final pkg in _selectedPkgs) {
                          final app = _apps.firstWhere((a) => a.packageName == pkg, orElse: () => AppConfig(packageName: pkg, appName: pkg));
                          app.isPinned = !allPinned;
                          await _as.saveConfig(app);
                        }
                        setState(() { _selectionMode = false; _selectedPkgs.clear(); });
                        await _load();
                      },
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}


// ── App Detail Screen ─────────────────────────────────────────────────────────

class _AppDetailScreen extends StatefulWidget {
  final AppConfig app;
  final AppService appService;
  final SettingsService settingsService;
  final List<AppConfig> allApps;

  const _AppDetailScreen({
    required this.app,
    required this.appService,
    required this.settingsService,
    required this.allApps,
  });

  @override
  State<_AppDetailScreen> createState() => _AppDetailScreenState();
}

class _AppDetailScreenState extends State<_AppDetailScreen> {
  late int _selectedFloor;
  late bool _isEmergency;
  late int _emergencyMinutes;
  late bool _emergencyActive;
  late bool _isPinned;
  late bool _mindfulDelay;
  late bool _batchEnabled;

  late TextEditingController _customNameCtrl;
  late TextEditingController _folderCtrl;
  String? _selectedFolder;

  SettingsService get _ss => widget.settingsService;
  AppService get _as => widget.appService;

  bool get _lockBlocked =>
      _ss.lockModeEnabled && _ss.isLockCooldownActive;

  @override
  void initState() {
    super.initState();
    final app = widget.app;
    _selectedFloor = _ss.pendingFloorChanges?[app.packageName] ?? app.floor;
    _isEmergency = _ss.isEmergencyApp(app.packageName);
    _emergencyMinutes = (app.emergencyUntil != null &&
            app.emergencyUntil!.isAfter(DateTime.now()))
        ? app.emergencyUntil!
            .difference(DateTime.now())
            .inMinutes
            .clamp(1, 120)
        : 30;
    _emergencyActive = app.isEmergency &&
        app.emergencyUntil != null &&
        app.emergencyUntil!.isAfter(DateTime.now());
    _isPinned = app.isPinned;
    _mindfulDelay = app.mindfulDelay;
    _batchEnabled = _ss.batchApps.contains(app.packageName);
    _customNameCtrl =
        TextEditingController(text: app.customName ?? '');
    _folderCtrl =
        TextEditingController(text: app.folderName ?? '');
    _selectedFolder =
        app.folderName?.isNotEmpty == true ? app.folderName : null;
  }

  @override
  void dispose() {
    _customNameCtrl.dispose();
    _folderCtrl.dispose();
    super.dispose();
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  // Collect existing folders from all apps on same floor
  List<String> get _existingFolders {
    return widget.allApps
        .where((a) =>
            a.floor == _selectedFloor &&
            a.folderName != null &&
            a.folderName!.isNotEmpty)
        .map((a) => a.folderName!)
        .toSet()
        .toList()
      ..sort();
  }

  Widget _floorPickerChip(int f) {
    final sel = _selectedFloor == f;
    return GestureDetector(
      onTap: () => setState(() => _selectedFloor = f),
      child: Container(
        width: 50,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: sel ? Colors.white : Colors.transparent,
          border: Border.all(color: sel ? Colors.white : Colors.white38),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(floorLabel(f),
            style: TextStyle(
                color: sel ? Colors.black : Colors.white54, fontSize: 12)),
      ),
    );
  }

  Future<void> _save() async {
    final app = widget.app;

    // Custom name
    app.customName = _customNameCtrl.text.trim().isEmpty
        ? null
        : _customNameCtrl.text.trim();

    // Folder name
    final folderText = _folderCtrl.text.trim();
    app.folderName = folderText.isEmpty ? _selectedFolder : folderText;
    if (app.folderName?.isEmpty == true) app.folderName = null;

    // isPinned
    app.isPinned = _isPinned;

    // mindfulDelay
    app.mindfulDelay = _mindfulDelay;

    // batch
    final batches = _ss.batchApps;
    if (_batchEnabled) {
      batches.add(app.packageName);
    } else {
      batches.remove(app.packageName);
    }
    await _ss.setBatchApps(batches);

    // Floor change
    if (!_lockBlocked && _selectedFloor != app.floor) {
      if (_ss.lockModeEnabled) {
        final ok = await _ss.requestFloorChange(
            app.packageName, _selectedFloor);
        if (!ok && mounted) _showSnack(S.of(context).cooldownActive);
      } else {
        app.floor = _selectedFloor;
      }
    }

    // Emergency — unified save
    app.isEmergency = _isEmergency;
    if (_isEmergency) {
      await _ss.addEmergencyApp(app.packageName);
    } else {
      await _ss.removeEmergencyApp(app.packageName);
    }
    if (_isEmergency && _emergencyActive) {
      if (!_ss.canActivateEmergency()) {
        _showSnack(_ss.emergencyLimitBlockMessage);
        await _as.saveConfig(app);
        if (mounted) Navigator.pop(context);
        return;
      }
      app.emergencyUntil = DateTime.now()
          .add(Duration(minutes: _emergencyMinutes));
      await _ss.recordEmergencyUseV2('registered', [app.packageName]);
    } else if (!_emergencyActive) {
      app.emergencyUntil = null;
    }

    await _as.saveConfig(app);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(app.appName,
            style: const TextStyle(color: Colors.white, fontSize: 15)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Custom name ──
            Text(S.of(context).displayNameLabel,
                style: const TextStyle(color: Colors.white70, fontSize: 13)),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _customNameCtrl,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: app.appName,
                      hintStyle: const TextStyle(
                          color: Colors.white24, fontSize: 13),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.07),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () {
                    _customNameCtrl.clear();
                    setState(() {});
                  },
                  child: const Icon(Icons.restart_alt,
                      color: Colors.white38, size: 20),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // ── Floor picker ──
            Text(S.of(context).floorLabel,
                style: const TextStyle(color: Colors.white70, fontSize: 13)),
            if (_lockBlocked)
              Padding(
                padding: const EdgeInsets.only(top: 6, bottom: 2),
                child: Text(S.of(context).cooldownChangeBlocked,
                    style: const TextStyle(
                        color: Colors.amber, fontSize: 12)),
              )
            else ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (int i = _ss.undergroundFloors; i >= 1; i--)
                    _floorPickerChip(-i),
                  for (int i = 1; i <= _ss.maxFloors; i++)
                    _floorPickerChip(i),
                ],
              ),
            ],
            const SizedBox(height: 16),

            // ── Folder picker ──
            Text(S.of(context).folderLabel,
                style: const TextStyle(color: Colors.white70, fontSize: 13)),
            const SizedBox(height: 8),
            if (_existingFolders.isNotEmpty) ...[
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  GestureDetector(
                    onTap: () => setState(() {
                      _selectedFolder = null;
                      _folderCtrl.clear();
                    }),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: _selectedFolder == null
                            ? Colors.white
                            : Colors.transparent,
                        border: Border.all(
                            color: _selectedFolder == null
                                ? Colors.white
                                : Colors.white38),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(S.of(context).noneLabel,
                          style: TextStyle(
                              color: _selectedFolder == null
                                  ? Colors.black
                                  : Colors.white54,
                              fontSize: 12)),
                    ),
                  ),
                  ..._existingFolders.map((name) => GestureDetector(
                        onTap: () => setState(() {
                          _selectedFolder = name;
                          _folderCtrl.clear();
                        }),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: _selectedFolder == name
                                ? Colors.white
                                : Colors.transparent,
                            border: Border.all(
                                color: _selectedFolder == name
                                    ? Colors.white
                                    : Colors.white38),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.folder,
                                  size: 13, color: Colors.white54),
                              const SizedBox(width: 4),
                              Text(name,
                                  style: TextStyle(
                                      color: _selectedFolder == name
                                          ? Colors.black
                                          : Colors.white54,
                                      fontSize: 12)),
                            ],
                          ),
                        ),
                      )),
                ],
              ),
              const SizedBox(height: 8),
            ],
            TextField(
              controller: _folderCtrl,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: S.of(context).newFolderHint,
                hintStyle: const TextStyle(
                    color: Colors.white24, fontSize: 12),
                filled: true,
                fillColor: Colors.white.withOpacity(0.07),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (v) {
                if (v.isNotEmpty) setState(() => _selectedFolder = null);
              },
            ),
            const SizedBox(height: 16),

            // ── Switches ──
            _switchRow(S.of(context).pinToThisFloor, _isPinned, Colors.blueAccent,
                (v) => setState(() => _isPinned = v)),
            _switchRow(S.of(context).mindfulDelayLabel, _mindfulDelay, Colors.tealAccent,
                (v) => setState(() => _mindfulDelay = v)),
            _switchRow(S.of(context).notificationBatchLabel, _batchEnabled, Colors.purpleAccent,
                (v) => setState(() => _batchEnabled = v)),
            _switchRow(S.of(context).markAsEmergency, _isEmergency, Colors.redAccent,
                (v) => setState(() => _isEmergency = v)),

            if (_isEmergency) ...[
              const SizedBox(height: 8),
              Text(S.of(context).emergencyDuration,
                  style: const TextStyle(
                      color: Colors.white70, fontSize: 13)),
              Row(
                children: [
                  Expanded(
                    child: Slider(
                      value: _emergencyMinutes.toDouble(),
                      min: 1,
                      max: 120,
                      divisions: 119,
                      activeColor: Colors.redAccent,
                      inactiveColor: Colors.white24,
                      label: S.of(context).minutesValue(_emergencyMinutes),
                      onChanged: (v) =>
                          setState(() => _emergencyMinutes = v.round()),
                    ),
                  ),
                  Text(S.of(context).minutesValue(_emergencyMinutes),
                      style: const TextStyle(
                          color: Colors.white, fontSize: 13)),
                ],
              ),
              _switchRow(S.of(context).emergencyOnOff, _emergencyActive, Colors.redAccent,
                  (v) => setState(() => _emergencyActive = v)),
            ],

            const SizedBox(height: 16),

            // ── Usage Count Floor Rules ──
            _UsageCountRulesSection(
              pkg: app.packageName,
              settingsService: _ss,
              maxFloors: _ss.maxFloors,
              undergroundFloors: _ss.undergroundFloors,
            ),

            const SizedBox(height: 32),

            // ── Save / Cancel buttons ──
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white54,
                    side: const BorderSide(color: Colors.white24),
                  ),
                  onPressed: () => Navigator.pop(context),
                  child: Text(S.of(context).actionCancel),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                  ),
                  onPressed: _save,
                  child: Text(S.of(context).actionSave),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _switchRow(String label, bool value, Color activeColor,
      ValueChanged<bool> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(
                  color: Colors.white70, fontSize: 13)),
          Switch(
            value: value,
            activeColor: activeColor,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

// ── Usage Count Floor Rules Section ──────────────────────────────────────────

class _UsageCountRulesSection extends StatefulWidget {
  final String pkg;
  final SettingsService settingsService;
  final int maxFloors;
  final int undergroundFloors;

  const _UsageCountRulesSection({
    required this.pkg,
    required this.settingsService,
    required this.maxFloors,
    required this.undergroundFloors,
  });

  @override
  State<_UsageCountRulesSection> createState() => _UsageCountRulesSectionState();
}

class _UsageCountRulesSectionState extends State<_UsageCountRulesSection> {
  SettingsService get _ss => widget.settingsService;

  Future<void> _addOrEditRule({Map<String, int>? existing, int? editIndex}) async {
    final rules = _ss.usageCountFloorRules(widget.pkg);
    int threshold = existing?['threshold'] ?? 5;
    int floor = existing?['floor'] ?? 2;
    final threshCtrl = TextEditingController(text: threshold.toString());

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInner) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          title: Text(existing == null ? S.of(ctx).ruleAdd : S.of(ctx).ruleEdit,
              style: const TextStyle(color: Colors.white, fontSize: 14)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(S.of(ctx).launchThresholdLabel, style: const TextStyle(color: Colors.white54, fontSize: 12)),
              const SizedBox(height: 4),
              TextField(
                controller: threshCtrl,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.07),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: BorderSide.none,
                  ),
                  suffixText: S.of(ctx).thresholdSuffix,
                  suffixStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                ),
                onChanged: (v) => threshold = int.tryParse(v) ?? threshold,
              ),
              const SizedBox(height: 12),
              Text(S.of(ctx).targetFloorLabel, style: const TextStyle(color: Colors.white54, fontSize: 12)),
              const SizedBox(height: 4),
              StatefulBuilder(
                builder: (_, setWrap) {
                  Widget chip(int f) {
                    final sel = floor == f;
                    return GestureDetector(
                      onTap: () => setWrap(() => floor = f),
                      child: Container(
                        width: 44,
                        height: 30,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: sel ? Colors.white : Colors.transparent,
                          border: Border.all(
                              color: sel ? Colors.white : Colors.white38),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(floorLabel(f),
                            style: TextStyle(
                                color:
                                    sel ? Colors.black : Colors.white54,
                                fontSize: 11)),
                      ),
                    );
                  }

                  return Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (int i = widget.undergroundFloors; i >= 1; i--)
                        chip(-i),
                      for (int i = 1; i <= widget.maxFloors; i++) chip(i),
                    ],
                  );
                },
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false),
                child: Text(S.of(ctx).actionCancel, style: const TextStyle(color: Colors.white54))),
            TextButton(
              onPressed: () {
                threshold = int.tryParse(threshCtrl.text) ?? threshold;
                Navigator.pop(ctx, true);
              },
              child: Text(S.of(ctx).actionSave, style: const TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;

    final updated = [...rules];
    final newRule = {'threshold': threshold, 'floor': floor};
    if (editIndex != null) {
      updated[editIndex] = newRule;
    } else {
      updated.add(newRule);
    }
    updated.sort((a, b) => a['threshold']!.compareTo(b['threshold']!));
    await _ss.setUsageCountFloorRules(widget.pkg, updated);
    setState(() {});
  }

  Future<void> _deleteRule(int index) async {
    final rules = [..._ss.usageCountFloorRules(widget.pkg)];
    rules.removeAt(index);
    await _ss.setUsageCountFloorRules(widget.pkg, rules);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final rules = _ss.usageCountFloorRules(widget.pkg);
    final todayCount = _ss.dailyLaunchCount(widget.pkg);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(s.usageCountFloorChange,
                style: const TextStyle(color: Colors.white70, fontSize: 13)),
            TextButton.icon(
              onPressed: () => _addOrEditRule(),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              icon: const Icon(Icons.add, color: Colors.tealAccent, size: 16),
              label: Text(s.actionAdd, style: const TextStyle(color: Colors.tealAccent, fontSize: 12)),
            ),
          ],
        ),
        Text(s.todayLaunchCount(todayCount),
            style: const TextStyle(color: Colors.white38, fontSize: 11)),
        const SizedBox(height: 4),
        if (rules.isEmpty)
          Text(s.noRules, style: const TextStyle(color: Colors.white24, fontSize: 12))
        else
          ...rules.asMap().entries.map((e) {
            final i = e.key;
            final rule = e.value;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      s.thresholdRule(rule['threshold']!, floorLabel(rule['floor']!)),
                      style: const TextStyle(color: Colors.white60, fontSize: 12),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => _addOrEditRule(existing: rule, editIndex: i),
                    child: const Icon(Icons.edit, color: Colors.white38, size: 16),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => _deleteRule(i),
                    child: const Icon(Icons.delete, color: Colors.redAccent, size: 16),
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }
}

// ── Emergency per-app caps screen ───────────────────────────────────────────

class _EmergencyPerAppCapsScreen extends StatefulWidget {
  final SettingsService settingsService;
  final List<AppConfig> allApps;
  const _EmergencyPerAppCapsScreen({
    required this.settingsService,
    required this.allApps,
  });
  @override
  State<_EmergencyPerAppCapsScreen> createState() =>
      _EmergencyPerAppCapsScreenState();
}

class _EmergencyPerAppCapsScreenState
    extends State<_EmergencyPerAppCapsScreen> {
  SettingsService get _ss => widget.settingsService;

  String _displayName(AppConfig app) =>
      (app.customName?.isNotEmpty == true) ? app.customName! : app.appName;

  Future<void> _editCap(AppConfig app) async {
    final cap = _ss.emergencyCapForApp(app.packageName);
    final result = await _showCapDialogStandalone(
        context, S.of(context).appLimitTitle(_displayName(app)),
        (cap?['count'] as num?)?.toInt() ?? 0,
        (cap?['period'] as String?) ?? 'daily');
    if (result == null) return;
    await _ss.setEmergencyCapForApp(app.packageName, result.$1, result.$2);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final registered = _ss.getEmergencyApps();
    final apps = widget.allApps
        .where((a) => registered.contains(a.packageName))
        .toList()
      ..sort((a, b) =>
          _displayName(a).toLowerCase().compareTo(_displayName(b).toLowerCase()));
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0D0D),
        foregroundColor: Colors.white,
        title: Text(s.emergencyPerAppLimitTitle,
            style: const TextStyle(color: Colors.white, fontSize: 16)),
      ),
      body: apps.isEmpty
          ? Center(
              child: Text(s.noEmergencyRegistered,
                  style: const TextStyle(color: Colors.white54, fontSize: 13)),
            )
          : ListView.separated(
              itemCount: apps.length,
              separatorBuilder: (_, __) => const Divider(
                  height: 1, color: Colors.white12, indent: 16, endIndent: 16),
              itemBuilder: (_, i) {
                final app = apps[i];
                final cap = _ss.emergencyCapForApp(app.packageName);
                final summary = cap == null
                    ? s.notSetUnlimited
                    : _ss.capSummary(cap);
                return ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  title: Text(_displayName(app),
                      style: const TextStyle(color: Colors.white, fontSize: 14)),
                  subtitle: Text(summary,
                      style:
                          const TextStyle(color: Colors.white54, fontSize: 12)),
                  trailing: cap == null
                      ? const Icon(Icons.chevron_right,
                          color: Colors.white24, size: 18)
                      : IconButton(
                          icon: const Icon(Icons.close,
                              color: Colors.redAccent, size: 18),
                          onPressed: () async {
                            await _ss.setEmergencyCapForApp(
                                app.packageName, 0, 'daily');
                            if (mounted) setState(() {});
                          },
                        ),
                  onTap: () => _editCap(app),
                );
              },
            ),
    );
  }
}

// ── Emergency folder caps screen ───────────────────────────────────────────

class _EmergencyFolderCapsScreen extends StatefulWidget {
  final SettingsService settingsService;
  final List<AppConfig> allApps;
  const _EmergencyFolderCapsScreen({
    required this.settingsService,
    required this.allApps,
  });
  @override
  State<_EmergencyFolderCapsScreen> createState() =>
      _EmergencyFolderCapsScreenState();
}

class _EmergencyFolderCapsScreenState
    extends State<_EmergencyFolderCapsScreen> {
  SettingsService get _ss => widget.settingsService;

  String _displayName(AppConfig app) =>
      (app.customName?.isNotEmpty == true) ? app.customName! : app.appName;

  Future<void> _editFolder({Map<String, dynamic>? existing, int? index}) async {
    final isEdit = existing != null;
    final nameCtrl = TextEditingController(
        text: existing?['name'] as String? ?? '');
    final selected = <String>{
      ...(existing?['apps'] as List?)?.map((e) => e.toString()) ??
          const <String>[]
    };
    int count = (existing?['count'] as num?)?.toInt() ?? 0;
    String period = existing?['period'] as String? ?? 'daily';
    final countCtrl =
        TextEditingController(text: count > 0 ? count.toString() : '');

    final registered = _ss.getEmergencyApps();
    final candidates = widget.allApps
        .where((a) => registered.contains(a.packageName))
        .toList()
      ..sort((a, b) =>
          _displayName(a).toLowerCase().compareTo(_displayName(b).toLowerCase()));

    final s0 = S.of(context);
    final periods = <(String, String)>[
      ('hourly', s0.periodHourly),
      ('daily', s0.periodDaily),
      ('weekly', s0.periodWeekly),
      ('monthly', s0.periodMonthly),
      ('yearly', s0.periodYearly),
    ];

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInner) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          title: Text(isEdit ? S.of(ctx).folderEdit : S.of(ctx).folderAdd,
              style: const TextStyle(color: Colors.white, fontSize: 14)),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(S.of(ctx).nameLabel,
                      style: const TextStyle(color: Colors.white54, fontSize: 12)),
                  const SizedBox(height: 4),
                  TextField(
                    controller: nameCtrl,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: S.of(ctx).nameHintSns,
                      hintStyle: const TextStyle(color: Colors.white38),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.07),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(4),
                          borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(S.of(ctx).countWithEmptyUnlimitedHint,
                      style: const TextStyle(color: Colors.white54, fontSize: 12)),
                  const SizedBox(height: 4),
                  TextField(
                    controller: countCtrl,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: S.of(ctx).unlimited,
                      hintStyle: const TextStyle(color: Colors.white38),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.07),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(4),
                          borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(S.of(ctx).periodLabel,
                      style: const TextStyle(color: Colors.white54, fontSize: 12)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: periods.map((p) {
                      final sel = period == p.$1;
                      return GestureDetector(
                        onTap: () => setInner(() => period = p.$1),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: sel ? Colors.white : Colors.transparent,
                            border: Border.all(
                                color:
                                    sel ? Colors.white : Colors.white38),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(p.$2,
                              style: TextStyle(
                                  color: sel
                                      ? Colors.black
                                      : Colors.white70,
                                  fontSize: 11)),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),
                  Text(S.of(ctx).targetApps,
                      style: const TextStyle(color: Colors.white54, fontSize: 12)),
                  const SizedBox(height: 4),
                  if (candidates.isEmpty)
                    Text(S.of(ctx).noEmergencyRegistered,
                        style: const TextStyle(
                            color: Colors.white38, fontSize: 12))
                  else
                    SizedBox(
                      height: 220,
                      child: ListView.builder(
                        shrinkWrap: true,
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
                ],
              ),
            ),
          ),
          actions: [
            if (isEdit)
              TextButton(
                onPressed: () =>
                    Navigator.pop(ctx, <String, dynamic>{'__delete': true}),
                child: Text(S.of(ctx).actionDelete,
                    style: const TextStyle(color: Colors.redAccent)),
              ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(S.of(ctx).actionCancel,
                  style: const TextStyle(color: Colors.white54)),
            ),
            TextButton(
              onPressed: () {
                final name = nameCtrl.text.trim();
                if (name.isEmpty) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                      SnackBar(content: Text(S.of(ctx).pleaseEnterName)));
                  return;
                }
                final c = int.tryParse(countCtrl.text) ?? 0;
                Navigator.pop(ctx, {
                  'name': name,
                  'apps': selected.toList(),
                  'count': c < 0 ? 0 : c,
                  'period': period,
                });
              },
              child: Text(S.of(ctx).actionSave,
                  style: const TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
    if (result == null) return;
    final folders = _ss.emergencyCapFolders;
    if (result['__delete'] == true && index != null) {
      folders.removeAt(index);
    } else if (isEdit && index != null) {
      folders[index] = result;
    } else {
      folders.add(result);
    }
    await _ss.setEmergencyCapFolders(folders);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final folders = _ss.emergencyCapFolders;
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0D0D),
        foregroundColor: Colors.white,
        title: Text(s.emergencyFolderLimitTitle,
            style: const TextStyle(color: Colors.white, fontSize: 16)),
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: Colors.white),
            onPressed: () => _editFolder(),
          ),
        ],
      ),
      body: folders.isEmpty
          ? Center(
              child: Text(s.folderAddTopRightHint,
                  style: const TextStyle(color: Colors.white54, fontSize: 13)),
            )
          : ListView.separated(
              itemCount: folders.length,
              separatorBuilder: (_, __) => const Divider(
                  height: 1, color: Colors.white12, indent: 16, endIndent: 16),
              itemBuilder: (_, i) {
                final folder = folders[i];
                final apps = (folder['apps'] as List?)
                        ?.map((e) => e.toString())
                        .toList() ??
                    const [];
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 4),
                  title: Text(folder['name'] as String? ?? s.folderLabel,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 14)),
                  subtitle: Text(
                      s.folderAppSubtitle(_ss.capSummary(folder), apps.length),
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 12)),
                  trailing: const Icon(Icons.chevron_right,
                      color: Colors.white24, size: 18),
                  onTap: () => _editFolder(existing: folder, index: i),
                );
              },
            ),
    );
  }
}

/// Standalone helper used by both the per-app caps screen and the folder
/// caps screen since they don't have access to the `_SettingsScreenState`
/// extension's `_showCapDialog`.
Future<(int, String)?> _showCapDialogStandalone(
  BuildContext context,
  String title,
  int initialCount,
  String initialPeriod,
) async {
  String period = initialPeriod;
  final s0 = S.of(context);
  final periods = <(String, String)>[
    ('hourly', s0.periodHourly),
    ('daily', s0.periodDaily),
    ('weekly', s0.periodWeekly),
    ('monthly', s0.periodMonthly),
    ('yearly', s0.periodYearly),
  ];
  final ctrl = TextEditingController(
      text: initialCount > 0 ? initialCount.toString() : '');
  return showDialog<(int, String)>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setInner) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: Text(title,
            style: const TextStyle(color: Colors.white, fontSize: 14)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(S.of(ctx).countWithEmptyUnlimitedHint,
                style: const TextStyle(color: Colors.white54, fontSize: 12)),
            const SizedBox(height: 6),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                hintText: S.of(ctx).unlimited,
                hintStyle: const TextStyle(color: Colors.white38),
                filled: true,
                fillColor: Colors.white.withOpacity(0.07),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 12),
            Text(S.of(ctx).periodLabel,
                style: const TextStyle(color: Colors.white54, fontSize: 12)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: periods.map((p) {
                final sel = period == p.$1;
                return GestureDetector(
                  onTap: () => setInner(() => period = p.$1),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: sel ? Colors.white : Colors.transparent,
                      border: Border.all(
                          color: sel ? Colors.white : Colors.white38),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(p.$2,
                        style: TextStyle(
                            color: sel ? Colors.black : Colors.white70,
                            fontSize: 11)),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(S.of(ctx).actionCancel,
                style: const TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () {
              final c = int.tryParse(ctrl.text) ?? 0;
              Navigator.pop(ctx, (c < 0 ? 0 : c, period));
            },
            child: Text(S.of(ctx).actionSave, style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    ),
  );
}

