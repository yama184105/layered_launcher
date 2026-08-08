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
    final emgSummary = s.emergencySummary(
      limitLabels[current] ?? current,
      emgAppCount,
    );

    return [
      _settingRow('${s.appList} / ${s.modesTitle}', '', () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                AppListAndModesScreen(appService: _as, settingsService: ss),
          ),
        ).then((_) => _load());
      }),
      _rowDivider,
      _expandableRow(
        key: 'appmgmt_emergency',
        title: s.emergencyMode,
        summary: emgSummary,
        children: _emergencyChildren(ss, current, limitLabels),
      ),
    ];
  }

  /// Used by screentime section: lets the user pick which apps show their
  /// "last launched" relative time on the home/floor list. Requires the
  /// system "Usage access" permission, which we prompt for if missing.
  Future<void> showLastUsedDisplayPicker() async {
    final granted = await _native.isUsageStatsPermissionGranted();
    if (!granted) {
      if (!mounted) return;
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          title: Text(
            S.of(ctx).usageStatsAccessRequired,
            style: const TextStyle(color: Colors.white, fontSize: 14),
          ),
          content: Text(
            S.of(ctx).usageStatsAccessExplanation,
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
                S.of(ctx).openSettings,
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      );
      if (go == true) await _native.openUsageStatsSettings();
      return;
    }
    await _showLockAppSelector(
      'lastUsedDisplayApps',
      _ss.lastUsedDisplayApps,
      (v) => _ss.setLastUsedDisplayApps(v),
    );
    setState(() {});
  }

  List<Widget> _emergencyChildren(
    SettingsService ss,
    String current,
    Map<String, String> limitLabels,
  ) {
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
          final picked = await _pickLockApps(ss.getEmergencyApps().toSet());
          if (picked == null || !mounted) return;
          if (await _gateEmergencyChange(
            ReservationKinds.emergencyApps,
            {'apps': picked.toList()},
            S.of(context).emergencyAppsRegister,
          )) {
            await ss.setEmergencyApps(picked.toList());
          }
          if (mounted) setState(() {});
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
            title: Text(
              S.of(ctx).emergencyFontColorTitle,
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: colors
                  .map(
                    (c) => ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: Color(c.$1),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white24),
                        ),
                      ),
                      title: Text(
                        c.$2,
                        style: TextStyle(color: Color(c.$1), fontSize: 13),
                      ),
                      trailing: ss.emergencyAppFontColor == c.$1
                          ? const Icon(
                              Icons.check,
                              color: Colors.tealAccent,
                              size: 18,
                            )
                          : null,
                      onTap: () => Navigator.pop(ctx, c.$1),
                    ),
                  )
                  .toList(),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(
                  S.of(ctx).actionCancel,
                  style: const TextStyle(color: Colors.white54),
                ),
              ),
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
        title: Text(
          s.emergencySectionIndex,
          style: const TextStyle(color: Colors.white, fontSize: 14),
        ),
        subtitle: Text(
          s.emergencySectionIndexDesc,
          style: const TextStyle(color: Colors.white54, fontSize: 12),
        ),
        activeColor: Colors.tealAccent,
        value: ss.emergencyAppShowIndex,
        onChanged: (v) async {
          await ss.setEmergencyAppShowIndex(v);
          setState(() {});
        },
      ),
    ];
  }

  // ── Emergency-mode usage limits ─────────────────────────────

  String _emgLimitsSummary(SettingsService ss) {
    final s = S.of(context);
    final all = ss.capSummary(s, ss.emergencyCapAll);
    final pick = ss.capSummary(s, ss.emergencyCapPick);
    final regGlobal = ss.capSummary(s, ss.emergencyCapRegisteredGlobal);
    return s.emergencyLimitsSummary(all, pick, regGlobal);
  }

  /// 緊急使用の上限設定の変更をストリクト「緊急使用設定ロック」で
  /// ゲートする。戻り値 true = そのまま保存してよい。
  Future<bool> _gateEmergencyCap(
      String target, int count, String period, String label) =>
      _gateEmergencyChange(
        ReservationKinds.emergencyCap,
        {'key': target, 'count': count, 'period': period},
        label,
      );

  /// 緊急モード関連の変更に共通のゲート。
  Future<bool> _gateEmergencyChange(
    String kind,
    Map<String, dynamic> data,
    String label,
  ) async {
    final result = await requestStrictAction(
      context,
      _ss,
      key: 'emergency',
      blockedMessage: S.of(context).emergencyLimitLocked,
      reservationKind: kind,
      reservationData: data,
      reservationLabel: label,
    );
    if (result == StrictGateResult.reserved && mounted) setState(() {});
    return result == StrictGateResult.allowed;
  }

  List<Widget> _emgLimitChildren(SettingsService ss) {
    final s = S.of(context);
    return [
      _settingRow(
        s.emergencyShowAllOn1F,
        ss.capSummary(s, ss.emergencyCapAll),
        () async {
          final cap = ss.emergencyCapAll;
          final result = await _showCapDialog(
            s.emergencyShowAllOn1FLimit,
            (cap['count'] as num?)?.toInt() ?? 0,
            cap['period'] as String? ?? 'weekly',
          );
          if (result == null || !mounted) return;
          if (!await _gateEmergencyCap(
              'all', result.$1, result.$2, s.emergencyShowAllOn1FLimit)) {
            return;
          }
          await ss.setEmergencyCapAll(result.$1, result.$2);
          setState(() {});
        },
      ),
      _rowDivider,
      _settingRow(
        s.emergencyAppListPick,
        ss.capSummary(s, ss.emergencyCapPick),
        () async {
          final cap = ss.emergencyCapPick;
          final result = await _showCapDialog(
            s.emergencyAppListPickLimit,
            (cap['count'] as num?)?.toInt() ?? 0,
            cap['period'] as String? ?? 'daily',
          );
          if (result == null || !mounted) return;
          if (!await _gateEmergencyCap(
              'pick', result.$1, result.$2, s.emergencyAppListPickLimit)) {
            return;
          }
          await ss.setEmergencyCapPick(result.$1, result.$2);
          setState(() {});
        },
      ),
      _rowDivider,
      _expandableRow(
        key: 'emg_limits_registered',
        title: s.emergencyRegistered,
        summary: s.emergencyRegisteredSummary(
          ss.capSummary(s, ss.emergencyCapRegisteredGlobal),
          _emgPerAppCount(ss),
          ss.emergencyCapFolders.length,
        ),
        children: [
          _settingRow(
            s.emergencyGlobalLimit,
            ss.capSummary(s, ss.emergencyCapRegisteredGlobal),
            () async {
              final cap = ss.emergencyCapRegisteredGlobal;
              final result = await _showCapDialog(
                s.emergencyRegisteredGlobalLimit,
                (cap['count'] as num?)?.toInt() ?? 0,
                cap['period'] as String? ?? 'daily',
              );
              if (result == null || !mounted) return;
              if (!await _gateEmergencyCap('regGlobal', result.$1, result.$2,
                  s.emergencyRegisteredGlobalLimit)) {
                return;
              }
              await ss.setEmergencyCapRegisteredGlobal(result.$1, result.$2);
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
    String title,
    int initialCount,
    String initialPeriod,
  ) async {
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
      text: initialCount > 0 ? initialCount.toString() : '',
    );
    return showDialog<(int, String)>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInner) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          title: Text(
            title,
            style: const TextStyle(color: Colors.white, fontSize: 14),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                S.of(ctx).countWithEmptyUnlimitedHint,
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: ctrl,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  hintText: S.of(ctx).unlimited,
                  hintStyle: const TextStyle(color: Colors.white38),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.07),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                S.of(ctx).periodLabel,
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
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
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: sel ? Colors.white : Colors.transparent,
                        border: Border.all(
                          color: sel ? Colors.white : Colors.white38,
                        ),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        p.$2,
                        style: TextStyle(
                          color: sel ? Colors.black : Colors.white70,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
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
              onPressed: () {
                final c = int.tryParse(ctrl.text) ?? 0;
                Navigator.pop(ctx, (c < 0 ? 0 : c, period));
              },
              child: Text(
                S.of(ctx).actionSave,
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showPerAppCapsScreen(SettingsService ss) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            _EmergencyPerAppCapsScreen(settingsService: ss, allApps: _apps),
      ),
    ).then((_) => setState(() {}));
  }

  void _showFolderCapsScreen(SettingsService ss) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            _EmergencyFolderCapsScreen(settingsService: ss, allApps: _apps),
      ),
    ).then((_) => setState(() {}));
  }

}

