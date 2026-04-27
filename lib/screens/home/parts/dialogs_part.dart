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
              _sheetItem(ctx, Icons.checklist, '複数選択モードに切り替え', () {
                Navigator.pop(ctx);
                setState(() {
                  _selectionMode = true;
                  _selectionInFavorites = isFavorite;
                  _reorderMode = false;
                  _selectedPackages.add(app.packageName);
                });
              }),
              _sheetItem(ctx, Icons.edit, '名前を変更', () {
                Navigator.pop(ctx);
                _showRenameDialog(app);
              }),
              _sheetItem(ctx, Icons.stairs, '階層を移動', () {
                Navigator.pop(ctx);
                _showMoveFloorDialog(app);
              }),
              _sheetItem(ctx, Icons.folder_open, 'フォルダに追加', () {
                Navigator.pop(ctx);
                _showFolderPicker(app, floor);
              }),
              if (app.isPinned)
                _sheetItem(ctx, Icons.star, 'お気に入りを解除', () {
                  Navigator.pop(ctx);
                  _unpinFromHome(app);
                }, color: Colors.amberAccent)
              else
                _sheetItem(ctx, Icons.star_outline, 'お気に入りに追加', () {
                  Navigator.pop(ctx);
                  _pinToHome(app);
                }),
              _sheetItem(ctx, Icons.info_outline, 'アプリ情報', () {
                Navigator.pop(ctx);
                DeviceApps.openAppSettings(app.packageName);
              }),
              _sheetItem(ctx, Icons.schedule, '自動移動',  () {
                Navigator.pop(ctx);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AutoMoveScreen(
                      settingsService: widget.settingsService,
                      packageNames: [app.packageName],
                      allApps: _allApps,
                    ),
                  ),
                ).then((_) { if (mounted) _loadApps(); });
              }),
              _sheetItem(ctx, Icons.delete_outline, 'アンインストール', () {
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
            _sheetItem(ctx, Icons.edit, 'フォルダ名を変更', () {
              Navigator.pop(ctx);
              _showRenameFolderDialog(folderName, apps, floor);
            }),
            _sheetItem(ctx, Icons.star_outline, 'お気に入りに追加', () {
              Navigator.pop(ctx);
              _pinFolderToHome(folderName);
            }),
            _sheetItem(ctx, Icons.swap_vert, 'フォルダの位置', () {
              Navigator.pop(ctx);
              _showFolderPositionDialog(folderName, apps);
            }),
            _sheetItem(ctx, Icons.delete_outline, 'フォルダを削除', () {
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
              Icon(icon, color: color.withOpacity(0.7), size: 22),
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
        title: const Text('名前を変更',
            style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: app.appName,
            hintStyle: const TextStyle(color: Colors.white38),
            filled: true,
            fillColor: Colors.white.withOpacity(0.07),
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
            child: const Text('キャンセル',
                style: TextStyle(color: Colors.white54)),
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
            child: const Text('完了',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    ctrl.dispose();
  }

  Future<void> _showMoveFloorDialog(AppConfig app) async {
    int selectedFloor = app.floor;
    final ug = widget.settingsService.undergroundFloors;
    final maxF = widget.settingsService.maxFloors;
    final floors = [
      for (int i = ug; i >= 1; i--) -i,
      for (int i = 1; i <= maxF; i++) i,
    ];
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInner) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          title: Text('階層を移動 — ${_displayName(app)}',
              style: const TextStyle(
                  color: Colors.white, fontSize: 14)),
          content: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: floors.map((f) {
              final sel = selectedFloor == f;
              return GestureDetector(
                onTap: () => setInner(() => selectedFloor = f),
                child: Container(
                  width: 44,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: sel ? Colors.white : Colors.transparent,
                    border: Border.all(
                        color:
                            sel ? Colors.white : Colors.white38),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(floorLabel(f),
                      style: TextStyle(
                          color: sel ? Colors.black : Colors.white54,
                          fontSize: 12)),
                ),
              );
            }).toList(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('キャンセル',
                  style: TextStyle(color: Colors.white54)),
            ),
            TextButton(
              onPressed: () async {
                final ss = widget.settingsService;
                // Check strict sub-mode: timer-before-apply
                if (ss.isFloorMoveLocked(app.packageName)) {
                  if (ss.strictSubType('floorMove') == 'block') {
                    if (ctx.mounted) Navigator.pop(ctx);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('フロア移動がロックされています')));
                    }
                    return;
                  }
                  // Timer mode: show countdown, apply only if confirmed
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (!mounted) return;
                  final confirmed = await showStrictTimerDialog(context, seconds: 10);
                  if (!confirmed || !mounted) return;
                  app.floor = selectedFloor;
                  await widget.appService.saveConfig(app);
                  _loadApps();
                  return;
                }
                // Not locked — apply immediately
                app.floor = selectedFloor;
                await widget.appService.saveConfig(app);
                if (ctx.mounted) Navigator.pop(ctx);
                _loadApps();
              },
              child: const Text('完了',
                  style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
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
          title: const Text('フォルダに追加',
              style: TextStyle(color: Colors.white)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (existing.isNotEmpty) ...[
                  const Text('既存のフォルダを選択',
                      style: TextStyle(
                          color: Colors.white54, fontSize: 12)),
                  const SizedBox(height: 8),
                  _folderOption(null, selected, '📂  フォルダなし',
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
                const Text('新しいフォルダ名',
                    style: TextStyle(
                        color: Colors.white54, fontSize: 12)),
                const SizedBox(height: 6),
                TextField(
                  controller: ctrl,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'フォルダ名を入力...',
                    hintStyle: const TextStyle(
                        color: Colors.white38, fontSize: 12),
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
                    if (v.isNotEmpty) setInner(() => selected = v);
                  },
                ),
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
              child: const Text('完了',
                  style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
    ctrl.dispose();
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
                ? Colors.white.withOpacity(0.1)
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

  // ── bulk move dialog ──────────────────────────────────────────

  Future<void> _showBulkMoveDialog() async {
    int? selectedFloor;
    final ug = widget.settingsService.undergroundFloors;
    final maxF = widget.settingsService.maxFloors;
    final floors = [
      for (int i = ug; i >= 1; i--) -i,
      for (int i = 1; i <= maxF; i++) i,
    ];
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInner) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          title: Text('${_selectedPackages.length}個のアプリを移動',
              style: const TextStyle(color: Colors.white, fontSize: 14)),
          content: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: floors.map((f) {
              final sel = selectedFloor == f;
              return GestureDetector(
                onTap: () => setInner(() => selectedFloor = f),
                child: Container(
                  width: 44,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: sel ? Colors.white : Colors.transparent,
                    border: Border.all(
                        color: sel ? Colors.white : Colors.white38),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(floorLabel(f),
                      style: TextStyle(
                          color: sel ? Colors.black : Colors.white54,
                          fontSize: 12)),
                ),
              );
            }).toList(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('キャンセル',
                  style: TextStyle(color: Colors.white54)),
            ),
            TextButton(
              onPressed: selectedFloor != null
                  ? () => Navigator.pop(ctx, selectedFloor)
                  : null,
              child: const Text('移動',
                  style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );

    if (result != null && mounted) {
      final ss = widget.settingsService;
      // Check if any selected app is locked
      final lockedPkgs = _selectedPackages.where((pkg) => ss.isFloorMoveLocked(pkg)).toList();
      final unlockedPkgs = _selectedPackages.where((pkg) => !ss.isFloorMoveLocked(pkg)).toList();

      // Apply immediately for unlocked apps
      for (final pkg in unlockedPkgs) {
        final app = _allApps.firstWhere((a) => a.packageName == pkg,
            orElse: () => AppConfig(packageName: pkg, appName: pkg, floor: 1));
        app.floor = result;
        await widget.appService.saveConfig(app);
      }

      // Handle locked apps with timer-before-apply
      if (lockedPkgs.isNotEmpty) {
        final anyBlock = lockedPkgs.any((pkg) => ss.strictSubType('floorMove') == 'block');
        if (anyBlock) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('一部のアプリはフロア移動がロックされています')));
          }
        } else {
          // Timer mode
          final confirmed = await showStrictTimerDialog(context, seconds: 10);
          if (confirmed && mounted) {
            for (final pkg in lockedPkgs) {
              final app = _allApps.firstWhere((a) => a.packageName == pkg,
                  orElse: () => AppConfig(packageName: pkg, appName: pkg, floor: 1));
              app.floor = result;
              await widget.appService.saveConfig(app);
            }
          }
        }
      }
      setState(() {
        _selectionMode = false;
        _selectedPackages.clear();
      });
      _loadApps();
    }
  }

  Future<void> _showBulkAutoMoveScreen() async {
    if (_selectedPackages.isEmpty) return;
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AutoMoveScreen(
          settingsService: widget.settingsService,
          packageNames: _selectedPackages.toList(),
          allApps: _allApps,
        ),
      ),
    );
    if (result == true && mounted) {
      setState(() {
        _selectionMode = false;
        _selectedPackages.clear();
      });
    }
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
          title: Text('${_selectedPackages.length}個をフォルダに追加',
              style: const TextStyle(color: Colors.white, fontSize: 14)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (existing.isNotEmpty) ...[
                  const Text('既存のフォルダを選択',
                      style: TextStyle(color: Colors.white54, fontSize: 12)),
                  const SizedBox(height: 8),
                  ...existing.map((name) => _folderOption(
                        name, selected, '📁  $name',
                        () => setInner(() { selected = name; ctrl.clear(); }),
                      )),
                  const SizedBox(height: 12),
                  const Divider(color: Colors.white12),
                  const SizedBox(height: 8),
                ],
                const Text('新しいフォルダ名',
                    style: TextStyle(color: Colors.white54, fontSize: 12)),
                const SizedBox(height: 6),
                TextField(
                  controller: ctrl,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'フォルダ名を入力...',
                    hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
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
                    if (v.isNotEmpty) setInner(() => selected = v);
                  },
                ),
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
              onPressed: selected != null || ctrl.text.isNotEmpty
                  ? () => Navigator.pop(
                        ctx,
                        ctrl.text.trim().isNotEmpty
                            ? ctrl.text.trim()
                            : selected,
                      )
                  : null,
              child: const Text('完了',
                  style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
    ctrl.dispose();

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
    final override = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: Text('「$name」はブロック中',
            style: const TextStyle(color: Colors.white, fontSize: 15)),
        content: const Text(
          'このアプリは現在ブロックされています。',
          style: TextStyle(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('閉じる',
                style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('緊急解除',
                style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (override == true && mounted) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          title: const Text('本当に解除しますか？',
              style: TextStyle(color: Colors.white)),
          content: const Text(
            '解除の記録が残ります。',
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
              child: const Text('解除して起動',
                  style: TextStyle(color: Colors.redAccent)),
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
        title: const Text('フォルダ名を変更',
            style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'フォルダ名',
            hintStyle:
                const TextStyle(color: Colors.white38),
            filled: true,
            fillColor: Colors.white.withOpacity(0.07),
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
            child: const Text('キャンセル',
                style: TextStyle(color: Colors.white54)),
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
            child: const Text('完了',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    ctrl.dispose();
  }

  Future<void> _deleteFolderConfirm(
      String folderName, List<AppConfig> apps) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: Text('「$folderName」を削除',
            style: const TextStyle(color: Colors.white)),
        content: Text(
          'フォルダを削除します。${apps.length}件のアプリはフォルダなしになります。',
          style: const TextStyle(
              color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('キャンセル',
                style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('削除',
                style: TextStyle(color: Colors.redAccent)),
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
    final options = [
      ('top', '最上部に固定'),
      ('alphabetical', '名前順（デフォルト）'),
      ('bottom', '最下部に固定'),
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
              Text('「$folderName」の表示位置',
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
              child: const Text('キャンセル',
                  style: TextStyle(color: Colors.white54)),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _setFolderPosition(apps, selected);
              },
              child: const Text('完了',
                  style: TextStyle(color: Colors.white)),
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

    final titleText = positionType == 'top' ? '最上部固定フォルダの順番' : '最下部固定フォルダの順番';

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
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text(
                    'ドラッグして順番を変更',
                    style: TextStyle(color: Colors.white38, fontSize: 12),
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
                                      title: Text('「$fn」を削除',
                                          style: const TextStyle(
                                              color: Colors.white)),
                                      content: Text(
                                        'フォルダを削除します。${apps.length}件のアプリはフォルダなしになります。',
                                        style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 13),
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(c, false),
                                          child: const Text('キャンセル',
                                              style: TextStyle(
                                                  color: Colors.white54)),
                                        ),
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(c, true),
                                          child: const Text('削除',
                                              style: TextStyle(
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
              child: const Text('キャンセル',
                  style: TextStyle(color: Colors.white54)),
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
              child: const Text('完了',
                  style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }
}
