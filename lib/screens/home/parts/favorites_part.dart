part of '../home_screen.dart';

extension FavoritesMethods on _HomeScreenState {
  // ── pin folder to home ────────────────────────────────────────
  Future<void> _pinFolderToHome(String folderName) async {
    final ss = widget.settingsService;
    final pinned = ss.pinnedFolderNames;
    if (!pinned.contains(folderName)) {
      pinned.add(folderName);
      await ss.setPinnedFolderNames(pinned);
      setState(() {});
    }
  }

  // ── ordering helpers ──────────────────────────────────────────

  List<_FavItem> _orderedFavoriteItems() {
    final ss = widget.settingsService;
    final pinnedApps = _allApps.where((a) => a.isPinned).toList();
    final order = ss.favoriteOrder;
    pinnedApps.sort((a, b) {
      final ia = order.indexOf(a.packageName);
      final ib = order.indexOf(b.packageName);
      if (ia == -1 && ib == -1) return _displayName(a).compareTo(_displayName(b));
      if (ia == -1) return 1;
      if (ib == -1) return -1;
      return ia.compareTo(ib);
    });

    final pinnedFolderNames = ss.pinnedFolderNames;

    final items = <_FavItem>[];
    // Interleave based on favorite order
    for (final entry in order) {
      if (pinnedFolderNames.contains(entry)) {
        items.add(_FavItem.folder(entry));
      } else {
        final matches = pinnedApps.where((a) => a.packageName == entry);
        if (matches.isNotEmpty) items.add(_FavItem.app(matches.first));
      }
    }
    // Add any not yet in order
    for (final app in pinnedApps) {
      if (!order.contains(app.packageName)) items.add(_FavItem.app(app));
    }
    for (final fn in pinnedFolderNames) {
      if (!order.contains(fn)) items.add(_FavItem.folder(fn));
    }
    return items;
  }

  List<AppConfig> _orderedFavorites() =>
      _orderedFavoriteItems().where((i) => !i.isFolder).map((i) => i.app!).toList();

  List<AppConfig> _orderedFolderApps(String folderName, List<AppConfig> apps) {
    final order = widget.settingsService.getFolderOrder(folderName);
    if (order.isEmpty) {
      return apps..sort((a, b) => _displayName(a).compareTo(_displayName(b)));
    }
    final pkgSet = apps.map((a) => a.packageName).toSet();
    final ordered = order
        .where((pkg) => pkgSet.contains(pkg))
        .map((pkg) => apps.firstWhere((a) => a.packageName == pkg))
        .toList();
    for (final a in apps) {
      if (!order.contains(a.packageName)) ordered.add(a);
    }
    return ordered;
  }