// ── App List Screen ─────────────────────────────────────────

class AppListAndModesScreen extends StatefulWidget {
  final AppService appService;
  final SettingsService settingsService;
  final List<AppConfig>? initialApps;

  const AppListAndModesScreen({
    super.key,
    required this.appService,
    required this.settingsService,
    this.initialApps,
  });

  @override
  State<AppListAndModesScreen> createState() => _AppListScreenState();
}

class _AppListScreenState extends State<AppListAndModesScreen> {
  static List<AppConfig> _cachedApps = [];

  List<AppConfig> _apps = [];
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';
  bool _selectionMode = false;
  final Set<String> _selectedPkgs = {};
  int? _filterFloor; // null = all floors
  int _tabIndex = 0; // 0 = app list, 1 = modes

  AppService get _as => widget.appService;
  SettingsService get _ss => widget.settingsService;

  @override
  void initState() {
    super.initState();
    _apps = List<AppConfig>.from(
      _cachedApps.isNotEmpty ? _cachedApps : widget.initialApps ?? const [],
    );
    _searchCtrl.addListener(
      () => setState(() => _searchQuery = _searchCtrl.text),
    );
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── 複数選択 → モード操作 ───────────────────────────────────────────

  List<AppConfig> get _selectedApps =>
      _apps.where((a) => _selectedPkgs.contains(a.packageName)).toList();

  void _endSelection() {
    setState(() {
      _selectionMode = false;
      _selectedPkgs.clear();
    });
  }

  /// 選択したアプリのモードをまとめて切り替える。
  Future<void> _bulkSwitchMode() async {
    final pkgs = _selectedPkgs.toList();
    if (pkgs.isEmpty) return;
    final modes = pkgs.map(_ss.appMode).toSet();
    final anyTemp = _selectedApps.any((a) => tempStateOf(_ss, a) != null);
    final picked = await showModeSelectSheet(
      context,
      title: S.of(context).modeSwitchCountTitle(pkgs.length),
      currentMode: modes.length == 1 ? modes.first : null,
      showRelease: modes.any((m) => m != 'normal'),
      showTempRelease: anyTemp,
    );
    if (picked == null || !mounted) return;

    switch (picked) {
      case kModeTemp:
        if (!await _bulkApplyTempMove(pkgs)) return;
        break;
      case kModeActionTempRelease:
        await clearTempMove(_as, _ss, _selectedApps);
        break;
      case kModeActionRelease:
        await releaseAppsWithSchedulePrompt(context, _ss, _apps, pkgs);
        break;
      case 'normal':
        // フロア確定まで解除しない。キャンセルすれば元のモードのまま。
        await switchToNormalWithFloor(context, _ss, _as, _apps, pkgs);
        break;
      case kModeCustom:
        // カスタム＝スケジュール。既存スケジュールがあれば「既存/新規」を選ぶ
        if (!mounted) return;
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
        break;
    }
    if (!mounted) return;
    _endSelection();
    await _load();
  }

  Future<void> _bulkTempMove() async {
    final pkgs = _selectedPkgs.toList();
    if (pkgs.isEmpty) return;
    if (!await _bulkApplyTempMove(pkgs) || !mounted) return;
    _endSelection();
    await _load();
  }

  Future<bool> _bulkApplyTempMove(List<String> pkgs) async {
    final apps = _apps.where((a) => pkgs.contains(a.packageName)).toList();
    if (apps.isEmpty) return false;
    final single = apps.length == 1 ? apps.first : null;
    final spec = await showTempMoveDialog(
      context,
      settingsService: _ss,
      title: single != null
          ? '${S.of(context).tempMoveTitle} — ${appLabelOf(single)}'
          : S.of(context).tempMoveCountTitle(apps.length),
      currentMode: single != null ? _ss.appMode(single.packageName) : null,
      currentFloor: single?.floor,
    );
    if (spec == null) return false;
    await applyTempMoveWithStrictGate(context, _ss, _as, apps, spec);
    return true;
  }

  Future<void> _load() async {
    final apps = await _as.getAllApps();
    if (!mounted) return;
    setState(() {
      _cachedApps = List<AppConfig>.from(apps);
      _apps = apps;
    });
  }

  String _displayName(AppConfig app) {
    final custom = app.customName?.trim();
    if (custom?.isNotEmpty == true) return custom!;
    final name = app.appName.trim();
    return name.isNotEmpty ? name : app.packageName;
  }

  List<AppConfig> get _filteredApps {
    var list = List<AppConfig>.from(_apps);
    if (_filterFloor != null) {
      list = list.where((a) => a.floor == _filterFloor).toList();
    }
    list.sort((a, b) => _displayName(a).compareTo(_displayName(b)));
    if (_searchQuery.isEmpty) return list;
    final q = _searchQuery.toLowerCase();
    return list
        .where(
          (a) =>
              _displayName(a).toLowerCase().contains(q) ||
              a.appName.toLowerCase().contains(q),
        )
        .toList();
  }

  String _modeNameOf(BuildContext context, String mode) {
    final s = S.of(context);
    switch (mode) {
      case 'custom':
        return s.customSection;
      case kModeTemp:
        return s.modeTemp;
      case 'schedule':
        return s.modeScheduleName;
      case 'usageCount':
        return s.modeUsageCount;
      case 'usageTime':
        return s.modeUsageTime;
      default:
        return s.modeNormal;
    }
  }

  String _modeDescOf(BuildContext context, String mode) {
    final s = S.of(context);
    switch (mode) {
      case 'custom':
        return s.modeCustomDesc;
      case kModeTemp:
        return s.modeTempDesc;
      case 'schedule':
        return s.modeScheduleDesc;
      case 'usageCount':
        return s.modeUsageCountDesc;
      case 'usageTime':
        return s.modeUsageTimeDesc;
      default:
        return s.modeNormalDesc;
    }
  }

  IconData _modeIcon(String mode) {
    switch (mode) {
      case 'custom':
        return Icons.tune;
      case kModeTemp:
        return Icons.timelapse;
      case 'schedule':
        return Icons.schedule;
      case 'usageCount':
        return Icons.tag;
      case 'usageTime':
        return Icons.hourglass_bottom;
      default:
        return Icons.apps;
    }
  }

  int _countInMode(String mode) => _apps.where((a) {
    if (mode == kModeTemp) return tempStateOf(_ss, a) != null;
    final current = _ss.appMode(a.packageName);
    return mode == 'custom' ? current != 'normal' : current == mode;
  }).length;

  Widget _buildTopTabs(S s) {
    Widget tab(int index, String label, IconData icon) {
      final selected = _tabIndex == index;
      return Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () => setState(() {
            _tabIndex = index;
            _selectionMode = false;
            _selectedPkgs.clear();
          }),
          child: Container(
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? Colors.white : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: selected ? Colors.black : Colors.white54,
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    color: selected ? Colors.black : Colors.white70,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 6),
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          tab(0, s.appList, Icons.list_alt),
          tab(1, s.modesTitle, Icons.tune),
        ],
      ),
    );
  }

  Widget _buildModesTab(S s) {
    final modes = ['normal', 'custom', kModeTemp];
    return ListView.separated(
      itemCount: modes.length,
      separatorBuilder: (_, __) =>
          const Divider(height: 1, color: Colors.white12),
      itemBuilder: (_, i) {
        final mode = modes[i];
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 8,
          ),
          leading: Icon(_modeIcon(mode), color: Colors.white54, size: 22),
          title: Text(
            _modeNameOf(context, mode),
            style: const TextStyle(color: Colors.white, fontSize: 15),
          ),
          subtitle: Text(
            _modeDescOf(context, mode),
            style: const TextStyle(color: Colors.white38, fontSize: 11),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                s.groupAppsCount(_countInMode(mode)),
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right, color: Colors.white24, size: 18),
            ],
          ),
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ModeDetailScreen(
                  mode: mode,
                  appService: _as,
                  settingsService: _ss,
                  initialApps: _apps,
                ),
              ),
            );
            if (mounted) _load();
          },
        );
      },
    );
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
          // Underground floors (deepest first 遶翫・BnF .. B1F).
          for (int i = underFloors; i >= 1; i--) _floorChip(-i, floorLabel(-i)),
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
        child: Text(
          label,
          style: TextStyle(
            color: sel ? Colors.black : Colors.white70,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  Widget _buildAppTile(AppConfig app) {
    final now = DateTime.now();
    final activeEmg =
        app.isEmergency &&
        app.emergencyUntil != null &&
        app.emergencyUntil!.isAfter(now);
    // 予約済みのフロア移動があれば、その行き先を「変更予定」として出す
    final reserved = _ss.strictReservationFor(
      ReservationKinds.floorMove,
      pkg: app.packageName,
    );
    final pending = (reserved?.data['floor'] as num?)?.toInt();
    final dFloor = pending ?? app.floor;
    final hasPending = pending != null;
    final folder = app.folderName?.isNotEmpty == true ? app.folderName! : null;
    final isBatch = _ss.batchApps.contains(app.packageName);
    final isSelected = _selectedPkgs.contains(app.packageName);
    final isBlocked = _ss.blockTypeForApp(app.packageName) != 'none';
    final mode = _ss.appMode(app.packageName);

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
          Text(
            _modeNameOf(context, mode),
            style: const TextStyle(color: Colors.tealAccent, fontSize: 11),
          ),
          if (hasPending)
            Text(
              S.of(context).pendingChange,
              style: const TextStyle(color: Colors.amber, fontSize: 11),
            ),
          if (folder != null)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.folder, color: Colors.white54, size: 13),
                const SizedBox(width: 2),
                Text(
                  folder,
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
              ],
            ),
          if (app.isPinned)
            const Icon(Icons.push_pin, color: Colors.blueAccent, size: 13),
          // 全体スイッチが OFF のときはディレイが掛からないのでバッジも出さない
          if (app.mindfulDelay && _ss.mindfulDelayEnabled)
            Text(
              S.of(context).delayBadge,
              style: const TextStyle(color: Colors.tealAccent, fontSize: 11),
            ),
          if (isBatch)
            Text(
              S.of(context).batchBadge,
              style: const TextStyle(color: Colors.purpleAccent, fontSize: 11),
            ),
          if (isBlocked)
            Text(
              S.of(context).blockBadge,
              style: const TextStyle(color: Colors.redAccent, fontSize: 11),
            ),
          if (activeEmg)
            Text(
              S.of(context).emergencyActiveBadge,
              style: const TextStyle(color: Colors.redAccent, fontSize: 11),
            ),
          if (_ss.isEmergencyApp(app.packageName) && !activeEmg)
            Text(
              S.of(context).emergencyDesignatedBadge,
              style: const TextStyle(color: Colors.white24, fontSize: 11),
            ),
        ],
      ),
      selected: isSelected,
      selectedTileColor: Colors.white.withValues(alpha: 0.05),
      trailing: _selectionMode
          ? null
          : const Icon(Icons.chevron_right, color: Colors.white38, size: 18),
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
            ? Text(
                s.selectedCount(_selectedPkgs.length),
                style: const TextStyle(color: Colors.white),
              )
            : Text(
                '${s.appList} / ${s.modesTitle}',
                style: const TextStyle(color: Colors.white),
              ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: _selectionMode
            ? [
                TextButton(
                  onPressed: () => setState(() {
                    _selectedPkgs.addAll(filtered.map((a) => a.packageName));
                  }),
                  child: Text(
                    s.actionSelectAll,
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() {
                    _selectionMode = false;
                    _selectedPkgs.clear();
                  }),
                  child: Text(
                    s.actionDeselectAll,
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ),
              ]
            : null,
      ),
      body: Column(
        children: [
          _buildTopTabs(s),
          if (_tabIndex == 1)
            Expanded(child: _buildModesTab(s))
          else ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: TextField(
                controller: _searchCtrl,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  hintText: s.appSearchHint,
                  hintStyle: const TextStyle(
                    color: Colors.white38,
                    fontSize: 13,
                  ),
                  prefixIcon: const Icon(
                    Icons.search,
                    color: Colors.white38,
                    size: 18,
                  ),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(
                            Icons.clear,
                            color: Colors.white38,
                            size: 18,
                          ),
                          onPressed: _searchCtrl.clear,
                        )
                      : null,
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.07),
                  contentPadding: const EdgeInsets.symmetric(vertical: 6),
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
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
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
                      // Mode switch (ノーマル/カスタム/一時的/解除)
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white12,
                          foregroundColor: Colors.white,
                        ),
                        icon: const Icon(Icons.layers, size: 16),
                        label: Text(
                          s.selectionMode,
                          style: const TextStyle(fontSize: 12),
                        ),
                        onPressed: _bulkSwitchMode,
                      ),
                      // Temporary move
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white12,
                          foregroundColor: Colors.orangeAccent,
                        ),
                        icon: const Icon(Icons.timelapse, size: 16),
                        label: Text(
                          s.selectionTemp,
                          style: const TextStyle(fontSize: 12),
                        ),
                        onPressed: _bulkTempMove,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

