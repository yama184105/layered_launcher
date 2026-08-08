part of '../home_screen.dart';

extension DialogsMethods on _HomeScreenState {
  // ── long-press: app bottom sheet ──────────────────────────────

  void _showAppBottomSheet(AppConfig app, int floor, {bool isFavorite = false}) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewPadding.bottom),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.symmetric(vertical: 8),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Text(
                  _displayName(app),
                  style: const TextStyle(color: Colors.white54, fontSize: 13),
                ),
              ),
              const Divider(color: Colors.white12, height: 1),
              _sheetItem(ctx, Icons.checklist, S.of(ctx).switchToMultiSelect, () {
                Navigator.pop(ctx);
                setState(() {
                  _selectionMode = true;
                  _selectionInFavorites = isFavorite;
                  _reorderMode = false;
                  _selectedPackages.add(app.packageName);
                });
              }),
              _sheetItem(ctx, Icons.edit, S.of(ctx).renameApp, () {
                Navigator.pop(ctx);
                _showRenameDialog(app);
              }),
              _sheetItem(ctx, Icons.stairs, S.of(ctx).moveFloor, () {
                Navigator.pop(ctx);
                _showModePickerSheet(app);
              }),
              _sheetItem(ctx, Icons.folder_open, S.of(ctx).addToFolder, () {
                Navigator.pop(ctx);
                _showFolderPicker(app, floor);
              }),
              if (app.isPinned)
                _sheetItem(ctx, Icons.star, S.of(ctx).removeFromFavorites, () {
                  Navigator.pop(ctx);
                  _unpinFromHome(app);
                }, color: Colors.amberAccent)
              else
                _sheetItem(ctx, Icons.star_outline, S.of(ctx).addToFavorites, () {
                  Navigator.pop(ctx);
                  _pinToHome(app);
                }),
              _sheetItem(ctx, Icons.info_outline, S.of(ctx).appInfo, () {
                Navigator.pop(ctx);
                _native.openAppDetailSettings(packageName: app.packageName);
              }),
              _sheetItem(ctx, Icons.delete_outline, S.of(ctx).uninstall, () {
                Navigator.pop(ctx);
                _confirmUninstall(app);
              }, color: Colors.redAccent),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  // ── long-press: folder bottom sheet ──────────────────────────

  void _showFolderBottomSheet(
      String folderName, List<AppConfig> apps, int floor) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Row(
                children: [
                  const Icon(Icons.folder, color: Colors.white38, size: 16),
                  const SizedBox(width: 8),
                  Text(folderName,
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 13)),
                ],
              ),
            ),
            const Divider(color: Colors.white12, height: 1),
            _sheetItem(ctx, Icons.checklist, S.of(ctx).switchToMultiSelect, () {
              Navigator.pop(ctx);
              setState(() {
                _folderSelectionMode = true;
                _selectionMode = false;
                _reorderMode = false;
                _selectedFolders.add('$floor:$folderName');
              });
            }),
            _sheetItem(ctx, Icons.edit, S.of(ctx).renameFolder, () {
              Navigator.pop(ctx);
              _showRenameFolderDialog(folderName, apps, floor);
            }),
            _sheetItem(ctx, Icons.star_outline, S.of(ctx).addToFavorites, () {
              Navigator.pop(ctx);
              _pinFolderToHome(folderName);
            }),
            _sheetItem(ctx, Icons.swap_vert, S.of(ctx).folderPosition, () {
              Navigator.pop(ctx);
              _showFolderPositionDialog(folderName, apps);
            }),
            _sheetItem(ctx, Icons.delete_outline, S.of(ctx).deleteFolder, () {
              Navigator.pop(ctx);
              _deleteFolderConfirm(folderName, apps);
            }, color: Colors.redAccent),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }


  Widget _sheetItem(BuildContext ctx, IconData icon, String label,
      VoidCallback? onTap,
      {Color color = Colors.white, bool checked = false}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
          child: Row(
            children: [
              Icon(icon, color: color.withValues(alpha: 0.7), size: 22),
              const SizedBox(width: 16),
              Expanded(
                child: Text(label,
                    style: TextStyle(color: color, fontSize: 15)),
              ),
              if (checked)
                const Icon(Icons.check, color: Colors.white, size: 18),
            ],
          ),
        ),
      ),
    );
  }

  // ── app actions ───────────────────────────────────────────────

  Future<void> _showRenameDialog(AppConfig app) async {
    final ctrl = TextEditingController(text: app.customName ?? '');
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: Text(S.of(ctx).renameApp,
            style: const TextStyle(color: Colors.white)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: app.appName,
            hintStyle: const TextStyle(color: Colors.white38),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.07),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(S.of(ctx).actionCancel,
                style: const TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () async {
              app.customName = ctrl.text.trim().isEmpty
                  ? null
                  : ctrl.text.trim();
              await widget.appService.saveConfig(app);
              if (ctx.mounted) Navigator.pop(ctx);
              _loadApps();
            },
            child: Text(S.of(ctx).actionDone,
                style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => ctrl.dispose());
  }

  // ── mode picker (階層を移動 → モード選択) ─────────────────────

  /// 「階層を移動」のエントリ。複数選択の「モード」ボタンと同じシートを
  /// 出す（説明文つき・「解除」あり）。カスタム（スケジュール/使用回数/
  /// 使用時間）を選ぶと編集画面へ進み、そこで対象アプリを複数選択できる。
  Future<void> _showModePickerSheet(AppConfig app) async {
    final ss = widget.settingsService;
    final pkg = app.packageName;
    final temp = tempStateOf(ss, app);

    final picked = await showModeSelectSheet(
      context,
      title: _displayName(app),
      currentMode: ss.appMode(pkg),
      statusText: temp != null ? tempStateSummary(context, temp) : null,
      showRelease: ss.appMode(pkg) != 'normal',
      showTempRelease: temp != null,
    );
    if (picked == null || !mounted) return;
    if (await _applyModeToPackages(picked, [pkg]) && mounted) {
      setState(() {});
      _loadApps();
    }
  }

  Future<void> _showFolderPicker(AppConfig app, int floor) async {
    // Collect existing folders on this floor
    final existing = _appsForFloor(floor)
        .map((a) => a.folderName)
        .where((n) => n != null && n.isNotEmpty)
        .cast<String>()
        .toSet()
        .toList()
      ..sort();

    final ctrl = TextEditingController();
    String? selected = app.folderName?.isNotEmpty == true
        ? app.folderName
        : null;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInner) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          title: Text(S.of(ctx).addToFolder,
              style: const TextStyle(color: Colors.white)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (existing.isNotEmpty) ...[
                  Text(S.of(ctx).selectExistingFolder,
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 12)),
                  const SizedBox(height: 8),
                  _folderOption(null, selected, S.of(ctx).noFolderEmoji,
                      () => setInner(() {
                            selected = null;
                            ctrl.clear();
                          })),
                  ...existing.map((name) => _folderOption(
                        name,
                        selected,
                        '📁  $name',
                        () => setInner(() {
                          selected = name;
                          ctrl.clear();
                        }),
                      )),
                  const SizedBox(height: 12),
                  const Divider(color: Colors.white12),
                  const SizedBox(height: 8),
                ],
                Text(S.of(ctx).newFolderName,
                    style: const TextStyle(
                        color: Colors.white54, fontSize: 12)),
                const SizedBox(height: 6),
                TextField(
                  controller: ctrl,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: S.of(ctx).folderNameHint,
                    hintStyle: const TextStyle(
                        color: Colors.white38, fontSize: 12),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.07),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onChanged: (v) {
                    if (v.isNotEmpty) setInner(() => selected = v);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(S.of(ctx).actionCancel,
                  style: const TextStyle(color: Colors.white54)),
            ),
            TextButton(
              onPressed: () async {
                final newFolder = ctrl.text.trim().isNotEmpty
                    ? ctrl.text.trim()
                    : selected;
                app.folderName =
                    (newFolder == null || newFolder.isEmpty)
                        ? null
                        : newFolder;
                await widget.appService.saveConfig(app);
                if (ctx.mounted) Navigator.pop(ctx);
                _loadApps();
              },
              child: Text(S.of(ctx).actionDone,
                  style: const TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => ctrl.dispose());
  }

  Widget _folderOption(String? value, String? selected, String label,
      VoidCallback onTap) {
    final isSelected = value == selected;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          width: double.infinity,
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          margin: const EdgeInsets.only(bottom: 4),
          decoration: BoxDecoration(
            color: isSelected
                ? Colors.white.withValues(alpha: 0.1)
                : Colors.transparent,
            border: Border.all(
                color:
                    isSelected ? Colors.white38 : Colors.white12),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(label,
                    style: TextStyle(
                        color: isSelected
                            ? Colors.white
                            : Colors.white60,
                        fontSize: 13)),
              ),
              if (isSelected)
                const Icon(Icons.check,
                    color: Colors.white, size: 16),
            ],
          ),
        ),
      ),
    );
  }

  // ── bulk actions (複数選択) ────────────────────────────────────

  /// 選択したアプリをまとめてフロア移動する。ストリクトでロック中の
  /// アプリはブロック or タイマー確認を挟んでから適用する。
  Future<void> _applyFloorToPackages(List<String> pkgs, int floor) =>
      applyFloorsWithStrictGate(
        context,
        widget.settingsService,
        widget.appService,
        {for (final pkg in pkgs) pkg: floor},
        _allApps,
      );

  void _exitSelectionMode() {
    setState(() {
      _selectionMode = false;
      _selectionInFavorites = false;
      _selectedPackages.clear();
    });
    _loadApps();
  }

  Future<void> _showBulkMoveDialog() async {
    if (_selectedPackages.isEmpty) return;
    final pkgs = _selectedPackages.toList();
    final floor = await showFloorSelectDialog(
      context,
      widget.settingsService,
      title: S.of(context).moveAppsCount(pkgs.length),
    );
    if (floor == null || !mounted) return;
    await _applyFloorToPackages(pkgs, floor);
    if (mounted) _exitSelectionMode();
  }

  /// 複数選択 → モード設定。ノーマル/スケジュール/使用回数/使用時間/
  /// 一時的への切り替えと、割り振り解除をまとめて行う。
  Future<void> _showBulkModePicker() async {
    if (_selectedPackages.isEmpty) return;
    final pkgs = _selectedPackages.toList();
    final ss = widget.settingsService;
    final currentModes = pkgs.map(ss.appMode).toSet();
    final anyTemp = _allApps.any(
        (a) => pkgs.contains(a.packageName) && tempStateOf(ss, a) != null);
    final picked = await showModeSelectSheet(
      context,
      title: S.of(context).modeSwitchCountTitle(pkgs.length),
      currentMode: currentModes.length == 1 ? currentModes.first : null,
      showRelease: currentModes.any((m) => m != 'normal'),
      showTempRelease: anyTemp,
    );
    if (picked == null || !mounted) return;
    if (await _applyModeToPackages(picked, pkgs) && mounted) {
      _exitSelectionMode();
    }
  }

  /// 複数選択 → 一時的に移動。
  Future<void> _showBulkTempMove() async {
    if (_selectedPackages.isEmpty) return;
    if (await _applyTempMoveToPackages(_selectedPackages.toList()) && mounted) {
      _exitSelectionMode();
    }
  }

  /// モード選択シートの結果を [pkgs] に適用する。設定が必要なモードは
  /// その編集画面へ遷移する。戻り値 true = 何か変更した。
  Future<bool> _applyModeToPackages(String mode, List<String> pkgs) async {
    if (pkgs.isEmpty) return false;
    final ss = widget.settingsService;
    switch (mode) {
      case 'normal':
        // フロアを確定するまで解除しない。キャンセルすれば元のモードのまま。
        await switchToNormalWithFloor(context, ss, widget.appService, _allApps,
            pkgs, initialFloor: pkgs.length == 1
                ? _allApps
                    .cast<AppConfig?>()
                    .firstWhere((a) => a?.packageName == pkgs.first,
                        orElse: () => null)
                    ?.floor
                : null);
        return true;
      case kModeCustom:
        // カスタム＝スケジュール。既存スケジュールがあれば「既存に追加/新規」を選ぶ
        final entry = await enterScheduleForApps(context, ss, _allApps, pkgs);
        if (entry == ScheduleEntryResult.cancelled) return false;
        if (entry == ScheduleEntryResult.done) return true;
        if (!mounted) return false;
        final result = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (_) => AutoMoveScreen(
              settingsService: ss,
              packageNames: pkgs,
              allApps: _allApps,
            ),
          ),
        );
        return result == true;
      case kModeTemp:
        return _applyTempMoveToPackages(pkgs);
      case kModeActionTempRelease:
        await clearTempMove(widget.appService, ss,
            _allApps.where((a) => pkgs.contains(a.packageName)).toList());
        return true;
      case kModeActionRelease:
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF1A1A1A),
            title: Text(S.of(ctx).actionRelease,
                style: const TextStyle(color: Colors.white, fontSize: 14)),
            content: Text(S.of(ctx).releaseCountConfirm(pkgs.length),
                style: const TextStyle(color: Colors.white70, fontSize: 13)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(S.of(ctx).actionCancel,
                    style: const TextStyle(color: Colors.white54)),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(S.of(ctx).actionRelease,
                    style: const TextStyle(color: Colors.redAccent)),
              ),
            ],
          ),
        );
        if (confirmed != true || !mounted) return false;
        await releaseAppsWithSchedulePrompt(context, ss, _allApps, pkgs);
        await clearTempMove(widget.appService, ss,
            _allApps.where((a) => pkgs.contains(a.packageName)).toList());
        return true;
    }
    return false;
  }

  /// 一時的モードを [pkgs] に適用する。戻り値 true = 適用した。
  Future<bool> _applyTempMoveToPackages(List<String> pkgs) async {
    final apps =
        _allApps.where((a) => pkgs.contains(a.packageName)).toList();
    if (apps.isEmpty) return false;
    final ss = widget.settingsService;
    final single = apps.length == 1 ? apps.first : null;
    final spec = await showTempMoveDialog(
      context,
      settingsService: ss,
      title: single != null
          ? '${S.of(context).tempMoveTitle} — ${_displayName(single)}'
          : S.of(context).tempMoveCountTitle(apps.length),
      currentMode: single != null ? ss.appMode(single.packageName) : null,
      currentFloor: single?.floor,
    );
    if (spec == null) return false;
    await applyTempMoveWithStrictGate(context, ss, widget.appService, apps, spec);
    return true;
  }

  Future<void> _showBulkFolderDialog() async {
    final floor = _currentFloor == _HomeScreenState._homeFloor ? 1 : _currentFloor;
    final existing = _appsForFloor(floor)
        .map((a) => a.folderName)
        .where((n) => n != null && n.isNotEmpty)
        .cast<String>()
        .toSet()
        .toList()
      ..sort();

    final ctrl = TextEditingController();
    String? selected;

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInner) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          title: Text(S.of(ctx).addAppsToFolder(_selectedPackages.length),
              style: const TextStyle(color: Colors.white, fontSize: 14)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (existing.isNotEmpty) ...[
                  Text(S.of(ctx).selectExistingFolder,
                      style: const TextStyle(color: Colors.white54, fontSize: 12)),
                  const SizedBox(height: 8),
                  ...existing.map((name) => _folderOption(
                        name, selected, '📁  $name',
                        () => setInner(() { selected = name; ctrl.clear(); }),
                      )),
                  const SizedBox(height: 12),
                  const Divider(color: Colors.white12),
                  const SizedBox(height: 8),
                ],
                Text(S.of(ctx).newFolderName,
                    style: const TextStyle(color: Colors.white54, fontSize: 12)),
                const SizedBox(height: 6),
                TextField(
                  controller: ctrl,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: S.of(ctx).folderNameHint,
                    hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.07),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onChanged: (v) {
                    if (v.isNotEmpty) setInner(() => selected = v);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(S.of(ctx).actionCancel,
                  style: const TextStyle(color: Colors.white54)),
            ),
            TextButton(
              onPressed: selected != null || ctrl.text.isNotEmpty
                  ? () => Navigator.pop(
                        ctx,
                        ctrl.text.trim().isNotEmpty
                            ? ctrl.text.trim()
                            : selected,
                      )
                  : null,
              child: Text(S.of(ctx).actionDone,
                  style: const TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => ctrl.dispose());

    if (result != null && result.isNotEmpty && mounted) {
      for (final pkg in _selectedPackages) {
        final app = _allApps.firstWhere(
          (a) => a.packageName == pkg,
          orElse: () => AppConfig(packageName: pkg, appName: pkg, floor: 1),
        );
        app.folderName = result;
        await widget.appService.saveConfig(app);
      }
      setState(() {
        _selectionMode = false;
        _selectionInFavorites = false;
        _selectedPackages.clear();
      });
      _loadApps();
    }
  }

  // ── app block dialog ──────────────────────────────────────────

  Future<void> _showBlockedDialog(AppConfig app) async {
    final ss = widget.settingsService;
    final pkg = app.packageName;
    final name = (app.customName?.isNotEmpty == true) ? app.customName! : app.appName;
    // First dialog: blocked alert. User picks between cancelling,
    // launching the app once, or jumping to the app's system settings
    // (useful when they just want to grant a permission like
    // notification access without actually using the blocked app).
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: Text(S.of(ctx).appBlockedTitle(name),
            style: const TextStyle(color: Colors.white, fontSize: 15)),
        content: Text(
          S.of(ctx).appBlockedMessage,
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'close'),
            child: Text(S.of(ctx).actionClose,
                style: const TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'settings'),
            child: const Text('システム設定を開く',
                style: TextStyle(color: Colors.tealAccent)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'launch'),
            child: Text(S.of(ctx).emergencyOverride,
                style: const TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (action == 'settings' && mounted) {
      // System settings shortcut: record the override (so subsequent
      // tap-back into the app doesn't re-prompt) and jump straight to
      // Settings > Apps > [pkg] so the user can flip notification /
      // permission toggles without unblocking via launch.
      await ss.recordBlockOverride(pkg);
      await _native.openAppDetailSettings(packageName: pkg);
      return;
    }
    if (action == 'launch' && mounted) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          title: Text(S.of(ctx).confirmOverrideTitle,
              style: const TextStyle(color: Colors.white)),
          content: Text(
            S.of(ctx).overrideRecorded,
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
              child: Text(S.of(ctx).overrideAndLaunch,
                  style: const TextStyle(color: Colors.redAccent)),
            ),
          ],
        ),
      );
      if (confirm == true && mounted) {
        await ss.recordBlockOverride(pkg);
        _launchWithMindfulDelay(app);
      }
    }
  }

  Future<void> _confirmUninstall(AppConfig app) async {
    // Launch system uninstall dialog directly — no in-app confirmation needed
    final intent = AndroidIntent(
      action: 'android.intent.action.DELETE',
      data: 'package:${app.packageName}',
    );
    await intent.launch();
  }

  // ── folder actions ────────────────────────────────────────────

  Future<void> _showRenameFolderDialog(
      String oldName, List<AppConfig> apps, int floor) async {
    final ctrl = TextEditingController(text: oldName);
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: Text(S.of(ctx).renameFolder,
            style: const TextStyle(color: Colors.white)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: S.of(ctx).folderName,
            hintStyle:
                const TextStyle(color: Colors.white38),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.07),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(S.of(ctx).actionCancel,
                style: const TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () async {
              final newName = ctrl.text.trim();
              if (newName.isEmpty || newName == oldName) {
                Navigator.pop(ctx);
                return;
              }
              for (final app in apps) {
                app.folderName = newName;
                await widget.appService.saveConfig(app);
              }
              if (ctx.mounted) Navigator.pop(ctx);
              _loadApps();
            },
            child: Text(S.of(ctx).actionDone,
                style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => ctrl.dispose());
  }

  Future<void> _deleteFolderConfirm(
      String folderName, List<AppConfig> apps) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: Text(S.of(ctx).deleteFolderTitle(folderName),
            style: const TextStyle(color: Colors.white)),
        content: Text(
          S.of(ctx).deleteFolderMessage(apps.length),
          style: const TextStyle(
              color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(S.of(ctx).actionCancel,
                style: const TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(S.of(ctx).actionDelete,
                style: const TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      for (final app in apps) {
        app.folderName = null;
        await widget.appService.saveConfig(app);
      }
      _loadApps();
    }
  }

  // ── bulk folder actions (フォルダの複数選択) ───────────────────
  // 選択キーは '<floor>:<folderName>'。同名フォルダが別フロアにもあるので
  // フロアと組で識別する。

  String _folderNameOfKey(String key) {
    final i = key.indexOf(':');
    return i < 0 ? key : key.substring(i + 1);
  }

  int _folderFloorOfKey(String key) {
    final i = key.indexOf(':');
    return i < 0 ? 1 : (int.tryParse(key.substring(0, i)) ?? 1);
  }

  /// 選択中フォルダに属するアプリをすべて集める。
  List<AppConfig> _appsOfSelectedFolders() {
    final result = <AppConfig>[];
    for (final key in _selectedFolders) {
      final floor = _folderFloorOfKey(key);
      final name = _folderNameOfKey(key);
      result.addAll(
        _allApps.where((a) => a.floor == floor && a.folderName == name),
      );
    }
    return result;
  }

  void _exitFolderSelection() {
    setState(() {
      _folderSelectionMode = false;
      _selectedFolders.clear();
    });
    _loadApps();
  }

  /// 全部お気に入りなら外す、そうでなければ全部追加する。
  Future<void> _bulkToggleFolderFavorite() async {
    final ss = widget.settingsService;
    final names = _selectedFolders.map(_folderNameOfKey).toSet();
    final pinned = ss.pinnedFolderNames;
    final allPinned = names.every(pinned.contains);
    if (allPinned) {
      pinned.removeWhere(names.contains);
    } else {
      for (final n in names) {
        if (!pinned.contains(n)) pinned.add(n);
      }
    }
    await ss.setPinnedFolderNames(pinned);
    _exitFolderSelection();
  }

  Future<void> _showBulkFolderPositionDialog() async {
    final s0 = S.of(context);
    final options = <(String, String)>[
      ('top', s0.folderPositionTop),
      ('alphabetical', s0.folderPositionAlphabetical),
      ('bottom', s0.folderPositionBottom),
    ];
    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: Row(
          children: [
            const Icon(Icons.swap_vert, color: Colors.white54, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                S.of(ctx).folderPositionBulkTitle(_selectedFolders.length),
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: options
              .map((opt) => Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => Navigator.pop(ctx, opt.$1),
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 12),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(opt.$2,
                                  style: const TextStyle(
                                      color: Colors.white70, fontSize: 14)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ))
              .toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(S.of(ctx).actionCancel,
                style: const TextStyle(color: Colors.white54)),
          ),
        ],
      ),
    );
    if (picked == null || !mounted) return;
    for (final app in _appsOfSelectedFolders()) {
      app.folderPosition = picked;
      await widget.appService.saveConfig(app);
    }
    _exitFolderSelection();
  }

  Future<void> _bulkDeleteFolders() async {
    final apps = _appsOfSelectedFolders();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: Text(S.of(ctx).deleteFoldersTitle(_selectedFolders.length),
            style: const TextStyle(color: Colors.white, fontSize: 14)),
        content: Text(S.of(ctx).deleteFolderMessage(apps.length),
            style: const TextStyle(color: Colors.white70, fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(S.of(ctx).actionCancel,
                style: const TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(S.of(ctx).actionDelete,
                style: const TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    // フォルダ解除（中のアプリは消さない）。お気に入り登録も外す。
    for (final app in apps) {
      app.folderName = null;
      await widget.appService.saveConfig(app);
    }
    final ss = widget.settingsService;
    final names = _selectedFolders.map(_folderNameOfKey).toSet();
    final pinned = ss.pinnedFolderNames..removeWhere(names.contains);
    await ss.setPinnedFolderNames(pinned);
    _exitFolderSelection();
  }

  Future<void> _setFolderPosition(
      List<AppConfig> apps, String position) async {
    for (final app in apps) {
      app.folderPosition = position;
      await widget.appService.saveConfig(app);
    }
    setState(() {});
    _loadApps();
  }

  Future<void> _showFolderPositionDialog(
      String folderName, List<AppConfig> apps) async {
    final current =
        apps.isNotEmpty ? apps.first.folderPosition : 'alphabetical';
    final s0 = S.of(context);
    final options = <(String, String)>[
      ('top', s0.folderPositionTop),
      ('alphabetical', s0.folderPositionAlphabetical),
      ('bottom', s0.folderPositionBottom),
    ];
    String selected = current;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInner) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          title: Row(
            children: [
              const Icon(Icons.swap_vert, color: Colors.white54, size: 18),
              const SizedBox(width: 8),
              Text(S.of(ctx).folderPositionTitle(folderName),
                  style: const TextStyle(
                      color: Colors.white, fontSize: 14)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: options.map((opt) {
              final isSelected = selected == opt.$1;
              return Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => setInner(() => selected = opt.$1),
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(opt.$2,
                              style: TextStyle(
                                  color: isSelected
                                      ? Colors.white
                                      : Colors.white70,
                                  fontSize: 14)),
                        ),
                        if (isSelected)
                          const Icon(Icons.check,
                              color: Colors.white, size: 18),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(S.of(ctx).actionCancel,
                  style: const TextStyle(color: Colors.white54)),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _setFolderPosition(apps, selected);
              },
              child: Text(S.of(ctx).actionDone,
                  style: const TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  // ── folder order dialog (for top/bottom pinned folders) ───────────────────

  Future<void> _showFolderOrderDialog(int floor, String positionType) async {
    final floorApps = _appsForFloor(floor);
    final folderMap = <String, List<AppConfig>>{};
    for (final app in floorApps) {
      final fn = _folderOf(app);
      if (fn != null) folderMap.putIfAbsent(fn, () => []).add(app);
    }

    final folders = folderMap.keys
        .where((fn) =>
            folderMap[fn]!.isNotEmpty &&
            folderMap[fn]!.first.folderPosition == positionType)
        .toList();

    final ss = widget.settingsService;
    final storedOrder = positionType == 'top'
        ? ss.getFixedTopFolderOrder(floor)
        : ss.getFixedBottomFolderOrder(floor);

    folders.sort((a, b) {
      final ia = storedOrder.indexOf(a);
      final ib = storedOrder.indexOf(b);
      if (ia == -1 && ib == -1) return a.compareTo(b);
      if (ia == -1) return 1;
      if (ib == -1) return -1;
      return ia.compareTo(ib);
    });

    final currentOrder = List<String>.from(folders);

    final s0 = S.of(context);
    final titleText = positionType == 'top'
        ? s0.fixedTopFolderOrder
        : s0.fixedBottomFolderOrder;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInner) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          title: Text(titleText,
              style: const TextStyle(color: Colors.white, fontSize: 14)),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    S.of(ctx).dragToReorder,
                    style: const TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                ),
                Flexible(
                  child: ReorderableListView(
                    shrinkWrap: true,
                    buildDefaultDragHandles: false,
                    proxyDecorator: (child, index, animation) => Material(
                      elevation: 0,
                      color: Colors.transparent,
                      child: child,
                    ),
                    onReorder: (oldIdx, newIdx) {
                      if (newIdx > oldIdx) newIdx--;
                      setInner(() {
                        final item = currentOrder.removeAt(oldIdx);
                        currentOrder.insert(newIdx, item);
                      });
                    },
                    children: [
                      for (int i = 0; i < currentOrder.length; i++)
                        ListTile(
                          key: ValueKey(currentOrder[i]),
                          dense: true,
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 4),
                          leading: ReorderableDragStartListener(
                            index: i,
                            child: const Icon(Icons.drag_handle,
                                color: Colors.white38, size: 20),
                          ),
                          title: Row(
                            children: [
                              const Icon(Icons.folder,
                                  color: Colors.white38, size: 16),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(currentOrder[i],
                                    style: const TextStyle(
                                        color: Colors.white, fontSize: 14)),
                              ),
                            ],
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // ⋮ button: open folder bottom sheet
                              GestureDetector(
                                onTap: () {
                                  final fn = currentOrder[i];
                                  Navigator.pop(ctx);
                                  _showFolderBottomSheet(
                                      fn, folderMap[fn] ?? [], floor);
                                },
                                child: const Padding(
                                  padding: EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  child: Icon(Icons.more_vert,
                                      color: Colors.white38, size: 20),
                                ),
                              ),
                              // X button: delete folder (with confirmation)
                              GestureDetector(
                                onTap: () async {
                                  final fn = currentOrder[i];
                                  final apps = folderMap[fn] ?? [];
                                  final confirm = await showDialog<bool>(
                                    context: context,
                                    builder: (c) => AlertDialog(
                                      backgroundColor:
                                          const Color(0xFF1A1A1A),
                                      title: Text(S.of(c).deleteFolderTitle(fn),
                                          style: const TextStyle(
                                              color: Colors.white)),
                                      content: Text(
                                        S.of(c).deleteFolderMessage(apps.length),
                                        style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 13),
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(c, false),
                                          child: Text(S.of(c).actionCancel,
                                              style: const TextStyle(
                                                  color: Colors.white54)),
                                        ),
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(c, true),
                                          child: Text(S.of(c).actionDelete,
                                              style: const TextStyle(
                                                  color: Colors.redAccent)),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (confirm == true) {
                                    for (final a in apps) {
                                      a.folderName = null;
                                      await widget.appService.saveConfig(a);
                                    }
                                    setInner(() => currentOrder.remove(fn));
                                    _loadApps();
                                  }
                                },
                                child: const Padding(
                                  padding: EdgeInsets.symmetric(
                                      horizontal: 4, vertical: 4),
                                  child: Icon(Icons.close,
                                      color: Colors.white38, size: 20),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(S.of(ctx).actionCancel,
                  style: const TextStyle(color: Colors.white54)),
            ),
            TextButton(
              onPressed: () async {
                if (positionType == 'top') {
                  await ss.setFixedTopFolderOrder(floor, currentOrder);
                } else {
                  await ss.setFixedBottomFolderOrder(floor, currentOrder);
                }
                if (ctx.mounted) Navigator.pop(ctx);
                setState(() {});
              },
              child: Text(S.of(ctx).actionDone,
                  style: const TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }
}