  // ── favorite folder tile (home screen) ────────────────────────
  Widget _favoriteFolderTile(String folderName) {
    final folderApps = _allApps.where((a) => a.folderName == folderName).toList();
    final key = 'home:$folderName';
    final isOpen = _openFolders.contains(key);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: () => setState(() => isOpen ? _openFolders.remove(key) : _openFolders.add(key)),
          onLongPress: () {
            showModalBottomSheet(
              context: context,
              backgroundColor: const Color(0xFF1A1A1A),
              builder: (ctx) => SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _sheetItem(ctx, Icons.star, S.of(ctx).removeFromFavoritesShort, () async {
                      Navigator.pop(ctx);
                      final ss = widget.settingsService;
                      final pinned = ss.pinnedFolderNames;
                      pinned.remove(folderName);
                      await ss.setPinnedFolderNames(pinned);
                      setState(() {});
                    }, color: Colors.amberAccent),
                  ],
                ),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Icon(isOpen ? Icons.folder_open : Icons.folder, color: _fontColor.withOpacity(0.54), size: 16),
                const SizedBox(width: 8),
                Text(folderName, style: TextStyle(color: _fontColor.withOpacity(0.8), fontSize: 14)),
                const SizedBox(width: 4),
                Text('(${folderApps.length})', style: TextStyle(color: _fontColor.withOpacity(0.4), fontSize: 11)),
                const Spacer(),
                Icon(isOpen ? Icons.expand_less : Icons.expand_more, color: _fontColor.withOpacity(0.4), size: 14),
              ],
            ),
          ),
        ),
        if (isOpen)
          ...folderApps.map((app) => Padding(
            padding: const EdgeInsets.only(left: 16),
            child: _appTile(app, 0),
          )),
      ],
    );
  }

  // ── reorder mode tile (favorites) ────────────────────────────

  Widget _favoriteTileReorder(AppConfig app, int index) {
    final textColor = _effectiveFloorText(0);
    return Material(
      key: ValueKey(app.packageName),
      color: Colors.transparent,
      child: Padding(
        padding: EdgeInsets.symmetric(
            horizontal: 16, vertical: widget.settingsService.rowSpacing),
        child: Row(
          children: [
            ReorderableDragStartListener(
              index: index,
              child: const Icon(Icons.drag_handle,
                  color: Colors.white38, size: 20),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _displayName(app),
                style: TextStyle(
                    color: textColor,
                    fontSize: widget.settingsService.fontSize),
              ),
            ),
            GestureDetector(
              onTap: () => _showAppBottomSheet(app, app.floor, isFavorite: true),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Icon(Icons.more_vert, color: Colors.white38, size: 20),
              ),
            ),
            GestureDetector(
              onTap: () => _unpinFromHome(app),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: Icon(Icons.close, color: Colors.white38, size: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── folder item tile (reorder mode) ──────────────────────────

  Widget _folderItemTileReorder(AppConfig app, int floor, String folderName, int index, {Key? key}) {
    final textColor = _effectiveFloorText(floor);
    final ss = widget.settingsService;
    return Material(
      key: key,
      color: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Row(
          children: [
            ReorderableDragStartListener(
              index: index,
              child: Icon(Icons.drag_handle, color: textColor.withOpacity(0.38), size: 20),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(_displayName(app), style: TextStyle(color: textColor, fontSize: ss.fontSize)),
            ),
            GestureDetector(
              onTap: () => _showAppBottomSheet(app, floor),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Icon(Icons.more_vert, color: textColor.withOpacity(0.38), size: 20),
              ),
            ),
            GestureDetector(
              onTap: () async {
                app.folderName = null;
                await widget.appService.saveConfig(app);
                setState(() {
                  _reorderingFolderApps.remove(app);
                });
                _loadApps();
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: Icon(Icons.close, color: textColor.withOpacity(0.38), size: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── pin / unpin ───────────────────────────────────────────────

  Future<void> _pinToHome(AppConfig app) async {
    app.isPinned = true;
    await widget.appService.saveConfig(app);
    _loadApps();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(S.of(context).addedToFavorites(_displayName(app)))),
      );
    }
  }

  Future<void> _unpinFromHome(AppConfig app) async {
    app.isPinned = false;
    await widget.appService.saveConfig(app);
    if (_reorderMode) {
      setState(() => _cachedFavorites
          .removeWhere((a) => a.packageName == app.packageName));
    }
    _loadApps();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(S.of(context).removedFromFavorites(_displayName(app)))),
      );
    }
  }

  Future<void> _bulkUnpinFromHome() async {
    for (final pkg in _selectedPackages) {
      final app = _allApps.firstWhere(
        (a) => a.packageName == pkg,
        orElse: () => AppConfig(packageName: pkg, appName: pkg, floor: 1),
      );
      if (app.isPinned) {
        app.isPinned = false;
        await widget.appService.saveConfig(app);
      }
    }
    setState(() {
      _selectionMode = false;
      _selectionInFavorites = false;
      _selectedPackages.clear();
    });
    _loadApps();
  }

  Future<void> _bulkPinToHome() async {
    for (final pkg in _selectedPackages) {
      final app = _allApps.firstWhere(
        (a) => a.packageName == pkg,
        orElse: () => AppConfig(packageName: pkg, appName: pkg, floor: 1),
      );
      if (!app.isPinned) {
        app.isPinned = true;
        await widget.appService.saveConfig(app);
      }
    }
    setState(() {
      _selectionMode = false;
      _selectionInFavorites = false;
      _selectedPackages.clear();
    });
    _loadApps();
  }

}