// ── App Detail Screen ───────────────────────────────────────

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
  late bool _isPinned;

  late TextEditingController _customNameCtrl;
  late TextEditingController _folderCtrl;
  String? _selectedFolder;

  SettingsService get _ss => widget.settingsService;
  AppService get _as => widget.appService;


  @override
  void initState() {
    super.initState();
    final app = widget.app;
    _selectedFloor = (_ss
                .strictReservationFor(
                  ReservationKinds.floorMove,
                  pkg: app.packageName,
                )
                ?.data['floor'] as num?)
            ?.toInt() ??
        app.floor;
    _isPinned = app.isPinned;
    _customNameCtrl = TextEditingController(text: app.customName ?? '');
    _folderCtrl = TextEditingController(text: app.folderName ?? '');
    _selectedFolder = app.folderName?.isNotEmpty == true
        ? app.folderName
        : null;
  }

  @override
  void dispose() {
    _customNameCtrl.dispose();
    _folderCtrl.dispose();
    super.dispose();
  }

  // Collect existing folders from all apps on same floor
  List<String> get _existingFolders {
    return widget.allApps
        .where(
          (a) =>
              a.floor == _selectedFloor &&
              a.folderName != null &&
              a.folderName!.isNotEmpty,
        )
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
        child: Text(
          floorLabel(f),
          style: TextStyle(
            color: sel ? Colors.black : Colors.white54,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  /// フロア移動が完全ブロックされているか（タイマー/予約なら操作は可能）。
  bool get _lockBlocked =>
      _ss.isFloorMoveLocked(widget.app.packageName) &&
      _ss.strictSubType('floorMove') == 'block';

  Widget _buildFloorPickerSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          S.of(context).floorLabel,
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
        if (_lockBlocked)
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 2),
            child: Text(
              S.of(context).cooldownChangeBlocked,
              style: const TextStyle(color: Colors.amber, fontSize: 12),
            ),
          )
        else ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (int i = _ss.undergroundFloors; i >= 1; i--)
                _floorPickerChip(-i),
              for (int i = 1; i <= _ss.maxFloors; i++) _floorPickerChip(i),
            ],
          ),
        ],
      ],
    );
  }

  String _modeNameOf(String mode) {
    final s = S.of(context);
    switch (mode) {
      case 'custom':
        return s.customSection;
      case 'schedule':
        return s.modeScheduleName;
      case 'usageCount':
        return s.modeUsageCount;
      case 'usageTime':
        return s.modeUsageTime;
      default:
        return s.modeNormal;
    }
  }

  String _modeSummary(String mode) {
    final s = S.of(context);
    switch (mode) {
      case 'custom':
        return '${s.modeScheduleName} / ${s.modeUsageCount} / ${s.modeUsageTime}';
      case 'schedule':
        return s.modeScheduleDesc;
      case 'usageCount':
        return s.modeUsageCountDesc;
      case 'usageTime':
        return s.modeUsageTimeDesc;
      default:
        return s.modeNormalDesc;
    }
  }

  String _scheduleTargetLabel(Map data) {
    final type = data['type'] as String? ?? 'fixed';
    if (type == 'keep') return S.of(context).keepPosition;
    if (type == 'random') {
      final floors = (data['floors'] as List?) ?? const [];
      return S.of(context).scheduleArrowRandom(floors.length);
    }
    if (type == 'usageCount' || type == 'usageTime') {
      final rules =
          ((type == 'usageTime' ? data['timeRules'] : data['countRules'])
                  as List?)
              ?.whereType<Map>()
              .toList() ??
          const <Map>[];
      if (rules.isEmpty) return S.of(context).notSet;
      final normalized = [
        for (final r in rules)
          {
            'threshold': (r['threshold'] as num).toInt(),
            'floor': (r['floor'] as num).toInt(),
          },
      ];
      return usageRangeLabels(
        S.of(context),
        normalized,
        isTime: type == 'usageTime',
      ).join(' / ');
    }
    final floor = (data['floor'] as num?)?.toInt();
    return floor == null ? S.of(context).notSet : floorLabel(floor);
  }

  String _fmtMinute(int minute) {
    final h = (minute ~/ 60) % 24;
    final m = minute % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

  String _modeConfigSummary(String mode) {
    final s = S.of(context);
    final pkg = widget.app.packageName;
    if (mode == 'custom') mode = _ss.appMode(pkg);
    if (mode == 'schedule') {
      final raw = _ss.autoMoveSchedule(pkg);
      if (raw.isEmpty) return s.notSet;
      final today = raw[DateTime.now().weekday.toString()];
      if (today is! Map) return s.notSet;
      final slots = (today['slots'] as List?) ?? const [];
      final def = today['default'];
      final parts = <String>[];
      if (def is Map) {
        parts.add('${s.defaultLabel}: ${_scheduleTargetLabel(def)}');
      }
      if (slots.isNotEmpty) {
        for (final slot in slots.whereType<Map>()) {
          final start = (slot['startMinute'] as num?)?.toInt() ?? 0;
          final end = (slot['endMinute'] as num?)?.toInt() ?? 1440;
          parts.add(
            '${_fmtMinute(start)}-${_fmtMinute(end)}: ${_scheduleTargetLabel(slot)}',
          );
        }
      }
      return parts.isEmpty ? s.notSet : parts.join(' / ');
    }
    if (mode == 'usageCount') {
      final rules = _ss.usageCountFloorRules(pkg);
      if (rules.isEmpty) return s.notSet;
      return usageRangeLabels(s, rules, isTime: false).join(' / ');
    }
    if (mode == 'usageTime') {
      final rules = _ss.usageTimeFloorRules(pkg);
      if (rules.isEmpty) return s.notSet;
      return usageRangeLabels(s, rules, isTime: true).join(' / ');
    }
    return floorLabel(_selectedFloor);
  }

  /// モード変更。ホームやモード画面と同じ共通シート（ノーマル /
  /// スケジュール / 使用回数 / 使用時間 / 一時的 / 解除）を出す。
  Future<void> _showModeSheet() async {
    final app = widget.app;
    final temp = tempStateOf(_ss, app);
    final current = _ss.appMode(app.packageName);
    final picked = await showModeSelectSheet(
      context,
      title: appLabelOf(app),
      currentMode: current,
      statusText: temp != null ? tempStateSummary(context, temp) : null,
      showRelease: current != 'normal',
      showTempRelease: temp != null,
    );
    if (picked == null || !mounted) return;
    switch (picked) {
      case kModeTemp:
        final spec = await showTempMoveDialog(
          context,
          settingsService: _ss,
          title: '${S.of(context).tempMoveTitle} — ${appLabelOf(app)}',
          currentMode: current,
          currentFloor: app.floor,
        );
        if (spec == null) return;
        await applyTempMoveWithStrictGate(
            context, _ss, widget.appService, [app], spec);
        break;
      case kModeActionTempRelease:
        await clearTempMove(widget.appService, _ss, [app]);
        break;
      case kModeActionRelease:
        await releaseAppsWithSchedulePrompt(
            context, _ss, widget.allApps, [app.packageName]);
        break;
      case 'normal':
        // フロア確定まで解除しない。キャンセルすれば元のモードのまま。
        await switchToNormalWithFloor(
          context,
          _ss,
          widget.appService,
          widget.allApps,
          [app.packageName],
          initialFloor: app.floor,
        );
        break;
      case kModeCustom:
        // カスタム＝スケジュール。既存スケジュールがあれば「既存/新規」を選ぶ
        final entry = await enterScheduleForApps(
          context,
          _ss,
          widget.allApps,
          [app.packageName],
        );
        if (entry == ScheduleEntryResult.createNew) {
          await _configureMode(kModeCustom);
        }
        break;
    }
    if (mounted) setState(() {});
  }

  /// スケジュール編集画面を直接開く（「編集」ボタン用。既存/新規の選択は
  /// しない — 既にそのアプリのスケジュールを直接いじる）。
  Future<void> _configureMode(String mode) async {
    final app = widget.app;
    if (mode == 'normal') {
      await _ss.releaseFromMode(app.packageName);
      if (mounted) setState(() {});
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AutoMoveScreen(
          settingsService: _ss,
          packageNames: [app.packageName],
          allApps: widget.allApps,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Widget _buildModeSection() {
    final mode = _ss.appMode(widget.app.packageName);
    final visibleMode = mode == 'normal' ? 'normal' : 'custom';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          S.of(context).modesTitle,
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
        const SizedBox(height: 6),
        Text(
          S.of(context).currentModeLabel(_modeNameOf(visibleMode)),
          style: const TextStyle(color: Colors.tealAccent, fontSize: 12),
        ),
        const SizedBox(height: 4),
        Text(
          mode == 'normal'
              ? _modeSummary(mode)
              : '${_modeSummary(visibleMode)} (${_modeNameOf(mode)})',
          style: const TextStyle(color: Colors.white38, fontSize: 11),
        ),
        const SizedBox(height: 4),
        Text(
          _modeConfigSummary(mode),
          style: const TextStyle(color: Colors.white54, fontSize: 11),
        ),
        if (tempStateOf(_ss, widget.app) case final temp?) ...[
          const SizedBox(height: 4),
          Text(
            tempStateSummary(context, temp),
            style: const TextStyle(color: Colors.orangeAccent, fontSize: 11),
          ),
        ],
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white38),
              ),
              icon: const Icon(Icons.layers, size: 16),
              label: Text(
                S.of(context).selectionMode,
                style: const TextStyle(fontSize: 12),
              ),
              onPressed: _showModeSheet,
            ),
            if (mode != 'normal')
              TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: Colors.tealAccent,
                ),
                icon: const Icon(Icons.edit, size: 16),
                label: Text(
                  S.of(context).actionConfigure,
                  style: const TextStyle(fontSize: 12),
                ),
                onPressed: () => _configureMode(mode),
              ),
          ],
        ),
      ],
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

    // Floor changes are only available in normal mode. Other modes manage
    // their own targets through schedules or rules.
    final currentMode = _ss.appMode(app.packageName);
    final floorChanged =
        currentMode == 'normal' && _selectedFloor != app.floor;

    await _as.saveConfig(app);
    if (floorChanged && mounted) {
      await applyFloorsWithStrictGate(
        context,
        _ss,
        _as,
        {app.packageName: _selectedFloor},
        widget.allApps,
      );
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(
          app.appName,
          style: const TextStyle(color: Colors.white, fontSize: 15),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Custom name ─────────────────────────────────────────────
            Text(
              S.of(context).displayNameLabel,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _customNameCtrl,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: app.appName,
                      hintStyle: const TextStyle(
                        color: Colors.white24,
                        fontSize: 13,
                      ),
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
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () {
                    _customNameCtrl.clear();
                    setState(() {});
                  },
                  child: const Icon(
                    Icons.restart_alt,
                    color: Colors.white38,
                    size: 20,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            _buildModeSection(),
            if (_ss.appMode(app.packageName) == 'normal') ...[
              const SizedBox(height: 16),
              _buildFloorPickerSection(),
            ],
            const SizedBox(height: 16),

            // ── Folder picker ───────────────────────────────────────────
            Text(
              S.of(context).folderLabel,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
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
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: _selectedFolder == null
                            ? Colors.white
                            : Colors.transparent,
                        border: Border.all(
                          color: _selectedFolder == null
                              ? Colors.white
                              : Colors.white38,
                        ),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        S.of(context).noneLabel,
                        style: TextStyle(
                          color: _selectedFolder == null
                              ? Colors.black
                              : Colors.white54,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                  ..._existingFolders.map(
                    (name) => GestureDetector(
                      onTap: () => setState(() {
                        _selectedFolder = name;
                        _folderCtrl.clear();
                      }),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: _selectedFolder == name
                              ? Colors.white
                              : Colors.transparent,
                          border: Border.all(
                            color: _selectedFolder == name
                                ? Colors.white
                                : Colors.white38,
                          ),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.folder,
                              size: 13,
                              color: Colors.white54,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              name,
                              style: TextStyle(
                                color: _selectedFolder == name
                                    ? Colors.black
                                    : Colors.white54,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            TextField(
              controller: _folderCtrl,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: S.of(context).newFolderHint,
                hintStyle: const TextStyle(color: Colors.white24, fontSize: 12),
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
              ),
              onChanged: (v) {
                if (v.isNotEmpty) setState(() => _selectedFolder = null);
              },
            ),
            const SizedBox(height: 16),

            // ── Uninstall ───────────────────────────────────────────────
            // Surfaces the system uninstall flow from the app-list
            // detail page. The actual prompt is the Android one
            // (ACTION_DELETE) so the user still has to confirm there.
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                icon: const Icon(
                  Icons.delete_outline,
                  color: Colors.redAccent,
                  size: 18,
                ),
                label: Text(
                  S.of(context).uninstall,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                ),
                onPressed: () async {
                  final intent = AndroidIntent(
                    action: 'android.intent.action.DELETE',
                    data: 'package:${app.packageName}',
                  );
                  await intent.launch();
                },
              ),
            ),

            const SizedBox(height: 12),

            // ── Save / Cancel buttons ───────────────────────────────────
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

}

// ── Emergency per-app caps screen ───────────────────────────

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

  String _displayName(AppConfig app) {
    final custom = app.customName?.trim();
    if (custom?.isNotEmpty == true) return custom!;
    final name = app.appName.trim();
    return name.isNotEmpty ? name : app.packageName;
  }

  /// アプリ個別の緊急上限もストリクト「緊急使用設定ロック」の対象。
  Future<bool> _gateEmergencyForApp(AppConfig app, int count, String period) async {
    final result = await requestStrictAction(
      context,
      _ss,
      key: 'emergency',
      blockedMessage: S.of(context).emergencyLimitLocked,
      reservationKind: ReservationKinds.emergencyCapApp,
      reservationData: {
        'pkg': app.packageName,
        'count': count,
        'period': period,
      },
      reservationLabel: S.of(context).appLimitTitle(_displayName(app)),
    );
    if (result == StrictGateResult.reserved && mounted) setState(() {});
    return result == StrictGateResult.allowed;
  }

  Future<void> _editCap(AppConfig app) async {
    final cap = _ss.emergencyCapForApp(app.packageName);
    final result = await _showCapDialogStandalone(
      context,
      S.of(context).appLimitTitle(_displayName(app)),
      (cap?['count'] as num?)?.toInt() ?? 0,
      (cap?['period'] as String?) ?? 'daily',
    );
    if (result == null || !mounted) return;
    if (!await _gateEmergencyForApp(app, result.$1, result.$2)) return;
    await _ss.setEmergencyCapForApp(app.packageName, result.$1, result.$2);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final registered = _ss.getEmergencyApps();
    final apps =
        widget.allApps.where((a) => registered.contains(a.packageName)).toList()
          ..sort(
            (a, b) => _displayName(
              a,
            ).toLowerCase().compareTo(_displayName(b).toLowerCase()),
          );
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0D0D),
        foregroundColor: Colors.white,
        title: Text(
          s.emergencyPerAppLimitTitle,
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
      ),
      body: apps.isEmpty
          ? Center(
              child: Text(
                s.noEmergencyRegistered,
                style: const TextStyle(color: Colors.white54, fontSize: 13),
              ),
            )
          : ListView.separated(
              itemCount: apps.length,
              separatorBuilder: (_, __) => const Divider(
                height: 1,
                color: Colors.white12,
                indent: 16,
                endIndent: 16,
              ),
              itemBuilder: (_, i) {
                final app = apps[i];
                final cap = _ss.emergencyCapForApp(app.packageName);
                final summary = cap == null
                    ? s.notSetUnlimited
                    : _ss.capSummary(s, cap);
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  title: Text(
                    _displayName(app),
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                  ),
                  subtitle: Text(
                    summary,
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  trailing: cap == null
                      ? const Icon(
                          Icons.chevron_right,
                          color: Colors.white24,
                          size: 18,
                        )
                      : IconButton(
                          icon: const Icon(
                            Icons.close,
                            color: Colors.redAccent,
                            size: 18,
                          ),
                          onPressed: () async {
                            await _ss.setEmergencyCapForApp(
                              app.packageName,
                              0,
                              'daily',
                            );
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

// ── Emergency folder caps screen ────────────────────────────

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

  String _displayName(AppConfig app) {
    final custom = app.customName?.trim();
    if (custom?.isNotEmpty == true) return custom!;
    final name = app.appName.trim();
    return name.isNotEmpty ? name : app.packageName;
  }

  Future<void> _editFolder({Map<String, dynamic>? existing, int? index}) async {
    final isEdit = existing != null;
    final nameCtrl = TextEditingController(
      text: existing?['name'] as String? ?? '',
    );
    final selected = <String>{
      ...(existing?['apps'] as List?)?.map((e) => e.toString()) ??
          const <String>[],
    };
    int count = (existing?['count'] as num?)?.toInt() ?? 0;
    String period = existing?['period'] as String? ?? 'daily';
    final countCtrl = TextEditingController(
      text: count > 0 ? count.toString() : '',
    );

    final registered = _ss.getEmergencyApps();
    final candidates =
        widget.allApps.where((a) => registered.contains(a.packageName)).toList()
          ..sort(
            (a, b) => _displayName(
              a,
            ).toLowerCase().compareTo(_displayName(b).toLowerCase()),
          );

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
          title: Text(
            isEdit ? S.of(ctx).folderEdit : S.of(ctx).folderAdd,
            style: const TextStyle(color: Colors.white, fontSize: 14),
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    S.of(ctx).nameLabel,
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  TextField(
                    controller: nameCtrl,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: S.of(ctx).nameHintSns,
                      hintStyle: const TextStyle(color: Colors.white38),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.07),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    S.of(ctx).countWithEmptyUnlimitedHint,
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  TextField(
                    controller: countCtrl,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: S.of(ctx).unlimited,
                      hintStyle: const TextStyle(color: Colors.white38),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.07),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    S.of(ctx).periodLabel,
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
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
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: sel ? Colors.white : Colors.transparent,
                            border: Border.all(
                              color: sel ? Colors.white : Colors.white38,
                            ),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            p.$2,
                            style: TextStyle(
                              color: sel ? Colors.black : Colors.white70,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    S.of(ctx).targetApps,
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  if (candidates.isEmpty)
                    Text(
                      S.of(ctx).noEmergencyRegistered,
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 12,
                      ),
                    )
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
                            title: Text(
                              _displayName(app),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                              ),
                            ),
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
                child: Text(
                  S.of(ctx).actionDelete,
                  style: const TextStyle(color: Colors.redAccent),
                ),
              ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(
                S.of(ctx).actionCancel,
                style: const TextStyle(color: Colors.white54),
              ),
            ),
            TextButton(
              onPressed: () {
                final name = nameCtrl.text.trim();
                if (name.isEmpty) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(content: Text(S.of(ctx).pleaseEnterName)),
                  );
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
              child: Text(
                S.of(ctx).actionSave,
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
    if (result == null || !mounted) return;
    final folders = _ss.emergencyCapFolders;
    if (result['__delete'] == true && index != null) {
      folders.removeAt(index);
    } else if (isEdit && index != null) {
      folders[index] = result;
    } else {
      folders.add(result);
    }
    // フォルダ上限もストリクト「緊急使用設定ロック」の対象
    final gate = await requestStrictAction(
      context,
      _ss,
      key: 'emergency',
      blockedMessage: S.of(context).emergencyLimitLocked,
      reservationKind: ReservationKinds.emergencyCapFolders,
      reservationData: {'folders': folders},
      reservationLabel: S.of(context).emergencyFolderLimitTitle,
    );
    if (gate == StrictGateResult.allowed) {
      await _ss.setEmergencyCapFolders(folders);
    }
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
        title: Text(
          s.emergencyFolderLimitTitle,
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: Colors.white),
            onPressed: () => _editFolder(),
          ),
        ],
      ),
      body: folders.isEmpty
          ? Center(
              child: Text(
                s.folderAddTopRightHint,
                style: const TextStyle(color: Colors.white54, fontSize: 13),
              ),
            )
          : ListView.separated(
              itemCount: folders.length,
              separatorBuilder: (_, __) => const Divider(
                height: 1,
                color: Colors.white12,
                indent: 16,
                endIndent: 16,
              ),
              itemBuilder: (_, i) {
                final folder = folders[i];
                final apps =
                    (folder['apps'] as List?)
                        ?.map((e) => e.toString())
                        .toList() ??
                    const [];
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  title: Text(
                    folder['name'] as String? ?? s.folderLabel,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                  ),
                  subtitle: Text(
                    s.folderAppSubtitle(_ss.capSummary(s, folder), apps.length),
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  trailing: const Icon(
                    Icons.chevron_right,
                    color: Colors.white24,
                    size: 18,
                  ),
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
    text: initialCount > 0 ? initialCount.toString() : '',
  );
  return showDialog<(int, String)>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setInner) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: Text(
          title,
          style: const TextStyle(color: Colors.white, fontSize: 14),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              S.of(ctx).countWithEmptyUnlimitedHint,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                hintText: S.of(ctx).unlimited,
                hintStyle: const TextStyle(color: Colors.white38),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.07),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              S.of(ctx).periodLabel,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
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
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: sel ? Colors.white : Colors.transparent,
                      border: Border.all(
                        color: sel ? Colors.white : Colors.white38,
                      ),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      p.$2,
                      style: TextStyle(
                        color: sel ? Colors.black : Colors.white70,
                        fontSize: 11,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
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
            onPressed: () {
              final c = int.tryParse(ctrl.text) ?? 0;
              Navigator.pop(ctx, (c < 0 ? 0 : c, period));
            },
            child: Text(
              S.of(ctx).actionSave,
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    ),
  );
}
