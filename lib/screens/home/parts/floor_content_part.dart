part of '../home_screen.dart';

extension FloorContentMethods on _HomeScreenState {
  // ── gesture handling ──────────────────────────────────────────

  Future<void> _executeGestureAction(String? action) async {
    if (action == null) return;
    if (action == 'open_keyboard') {
      _searchFocusNode.requestFocus();
      return;
    }
    if (action == 'notification_panel') {
      await _native.expandNotificationPanel();
      return;
    }
    if (action == 'screen_off') {
      final adminEnabled = await _native.isDeviceAdminEnabled();
      if (adminEnabled) {
        await _native.lockScreen();
      } else {
        if (!mounted) return;
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF1A1A1A),
            title: Text(S.of(ctx).deviceAdminRequired,
                style: const TextStyle(color: Colors.white)),
            content: Text(
              S.of(ctx).screenOffNeedsAdmin,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(S.of(ctx).actionCancel,
                      style: const TextStyle(color: Colors.white54))),
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _native.openDeviceAdminSettings();
                },
                child: Text(S.of(ctx).openSettings,
                    style: const TextStyle(color: Colors.white)),
              ),
            ],
          ),
        );
      }
    } else {
      // it's a package name
      final app = _allApps.firstWhere(
        (a) => a.packageName == action,
        orElse: () =>
            AppConfig(packageName: action, appName: action, floor: 1),
      );
      await _launchWithMindfulDelay(app);
    }
  }

  void _handleHomeGestureUp(DragEndDetails details) {
    final vel = details.primaryVelocity ?? 0;
    if (vel < -300) {
      // swipe up
      _executeGestureAction(widget.settingsService.gestureUpApp);
    } else if (vel > 300) {
      // swipe down
      _executeGestureAction(widget.settingsService.gestureDownApp);
    }
  }

  // ── mindful delay ─────────────────────────────────────────────

  Future<void> _trackUsageCountFloor(AppConfig app) async {
    final ss = widget.settingsService;
    final rules = ss.usageCountFloorRules(app.packageName);
    if (rules.isEmpty) return;
    final newCount = await ss.incrementDailyLaunchCount(app.packageName);
    // Find highest threshold that newCount satisfies
    final sorted = [...rules]..sort((a, b) => b['threshold']!.compareTo(a['threshold']!));
    for (final rule in sorted) {
      if (newCount >= rule['threshold']!) {
        final targetFloor = rule['floor']!;
        if (app.floor != targetFloor) {
          app.floor = targetFloor;
          await widget.appService.saveConfig(app);
          if (mounted) setState(() {});
        }
        break;
      }
    }
  }

  Future<void> _launchWithMindfulDelay(AppConfig app) async {
    if (!app.mindfulDelay) {
      _launchedExternalApp = true;
      widget.appService.launchApp(app.packageName);
      _trackUsageCountFloor(app);
      return;
    }
    if (_mindfulActive) return;

    final secs = widget.settingsService.mindfulDelaySeconds;
    int remaining = secs;
    _mindfulCancelled = false;
    _mindfulActive = true;
    bool timerDone = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInner) {
          _mindfulTimer ??= Timer.periodic(const Duration(seconds: 1), (t) {
            if (!mounted || _mindfulCancelled) {
              t.cancel();
              _mindfulTimer = null;
              if (ctx.mounted) Navigator.of(ctx).pop();
              return;
            }
            remaining--;
            if (remaining <= 0) {
              timerDone = true;
              t.cancel();
              _mindfulTimer = null;
              if (ctx.mounted) Navigator.of(ctx).pop();
            } else {
              if (ctx.mounted) setInner(() {});
            }
          });

          return PopScope(
            canPop: true,
            onPopInvokedWithResult: (didPop, _) {
              if (didPop && !timerDone) {
                _mindfulCancelled = true;
                _mindfulTimer?.cancel();
                _mindfulTimer = null;
              }
            },
            child: AlertDialog(
              backgroundColor: const Color(0xFF1A1A1A),
              title: Text(_displayName(app),
                  style: const TextStyle(color: Colors.white)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(S.of(ctx).confirmOpenApp,
                      style: const TextStyle(color: Colors.white70, fontSize: 14)),
                  const SizedBox(height: 12),
                  Text(S.of(ctx).launchInSeconds(remaining),
                      style: const TextStyle(
                          color: Colors.amber,
                          fontSize: 24,
                          fontWeight: FontWeight.bold)),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    _mindfulCancelled = true;
                    _mindfulTimer?.cancel();
                    _mindfulTimer = null;
                    if (ctx.mounted) Navigator.of(ctx).pop();
                  },
                  child: Text(S.of(ctx).actionCancel,
                      style: const TextStyle(color: Colors.redAccent)),
                ),
              ],
            ),
          );
        },
      ),
    );

    _mindfulTimer?.cancel();
    _mindfulTimer = null;
    _mindfulActive = false;

    if (!_mindfulCancelled && mounted) {
      _launchedExternalApp = true;
      widget.appService.launchApp(app.packageName);
      _trackUsageCountFloor(app);
    }
  }

  // ── effective floor background ────────────────────────────────

  Color _effectiveFloorBg(int floor) {
    final custom = widget.settingsService.floorCustomBgValue(floor);
    if (custom != null) return Color(custom);
    return _floorBg(floor);
  }

  Color _effectiveFloorText(int floor) {
    final bg = _effectiveFloorBg(floor);
    if (bg.computeLuminance() > 0.5) return Colors.black;
    return _floorText(floor);
  }

  // ── font color (from settings) ────────────────────────────────
  Color get _fontColor => widget.settingsService.effectiveFontColor;

  // ── display name helper ───────────────────────────────────────
  String _displayName(AppConfig app) =>
      (app.customName?.isNotEmpty == true) ? app.customName! : app.appName;

  // ── apps for floor helper ─────────────────────────────────────
  List<AppConfig> _appsForFloor(int floor) {
    if (floor == _HomeScreenState._homeFloor) return [];
    if (floor == 1) {
      final normal = _allApps.where((a) => a.floor == 1).toList();
      // Add emergency 1F apps (apps from other floors temporarily shown on 1F)
      if (_emergency1FApps.isNotEmpty && _emergencyEndTime != null && _emergencyEndTime!.isAfter(DateTime.now())) {
        final emgApps = _allApps.where((a) =>
            _emergency1FApps.contains(a.packageName) && a.floor != 1).toList();
        // Merge without duplicates
        final seen = normal.map((a) => a.packageName).toSet();
        for (final a in emgApps) {
          if (!seen.contains(a.packageName)) {
            normal.add(a);
            seen.add(a.packageName);
          }
        }
      }
      return normal;
    }
    return _allApps.where((a) => a.floor == floor).toList();
  }

  // ── navigation ────────────────────────────────────────────────

  void _navigate(int newFloor, {required bool goingDeeper, bool slideH = false}) {
    if (_isAnimating) return;
    // Close all open folders when navigating between floors
    _openFolders.clear();

    // PageView handles HOME ↔ 1F transitions
    if (newFloor == 1 && (_currentFloor == _HomeScreenState._homeFloor || _currentFloor == 1)) {
      _pageCtrl.animateToPage(1, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
      setState(() => _currentFloor = 1);
      return;
    }
    if (newFloor == _HomeScreenState._homeFloor && _currentFloor == 1) {
      _pageCtrl.animateToPage(0, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
      setState(() => _currentFloor = _HomeScreenState._homeFloor);
      return;
    }
    if (newFloor == _HomeScreenState._homeFloor && _currentFloor == _HomeScreenState._homeFloor) return;

    _fromFloor = _currentFloor;
    _fromApps = _appsForFloor(_currentFloor);
    _isSlideAnim = slideH;
    setState(() {
      _currentFloor = newFloor;
      _goingUp = !goingDeeper;
      _isAnimating = true;
    });

    final ss = widget.settingsService;
    // Use per-pair speed if set, otherwise fall back to global speed
    final speedMs = slideH
        ? ss.animationSpeedMs
        : ss.effectiveAnimSpeedMs(_fromFloor, newFloor);

    if (slideH) {
      _slideCtrl.duration = Duration(milliseconds: (speedMs * 0.5).round().clamp(150, 600));
    } else {
      if (ss.animationType == 'none') {
        // Instant - just set state
        if (mounted) setState(() { _isAnimating = false; _fromApps = []; });
        return;
      }
      _ctrl.duration = Duration(milliseconds: speedMs);
    }

    final ctrl = slideH ? _slideCtrl : _ctrl;
    final targetFloor = newFloor;
    ctrl.reset();
    ctrl.forward().then((_) {
      if (mounted) {
        setState(() { _isAnimating = false; _fromApps = []; });
        // Sync PageController position when landing on HOME or 1F
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (targetFloor == 1 && _pageCtrl.hasClients) {
            _pageCtrl.jumpToPage(1);
          } else if (targetFloor == _HomeScreenState._homeFloor && _pageCtrl.hasClients) {
            _pageCtrl.jumpToPage(0);
          }
        });
      }
    });
  }

  void _goShallower() {
    if (_currentFloor > _minFloor) {
      // When underground floors exist and we're at 1F, skip HOME → go to B1F
      if (_currentFloor == 1 && _minFloor < _HomeScreenState._homeFloor) {
        _navigate(-1, goingDeeper: false);
      } else {
        _navigate(_currentFloor - 1, goingDeeper: false);
      }
    }
  }

  void _goDeeper() {
    if (_currentFloor < _maxFloor) {
      // When coming from underground B1F, skip HOME → go to 1F
      if (_currentFloor == -1) {
        _navigate(1, goingDeeper: true);
      } else {
        _navigate(_currentFloor + 1, goingDeeper: true);
      }
    }
  }

  void _goHome() {
    if (_currentFloor == _HomeScreenState._homeFloor) return;
    _navigate(_HomeScreenState._homeFloor, goingDeeper: false, slideH: true);
  }

  // ── home ↔ 1F view (PageView) ─────────────────────────────────

  Widget _buildHomeAnd1F() {
    final apps1F = _appsForFloor(1);

    return PageView(
      controller: _pageCtrl,
      onPageChanged: (page) {
        if (!_isAnimating) {
          _openFolders.clear();
          if (page == 0 && _searchQuery.isNotEmpty) {
            _searchCtrl.clear();
          }
          setState(() => _currentFloor = page == 0 ? _HomeScreenState._homeFloor : 1);
        }
      },
      children: [
        // Page 0: HOME
        GestureDetector(
          behavior: HitTestBehavior.translucent,
          onVerticalDragEnd: _handleHomeGestureUp,
          onDoubleTap: () => _executeGestureAction(
              widget.settingsService.gestureDoubleTapApp),
          child: _buildHomeBackground(child: _buildHomeContent()),
        ),
        // Page 1: 1F + stair nav
        _buildFloorBackground(1, child: Builder(builder: (ctx) {
          final statusBarH = MediaQuery.of(ctx).padding.top;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Column(
                  children: [
                    SizedBox(height: statusBarH),
                    // Search bar fades in as user swipes from home to 1F
                    AnimatedBuilder(
                      animation: _pageCtrl,
                      builder: (ctx2, child) {
                        double opacity = 0.0;
                        try {
                          if (_pageCtrl.hasClients) {
                            opacity = (_pageCtrl.page ?? 0.0).clamp(0.0, 1.0);
                          }
                        } catch (_) {}
                        if (opacity <= 0.0) return const SizedBox.shrink();
                        return Opacity(opacity: opacity, child: child!);
                      },
                      child: _searchBar(),
                    ),
                    Expanded(
                      child: _searchQuery.isNotEmpty
                          ? _buildSearchResults()
                          : _floorContent(1, apps1F),
                    ),
                  ],
                ),
              ),
              AnimatedBuilder(
                animation: _pageCtrl,
                builder: (ctx2, child) {
                  double opacity = 0.0;
                  if (_pageCtrl.hasClients && _pageCtrl.page != null) {
                    opacity = _pageCtrl.page!.clamp(0.0, 1.0);
                  }
                  return Opacity(opacity: opacity, child: child!);
                },
                child: Padding(
                  padding: EdgeInsets.fromLTRB(4, statusBarH + 16, 8, 16),
                  child: _buildStairNav(),
                ),
              ),
            ],
          );
        })),
      ],
    );
  }

  // ── folder helper ─────────────────────────────────────────────

  String? _folderOf(AppConfig app) =>
      (app.folderName?.isNotEmpty == true) ? app.folderName : null;

  // ── app tile ──────────────────────────────────────────────────

  Widget _appTile(AppConfig app, int floor,
      {VoidCallback? onLongPressOverride, Color? colorOverride}) {
    final now = DateTime.now();
    final isEmg = app.isEmergency &&
        app.emergencyUntil != null &&
        app.emergencyUntil!.isAfter(now);
    final notifCount = _notifCounts[app.packageName] ?? 0;
    final textColor = colorOverride ?? _effectiveFloorText(floor);
    final isSelected = _selectedPackages.contains(app.packageName);
    final ss = widget.settingsService;

    return Material(
      color: isSelected ? Colors.white.withOpacity(0.08) : Colors.transparent,
      child: InkWell(
        onTap: () {
          if (_selectionMode) {
            setState(() {
              if (isSelected) {
                _selectedPackages.remove(app.packageName);
              } else {
                _selectedPackages.add(app.packageName);
              }
            });
          } else {
            if (widget.settingsService.isAppBlocked(app.packageName)) {
              _showBlockedDialog(app);
            } else {
              _launchWithMindfulDelay(app);
            }
          }
        },
        onLongPress: () {
          if (onLongPressOverride != null) {
            onLongPressOverride();
          } else {
            _showAppBottomSheet(app, floor);
          }
        },
        child: Padding(
          padding: EdgeInsets.symmetric(
              horizontal: 16,
              vertical: ss.rowSpacing),
          child: Row(
            children: [
              if (_selectionMode)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: Checkbox(
                      value: isSelected,
                      activeColor: Colors.white,
                      checkColor: Colors.black,
                      side: BorderSide(
                          color: textColor.withOpacity(0.54)),
                      onChanged: (_) => setState(() {
                        if (isSelected) {
                          _selectedPackages.remove(app.packageName);
                        } else {
                          _selectedPackages.add(app.packageName);
                        }
                      }),
                    ),
                  ),
                ),
              Expanded(
                child: Text(
                  _displayName(app),
                  style: TextStyle(
                    color: isEmg ? Colors.redAccent : textColor,
                    fontSize: ss.fontSize,
                    fontWeight:
                        isEmg ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
              if (ss.lastUsedDisplayApps.contains(app.packageName))
                Builder(builder: (_) {
                  final label = formatLastUsedRelative(
                      _lastUsedMap[app.packageName],
                      now: _now);
                  if (label == null) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Text(
                      label,
                      style: TextStyle(
                        color: textColor.withOpacity(0.45),
                        fontSize: 11,
                      ),
                    ),
                  );
                }),
              if (notifCount > 0)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Text(
                    '($notifCount)',
                    style: TextStyle(
                      color: textColor.withOpacity(0.45),
                      fontSize: 12,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _folderTile(String name, List<AppConfig> apps, String key,
      bool isOpen, int floor, {VoidCallback? onLongPress}) {
    final ss = widget.settingsService;
    final textColor = _effectiveFloorText(floor);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => setState(() {
          if (widget.settingsService.singleFolderMode && !isOpen) {
            // Close all other open folders on this floor
            _openFolders.removeWhere((k) => k.startsWith('$floor:') && k != key);
          }
          isOpen ? _openFolders.remove(key) : _openFolders.add(key);
        }),
        onLongPress: onLongPress ?? () {
          final pos = apps.isNotEmpty ? apps.first.folderPosition : 'alphabetical';
          if (pos == 'top' || pos == 'bottom') {
            _showFolderOrderDialog(floor, pos);
          } else {
            _showFolderBottomSheet(name, apps, floor);
          }
        },
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Icon(
                isOpen ? Icons.folder_open : Icons.folder,
                color: textColor.withOpacity(0.54),
                size: 18,
              ),
              const SizedBox(width: 10),
              Text(name,
                  style: TextStyle(
                      color: textColor.withOpacity(0.70), fontSize: ss.fontSize)),
              const SizedBox(width: 6),
              Text(S.of(context).folderItemsCount(apps.length),
                  style: TextStyle(
                      color: textColor.withOpacity(0.38), fontSize: 12)),
              const Spacer(),
              Icon(
                isOpen ? Icons.expand_less : Icons.expand_more,
                color: textColor.withOpacity(0.38),
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Folder item row: shows ⋮ and ✕ only when selection mode is active; long press → bottom sheet
  Widget _folderItemTile(AppConfig app, int floor, String folderName) {
    final textColor = _effectiveFloorText(floor);
    final ss = widget.settingsService;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          if (_selectionMode) {
            setState(() {
              if (_selectedPackages.contains(app.packageName)) {
                _selectedPackages.remove(app.packageName);
              } else {
                _selectedPackages.add(app.packageName);
              }
            });
          } else {
            if (ss.isAppBlocked(app.packageName)) {
              _showBlockedDialog(app);
            } else {
              _launchWithMindfulDelay(app);
            }
          }
        },
        onLongPress: () {
          final key = '$floor:$folderName';
          final folderApps = _allApps
              .where((a) => a.floor == floor && a.folderName == folderName)
              .toList();
          setState(() {
            _openFolders.add(key);
            _reorderingFolderKey = key;
            _reorderingFolderApps = _orderedFolderApps(folderName, folderApps);
          });
        },
        child: Padding(
          padding: EdgeInsets.symmetric(
              horizontal: 16, vertical: ss.rowSpacing),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _displayName(app),
                  style: TextStyle(color: textColor, fontSize: ss.fontSize),
                ),
              ),
              if (ss.lastUsedDisplayApps.contains(app.packageName))
                Builder(builder: (_) {
                  final label = formatLastUsedRelative(
                      _lastUsedMap[app.packageName],
                      now: _now);
                  if (label == null) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Text(
                      label,
                      style: TextStyle(
                        color: textColor.withOpacity(0.45),
                        fontSize: 11,
                      ),
                    ),
                  );
                }),
              if (_selectionMode) ...[
                GestureDetector(
                  onTap: () => _showAppBottomSheet(app, floor),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Icon(Icons.more_vert,
                        color: textColor.withOpacity(0.38), size: 20),
                  ),
                ),
                GestureDetector(
                  onTap: () async {
                    app.folderName = null;
                    await widget.appService.saveConfig(app);
                    setState(() {});
                    _loadApps();
                  },
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                    child: Icon(Icons.close,
                        color: textColor.withOpacity(0.38), size: 20),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Wraps [child] in a KeyedSubtree with a GlobalKey, registering the key
  /// against [section] in [sectionKeys]. Used by the alphabet sidebar to
  /// scroll-to-section via Scrollable.ensureVisible.
  Widget _wrapSectionAnchor(String section,
      Map<String, GlobalKey>? sectionKeys, Widget child) {
    if (sectionKeys == null) return child;
    final key = GlobalKey();
    sectionKeys[section] = key;
    return KeyedSubtree(key: key, child: child);
  }

  List<Widget> _buildFloorWidgets(int floor, List<AppConfig> apps,
      [Map<String, GlobalKey>? sectionKeys]) {
    // Recently added section at top
    final ss = widget.settingsService;
    final recentApps = ss.showRecentlyAdded
        ? apps.where((a) => ss.isRecentlyAdded(a.packageName)).toList()
        : <AppConfig>[];

    final ungrouped = apps.where((a) => _folderOf(a) == null).toList()
      ..sort((a, b) {
        final nameA = _displayName(a);
        final nameB = _displayName(b);
        final ka = _sortKey(nameA);
        final kb = _sortKey(nameB);
        if (ka != kb) return ka.compareTo(kb);
        return nameA.compareTo(nameB);
      });

    final folderMap = <String, List<AppConfig>>{};
    for (final app in apps) {
      final fn = _folderOf(app);
      if (fn != null) folderMap.putIfAbsent(fn, () => []).add(app);
    }

    // Classify folders by folderPosition
    final topFolders = <String>[];
    final alphFolders = <String>[];
    final bottomFolders = <String>[];
    for (final fn in folderMap.keys) {
      switch (folderMap[fn]!.first.folderPosition) {
        case 'top':
          topFolders.add(fn);
          break;
        case 'bottom':
          bottomFolders.add(fn);
          break;
        default:
          alphFolders.add(fn);
      }
    }
    // Sort top/bottom folders by stored custom order; alphabetical folders by name
    final topOrder = ss.getFixedTopFolderOrder(floor);
    topFolders.sort((a, b) {
      final ia = topOrder.indexOf(a);
      final ib = topOrder.indexOf(b);
      if (ia == -1 && ib == -1) return a.compareTo(b);
      if (ia == -1) return 1;
      if (ib == -1) return -1;
      return ia.compareTo(ib);
    });
    alphFolders.sort();
    final bottomOrder = ss.getFixedBottomFolderOrder(floor);
    bottomFolders.sort((a, b) {
      final ia = bottomOrder.indexOf(a);
      final ib = bottomOrder.indexOf(b);
      if (ia == -1 && ib == -1) return a.compareTo(b);
      if (ia == -1) return 1;
      if (ib == -1) return -1;
      return ia.compareTo(ib);
    });

    final widgets = <Widget>[];
    String? lastSection;

    // 0. Recently added section
    if (recentApps.isNotEmpty) {
      widgets.add(SizedBox(
        height: 28,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(S.of(context).recentlyAddedSection,
                style: TextStyle(
                    color: _effectiveFloorText(floor).withOpacity(0.54),
                    fontSize: 12)),
          ),
        ),
      ));
      for (final app in recentApps) {
        widgets.add(_appTile(app, floor));
      }
      widgets.add(const SizedBox(height: 9, child: Divider(color: Colors.white12)));
    }

    // 0.5. Emergency apps section (only on 1F during emergency mode)
    if (floor == 1 && _emergency1FApps.isNotEmpty && _emergencyEndTime != null && _emergencyEndTime!.isAfter(DateTime.now())) {
      final emgColor = Color(ss.emergencyAppFontColor);
      final emgMode = ss.emergencyAppDisplayMode;
      final emgApps = apps.where((a) =>
          _emergency1FApps.contains(a.packageName) && a.floor != 1).toList();

      if (emgMode == 'section' && emgApps.isNotEmpty) {
        // Section display: grouped at top with header
        final header = SizedBox(
          height: 28,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(S.of(context).emergencyAppsSection,
                  style: TextStyle(color: emgColor.withOpacity(0.7), fontSize: 12)),
            ),
          ),
        );
        widgets.add(ss.emergencyAppShowIndex
            ? _wrapSectionAnchor('🚨', sectionKeys, header)
            : header);

        emgApps.sort((a, b) => _displayName(a).compareTo(_displayName(b)));
        String? lastEmgSec;
        for (final app in emgApps) {
          Widget tile = _appTile(app, floor, colorOverride: emgColor);
          if (ss.emergencyAppShowIndex) {
            final sec = _indexChar(_displayName(app));
            if (sec != lastEmgSec) {
              tile = _wrapSectionAnchor('🚨$sec', sectionKeys, tile);
              lastEmgSec = sec;
            }
          }
          widgets.add(tile);
        }
        widgets.add(const SizedBox(height: 9, child: Divider(color: Colors.white12)));

        // Remove emergency apps from ungrouped to avoid double-showing
        ungrouped.removeWhere((a) => _emergency1FApps.contains(a.packageName) && a.floor != 1);
      }
      // For 'normal' mode, emergency apps stay in ungrouped but with color override handled in tile rendering
    }

    // Helper: render one folder (header + expanded items if open)
    void addFolder(String fn) {
      final key = '$floor:$fn';
      final isOpen = _openFolders.contains(key);
      final isReordering = _reorderingFolderKey == key;

      widgets.add(_folderTile(fn, folderMap[fn]!, key, isOpen, floor,
        onLongPress: () {
          if (isOpen) {
            setState(() {
              _reorderingFolderKey = key;
              _reorderingFolderApps = _orderedFolderApps(fn, List.from(folderMap[fn]!));
            });
          } else {
            final pos = folderMap[fn]!.isNotEmpty ? folderMap[fn]!.first.folderPosition : 'alphabetical';
            if (pos == 'top' || pos == 'bottom') {
              _showFolderOrderDialog(floor, pos);
            } else {
              _showFolderBottomSheet(fn, folderMap[fn]!, floor);
            }
          }
        },
      ));

      if (isReordering) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(left: 20, right: 8),
          child: ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            proxyDecorator: (child, i, anim) => Material(elevation: 0, color: Colors.transparent, child: child),
            onReorder: (oldIdx, newIdx) async {
              if (newIdx > oldIdx) newIdx--;
              setState(() {
                final item = _reorderingFolderApps.removeAt(oldIdx);
                _reorderingFolderApps.insert(newIdx, item);
              });
              await widget.settingsService.setFolderOrder(
                fn,
                _reorderingFolderApps.map((a) => a.packageName).toList(),
              );
            },
            children: [
              for (int i = 0; i < _reorderingFolderApps.length; i++)
                _folderItemTileReorder(_reorderingFolderApps[i], floor, fn, i, key: ValueKey(_reorderingFolderApps[i].packageName)),
            ],
          ),
        ));
        widgets.add(Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton(
              onPressed: () => setState(() => _reorderingFolderKey = null),
              child: Text(S.of(context).actionDone, style: const TextStyle(color: Colors.white)),
            ),
          ),
        ));
      } else if (isOpen) {
        for (final app in _orderedFolderApps(fn, List.from(folderMap[fn]!))) {
          widgets.add(Padding(
            padding: const EdgeInsets.only(left: 20),
            child: _folderItemTile(app, floor, fn),
          ));
        }
      }
    }

    // 1. Top-pinned folders
    for (final fn in topFolders) {
      addFolder(fn);
    }

    // 2. Merge ungrouped apps and alphabetical folders in sorted order
    int appIdx = 0, fldIdx = 0;
    while (appIdx < ungrouped.length || fldIdx < alphFolders.length) {
      final hasApp = appIdx < ungrouped.length;
      final hasFld = fldIdx < alphFolders.length;
      final bool takeApp;
      if (hasApp && hasFld) {
        takeApp = _displayName(ungrouped[appIdx])
                .compareTo(alphFolders[fldIdx]) <=
            0;
      } else {
        takeApp = hasApp;
      }
      if (takeApp) {
        final app = ungrouped[appIdx++];
        final sec = _indexChar(_displayName(app));
        // Apply emergency color override for emergency 1F apps in 'normal' mode
        final isEmg1F = floor == 1 && _emergency1FApps.contains(app.packageName) && app.floor != 1
            && _emergencyEndTime != null && _emergencyEndTime!.isAfter(DateTime.now());
        Widget tile = _appTile(app, floor,
            colorOverride: isEmg1F ? Color(ss.emergencyAppFontColor) : null);
        if (sec != lastSection) {
          tile = _wrapSectionAnchor(sec, sectionKeys, tile);
          lastSection = sec;
        }
        widgets.add(tile);
      } else {
        final fn = alphFolders[fldIdx++];
        final sec = _indexChar(fn);
        // Folder section anchor: wrap as a separate sentinel just before the folder.
        if (sec != lastSection) {
          if (sectionKeys != null) {
            final key = GlobalKey();
            sectionKeys[sec] = key;
            widgets.add(KeyedSubtree(key: key, child: const SizedBox.shrink()));
          }
          lastSection = sec;
        }
        addFolder(fn);
      }
    }

    // 3. Bottom-pinned folders
    for (final fn in bottomFolders) {
      addFolder(fn);
    }

    if (widgets.isEmpty) {
      widgets.add(const SizedBox(height: 32));
      widgets.add(Center(
        child: Text(S.of(context).noAppsOnFloor,
            style: const TextStyle(color: Colors.white24, fontSize: 14)),
      ));
    }
    return widgets;
  }

  Widget _floorContent(int floor, List<AppConfig> apps) {
    if (floor == _HomeScreenState._homeFloor) return _buildHomeContent();

    final isCurrent = floor == _currentFloor;
    final isCurrentAndStill = isCurrent && !_isAnimating;

    final sectionKeys = isCurrentAndStill ? <String, GlobalKey>{} : null;
    final listItems = _buildFloorWidgets(floor, apps, sectionKeys);

    final navBarH = MediaQuery.of(context).viewPadding.bottom;
    final selectionBarH = _selectionMode ? 100.0 : 0.0;
    // Use ListView (not ListView.builder) so all section anchors are mounted in
    // the tree — required for Scrollable.ensureVisible via GlobalKey to work
    // for items that are currently off-screen.
    //
    // PageStorageKey persists the scroll offset across widget-tree shape
    // changes (e.g. when the listView moves from inside an animation Stack
    // to the top level once the transition completes), so a scroll the user
    // does mid-animation isn't snapped back to 0 on completion.
    //
    // Attach _scrollController to the current floor's listView even *during*
    // animation, so the controller's position survives the tree change too.
    final listView = ListView(
      key: PageStorageKey<int>(floor),
      controller: isCurrent ? _scrollController : null,
      padding: EdgeInsets.only(bottom: navBarH + 16 + selectionBarH),
      physics: const ClampingScrollPhysics(),
      children: [
        for (final item in listItems)
          Align(alignment: Alignment.centerLeft, child: item),
      ],
    );

    if (!isCurrentAndStill) return listView;

    // Add alphabet/あいうえお index sidebar for current non-animating floor
    return Row(
      children: [
        Expanded(child: listView),
        _buildIndexSidebar(apps, sectionKeys!),
      ],
    );
  }

  // ── animated content ──────────────────────────────────────────

  // ── content animation (unified with background movement) ────────────────────

  Widget _buildAnimatedContent(double floorH) {
    // For slide/stair: content slides in sync with the background (unified box).
    // For fade/zoom: content crossfades at fixed position.
    // For horizontal slide (HOME ↔ 1F): content slides horizontally.
    final screenW = MediaQuery.of(context).size.width;
    final currentApps = _appsForFloor(_currentFloor);
    final ss = widget.settingsService;
    final animType = _isSlideAnim ? 'slide' : ss.animationType;
    final animation = _isSlideAnim
        ? _slideAnim
        : (animType == 'stair' ? _stairAnim : _smoothAnim);

    return ClipRect(
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, _) {
          final p = animation.value;

          if (!_isAnimating) {
            return _floorContent(_currentFloor, currentApps);
          }

          // Horizontal slide (HOME ↔ 1F): slide content left/right
          if (_isSlideAnim) {
            final outX = _goingUp ? screenW * p : -screenW * p;
            final inX = _goingUp ? -screenW * (1.0 - p) : screenW * (1.0 - p);
            return Stack(children: [
              Transform.translate(offset: Offset(outX, 0),
                  child: SizedBox.expand(child: _floorContent(_fromFloor, _fromApps))),
              Transform.translate(offset: Offset(inX, 0),
                  child: SizedBox.expand(child: _floorContent(_currentFloor, currentApps))),
            ]);
          }

          // Slide / Stair: content slides vertically in sync with the background.
          // Both background (fullH) and content use the same offset, so they move
          // as one unified box — no visual gap or speed mismatch.
          if (animType == 'slide' || animType == 'stair') {
            final sp = animType == 'stair' ? _discreteStairAnim.value : p;
            final outY = _goingUp ? -floorH * sp : floorH * sp;
            final inY = _goingUp ? floorH * (1.0 - sp) : -floorH * (1.0 - sp);
            return Stack(children: [
              Transform.translate(offset: Offset(0, outY),
                  child: SizedBox.expand(child: _floorContent(_fromFloor, _fromApps))),
              Transform.translate(offset: Offset(0, inY),
                  child: SizedBox.expand(child: _floorContent(_currentFloor, currentApps))),
            ]);
          }

          // Fade / Zoom: crossfade content at fixed position.
          if (animType == 'zoom') {
            return Stack(children: [
              Opacity(opacity: (1.0 - p).clamp(0.0, 1.0),
                child: Transform.scale(scale: 1.0 - 0.08 * p,
                  child: SizedBox.expand(child: _floorContent(_fromFloor, _fromApps)))),
              Opacity(opacity: p.clamp(0.0, 1.0),
                child: Transform.scale(scale: 0.92 + 0.08 * p,
                  child: SizedBox.expand(child: _floorContent(_currentFloor, currentApps)))),
            ]);
          }
          // fade (default for all other types)
          return Stack(children: [
            Opacity(opacity: (1.0 - p).clamp(0.0, 1.0),
                child: SizedBox.expand(child: _floorContent(_fromFloor, _fromApps))),
            Opacity(opacity: p.clamp(0.0, 1.0),
                child: SizedBox.expand(child: _floorContent(_currentFloor, currentApps))),
          ]);
        },
      ),
    );
  }

  // ── floor row — background covers full width (content + stair nav) ────────

  Widget _buildFloorWithNav(double _ignored) {
    final ss = widget.settingsService;
    final animType = _isSlideAnim ? 'slide' : ss.animationType;
    final anim = _isSlideAnim
        ? _slideAnim
        : (animType == 'stair' ? _stairAnim : _smoothAnim);
    final screenW = MediaQuery.of(context).size.width;

    return LayoutBuilder(
      builder: (ctx, constraints) {
        final navH = constraints.maxHeight;
        return _buildFloorWithNavInner(navH, screenW, animType, anim);
      },
    );
  }

  Widget _buildFloorWithNavInner(
      double navH, double screenW, String animType, Animation<double> anim) {

    final statusBarH = MediaQuery.of(context).padding.top;
    // Use the full physical screen height for slide distance so backgrounds
    // cover the entire display including status bar and nav bar areas.
    final fullH = MediaQuery.of(context).size.height;

    // UI row (transparent — backgrounds handled at this level)
    // Content crossfades at fixed position; backgrounds slide with fullH.
    final uiContent = (_searchQuery.isNotEmpty && !_isAnimating)
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: statusBarH),
              _searchBar(),
              Expanded(child: _buildSearchResults()),
            ],
          )
        : Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(height: statusBarH),
                    // Keep search bar in layout during animation (invisible but
                    // maintaining size) so the app list position doesn't shift.
                    Opacity(opacity: _isAnimating ? 0.0 : 1.0, child: _searchBar()),
                    Expanded(child: _buildAnimatedContent(fullH)),
                  ],
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(4, statusBarH + 16, 8, 16),
                child: _buildStairNav(),
              ),
            ],
          );

    if (!_isAnimating) {
      // Wrap entire area (search bar + content + stair nav) with floor background
      return _buildFloorBackground(_currentFloor, child: uiContent);
    }

    // Animating: slide full-screen-height backgrounds behind content.
    // Use OverflowBox sized to fullH so each background covers the entire
    // physical screen, even though the widget's own constraints (navH) may
    // be smaller due to emergency banners or other layout elements.
    Widget fullBg(int floor, Offset offset) => Transform.translate(
          offset: offset,
          child: OverflowBox(
              minHeight: fullH,
              maxHeight: fullH,
              minWidth: screenW,
              maxWidth: screenW,
              child: _buildFloorBackground(floor, child: const SizedBox.shrink())),
        );

    return ClipRect(
      child: AnimatedBuilder(
        animation: anim,
        builder: (ctx, child) {
          final p = anim.value;

          if (animType == 'fade') {
            return Stack(children: [
              Opacity(opacity: (1.0 - p).clamp(0.0, 1.0),
                  child: fullBg(_fromFloor, Offset.zero)),
              Opacity(opacity: p.clamp(0.0, 1.0),
                  child: fullBg(_currentFloor, Offset.zero)),
              child!,
            ]);
          }

          if (animType == 'zoom') {
            return Stack(children: [
              Opacity(opacity: (1.0 - p).clamp(0.0, 1.0),
                  child: fullBg(_fromFloor, Offset.zero)),
              Opacity(opacity: p.clamp(0.0, 1.0),
                  child: fullBg(_currentFloor, Offset.zero)),
              child!,
            ]);
          }

          if (animType == 'stair') {
            final sp = _discreteStairAnim.value;
            final outY = _goingUp ? -fullH * sp : fullH * sp;
            final inY = _goingUp ? fullH * (1.0 - sp) : -fullH * (1.0 - sp);
            return Stack(children: [
              fullBg(_fromFloor, Offset(0, outY)),
              fullBg(_currentFloor, Offset(0, inY)),
              child!,
            ]);
          }

          // Default: slide — use fullH for vertical, screenW for horizontal
          double outX = 0, bgOutY = 0, inX = 0, bgInY = 0;
          if (_isSlideAnim) {
            outX = _goingUp ? screenW * p : -screenW * p;
            inX = _goingUp ? -screenW * (1.0 - p) : screenW * (1.0 - p);
          } else {
            bgOutY = _goingUp ? -fullH * p : fullH * p;
            bgInY = _goingUp ? fullH * (1.0 - p) : -fullH * (1.0 - p);
          }
          return Stack(children: [
            fullBg(_fromFloor, Offset(outX, bgOutY)),
            fullBg(_currentFloor, Offset(inX, bgInY)),
            child!,
          ]);
        },
        child: uiContent,
      ),
    );
  }

  // ── stair nav ─────────────────────────────────────────────────

  Widget _buildStairNav() {
    final canUp = _currentFloor < _maxFloor && !_isAnimating;
    final canDown = _currentFloor > _minFloor && !_isAnimating;
    final borderColor = _floorText(_currentFloor).withOpacity(0.7);
    final borderColorDim = _floorText(_currentFloor).withOpacity(0.12);
    final hasActive = _emergencyRemaining != null ||
        (_emergencyEndTime != null && _emergencyEndTime!.isAfter(DateTime.now()));

    final upLabel = canUp
        ? floorLabel(_currentFloor == -1 ? 1 : _currentFloor + 1)
        : '';
    final downLabel = canDown
        ? floorLabel(_currentFloor == 1 && _minFloor < _HomeScreenState._homeFloor
            ? -1
            : _currentFloor - 1)
        : '';

    return Column(
      children: [
        // Nav buttons centered vertically
        const Spacer(),
        _navBtn('▲', upLabel, canUp, _goDeeper,
            borderColor: borderColor, borderColorDim: borderColorDim),
        const SizedBox(height: 8),
        Container(
          width: 46,
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            border: Border.all(color: borderColor),
            borderRadius: BorderRadius.circular(4),
            color: Colors.transparent,
          ),
          child: Column(
            children: [
              Text(floorLabel(_currentFloor),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: _floorText(_currentFloor),
                      fontSize: 13,
                      fontWeight: FontWeight.bold)),
              Text(S.of(context).currentFloor,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: _floorText(_currentFloor).withOpacity(0.54),
                      fontSize: 9)),
            ],
          ),
        ),
        const SizedBox(height: 8),
        _navBtn('▼', downLabel, canDown, _goShallower,
            borderColor: borderColor, borderColorDim: borderColorDim),
        const Spacer(),
        // Emergency mode buttons: add + stop (only during emergency)
        if (hasActive) ...[
          _buildNavIconBtn(Icons.add_circle_outline, Colors.white54,
              () => _showEmergencyAddDialog()),
          const SizedBox(height: 4),
          _buildNavIconBtn(Icons.stop_circle_outlined, Colors.redAccent,
              () => _stopEmergencyMode()),
          const SizedBox(height: 4),
        ],
        // Emergency button (inactive mode) or settings gear
        if (!hasActive) ...[
          _buildEmergencyButton(),
          const SizedBox(height: 6),
        ],
        // Settings gear at bottom — add bottom margin so it stays above nav bar
        Padding(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewPadding.bottom + 40),
          child: _buildSettingsButton(),
        ),
      ],
    );
  }

  Widget _buildNavIconBtn(IconData icon, Color color, VoidCallback onTap) {
    return SizedBox(
      width: 46,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(4),
        child: InkWell(
          borderRadius: BorderRadius.circular(4),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              border: Border.all(color: color.withOpacity(0.3)),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Icon(icon, color: color, size: 16),
          ),
        ),
      ),
    );
  }

  /// Shows the 3-option add dialog (same as initial emergency dialog but adds to existing session)
  Future<void> _showEmergencyAddDialog() async {
    final ss = widget.settingsService;
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: Text(S.of(ctx).emergencyAddTitle, style: const TextStyle(color: Colors.redAccent, fontSize: 14)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(dense: true, contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.all_inclusive, color: Colors.redAccent, size: 20),
              title: Text(S.of(ctx).emergencyAddAllOn1F, style: const TextStyle(color: Colors.white, fontSize: 13)),
              onTap: () => Navigator.pop(ctx, 'all')),
            ListTile(dense: true, contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.star, color: Colors.orangeAccent, size: 20),
              title: Text(S.of(ctx).emergencyAddFromRegistered, style: const TextStyle(color: Colors.white, fontSize: 13)),
              onTap: () => Navigator.pop(ctx, 'registered')),
            ListTile(dense: true, contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.apps, color: Colors.white54, size: 20),
              title: Text(S.of(ctx).emergencyAppListPick, style: const TextStyle(color: Colors.white, fontSize: 13)),
              onTap: () => Navigator.pop(ctx, 'pick')),
          ],
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(S.of(ctx).actionCancel, style: const TextStyle(color: Colors.white54)))],
      ),
    );
    if (choice == null || !mounted) return;

    Set<String>? newPkgs;
    if (choice == 'all') {
      newPkgs = _allApps.map((a) => a.packageName).toSet();
    } else if (choice == 'registered') {
      final registered = ss.getEmergencyApps();
      if (registered.isEmpty) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(S.of(context).noEmergencyAppsRegistered)));
        return;
      }
      final candidates = _allApps
          .where((a) => registered.contains(a.packageName))
          .toList()
        ..sort((a, b) =>
            a.appName.toLowerCase().compareTo(b.appName.toLowerCase()));
      final picked =
          await _showAppCheckboxDialog(S.of(context).emergencyAddFromRegistered, candidates);
      if (picked == null || picked.isEmpty || !mounted) return;
      newPkgs = picked;
    } else if (choice == 'pick') {
      final apps = List<AppConfig>.from(_allApps)
        ..sort((a, b) =>
            a.appName.toLowerCase().compareTo(b.appName.toLowerCase()));
      final picked = await _showAppCheckboxDialog(S.of(context).selectApp, apps);
      if (picked == null || picked.isEmpty || !mounted) return;
      newPkgs = picked;
    }
    if (newPkgs == null || newPkgs.isEmpty || !mounted) return;

    final block = ss.checkEmergencyLimit(choice, newPkgs.toList());
    if (block != null) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(block)));
      }
      return;
    }
    ss.recordEmergencyUseV2(choice, newPkgs.toList());
    setState(() => _emergency1FApps.addAll(newPkgs!));
  }

  Widget _buildEmergencyButton() {
    final textColor = _floorText(_currentFloor);
    return SizedBox(
      width: 46,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(4),
        child: InkWell(
          borderRadius: BorderRadius.circular(4),
          onTap: () => _showEmergencyDialog(),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              border: Border.all(color: textColor.withOpacity(0.12)),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Icon(Icons.warning_amber_rounded,
                color: textColor.withOpacity(0.54), size: 16),
          ),
        ),
      ),
    );
  }

  void _stopEmergencyMode() {
    setState(() {
      _emergency1FApps.clear();
      _emergencyEndTime = null;
      // Also clear old-style emergency flags
      for (final app in _allApps) {
        if (app.isEmergency) {
          app.isEmergency = false;
          app.emergencyUntil = null;
          widget.appService.saveConfig(app);
        }
      }
    });
  }

  void _activateEmergency(String mode, Set<String> packages, int minutes) {
    final ss = widget.settingsService;
    ss.recordEmergencyUseV2(mode, packages.toList());
    setState(() {
      _emergency1FApps.addAll(packages);
      _emergencyEndTime = DateTime.now().add(Duration(minutes: minutes));
    });
  }

  /// Shows a checkbox picker over [candidates] and returns the user's
  /// selection, or null if cancelled.
  Future<Set<String>?> _showAppCheckboxDialog(
    String title,
    List<AppConfig> candidates,
  ) async {
    final selected = <String>{};
    return showDialog<Set<String>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInner) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          title: Text(title,
              style: const TextStyle(color: Colors.white, fontSize: 14)),
          content: SizedBox(
            width: double.maxFinite,
            height: 400,
            child: ListView.builder(
              itemCount: candidates.length,
              itemBuilder: (_, i) {
                final app = candidates[i];
                final name = app.customName?.isNotEmpty == true
                    ? app.customName!
                    : app.appName;
                final checked = selected.contains(app.packageName);
                return CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  activeColor: Colors.orangeAccent,
                  checkColor: Colors.black,
                  title: Text(name,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 13)),
                  subtitle: Text(floorLabel(app.floor),
                      style: const TextStyle(
                          color: Colors.white38, fontSize: 10)),
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
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(S.of(ctx).actionCancel,
                    style: const TextStyle(color: Colors.white54))),
            TextButton(
                onPressed: () =>
                    Navigator.pop(ctx, Set<String>.from(selected)),
                child: Text(S.of(ctx).actionDecide,
                    style: const TextStyle(color: Colors.white))),
          ],
        ),
      ),
    );
  }

  Future<void> _showEmergencyDialog() async {
    final ss = widget.settingsService;
    if (!ss.canActivateEmergency()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ss.emergencyLimitBlockMessage)));
      }
      return;
    }
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: Text(S.of(ctx).emergencyUseTitle, style: const TextStyle(color: Colors.redAccent, fontSize: 15)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(S.of(ctx).emergencyUseDescription,
                style: const TextStyle(color: Colors.white54, fontSize: 11)),
            const SizedBox(height: 12),
            ListTile(
              dense: true, contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.all_inclusive, color: Colors.redAccent, size: 20),
              title: Text(S.of(ctx).emergencyShowAllOn1F, style: const TextStyle(color: Colors.white, fontSize: 13)),
              onTap: () => Navigator.pop(ctx, 'all'),
            ),
            ListTile(
              dense: true, contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.star, color: Colors.orangeAccent, size: 20),
              title: Text(S.of(ctx).emergencyChooseRegistered, style: const TextStyle(color: Colors.white, fontSize: 13)),
              onTap: () => Navigator.pop(ctx, 'registered'),
            ),
            ListTile(
              dense: true, contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.apps, color: Colors.white54, size: 20),
              title: Text(S.of(ctx).emergencyAppListPick, style: const TextStyle(color: Colors.white, fontSize: 13)),
              onTap: () => Navigator.pop(ctx, 'pick'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(S.of(ctx).actionCancel, style: const TextStyle(color: Colors.white54))),
        ],
      ),
    );
    if (choice == null || !mounted) return;

    Set<String>? targetPkgs;
    if (choice == 'all') {
      targetPkgs = _allApps.map((a) => a.packageName).toSet();
    } else if (choice == 'registered') {
      final registered = ss.getEmergencyApps();
      if (registered.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(S.of(context).emergencyAppsRegisterHelp)));
        }
        return;
      }
      // Show picker so the user explicitly selects which registered apps to
      // enable on 1F (instead of defaulting to all of them).
      final candidates = _allApps
          .where((a) => registered.contains(a.packageName))
          .toList()
        ..sort((a, b) =>
            a.appName.toLowerCase().compareTo(b.appName.toLowerCase()));
      final picked = await _showAppCheckboxDialog(
          S.of(context).emergencyChooseRegistered, candidates);
      if (picked == null || picked.isEmpty || !mounted) return;
      targetPkgs = picked;
    } else if (choice == 'pick') {
      final apps = List<AppConfig>.from(_allApps)
        ..sort((a, b) => a.appName.toLowerCase().compareTo(b.appName.toLowerCase()));
      final picked =
          await _showAppCheckboxDialog(S.of(context).emergencyChooseTargetApps, apps);
      if (picked == null || picked.isEmpty || !mounted) return;
      targetPkgs = picked;
    }
    if (targetPkgs == null || targetPkgs.isEmpty) return;

    // Detailed limit check now that we know the chosen apps.
    final block = ss.checkEmergencyLimit(choice, targetPkgs.toList());
    if (block != null) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(block)));
      }
      return;
    }

    // Choose duration
    final duration = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: Text(S.of(ctx).selectDuration, style: const TextStyle(color: Colors.redAccent, fontSize: 14)),
        content: Text(S.of(ctx).emergencyDurationDescription,
            style: const TextStyle(color: Colors.white70, fontSize: 12)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(S.of(ctx).actionCancel, style: const TextStyle(color: Colors.white54))),
          TextButton(onPressed: () => Navigator.pop(ctx, 15), child: Text(S.of(ctx).minutesShort15, style: const TextStyle(color: Colors.orangeAccent))),
          TextButton(onPressed: () => Navigator.pop(ctx, 30), child: Text(S.of(ctx).minutesShort30, style: const TextStyle(color: Colors.orangeAccent))),
          TextButton(onPressed: () => Navigator.pop(ctx, 60), child: Text(S.of(ctx).minutesShort60, style: const TextStyle(color: Colors.redAccent))),
        ],
      ),
    );
    if (duration != null && mounted) {
      _activateEmergency(choice, targetPkgs, duration);
    }
  }

  Widget _buildSettingsButton() {
    final textColor = _floorText(_currentFloor);
    return SizedBox(
      width: 46,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(4),
        child: InkWell(
          borderRadius: BorderRadius.circular(4),
          onTap: () async {
            _isInExternalScreen = true;
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => SettingsScreen(
                  appService: widget.appService,
                  settingsService: widget.settingsService,
                ),
              ),
            );
            _isInExternalScreen = false;
            if (mounted) setState(() {});
            _loadApps();
            _startBatchTimer();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              border: Border.all(color: textColor.withOpacity(0.12)),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Icon(Icons.settings, color: textColor.withOpacity(0.54), size: 16),
          ),
        ),
      ),
    );
  }

  Widget _navBtn(
      String label, String sub, bool enabled, VoidCallback onTap,
      {Color borderColor = Colors.white70,
      Color borderColorDim = Colors.white12}) {
    return SizedBox(
      width: 46,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(4),
        child: InkWell(
          borderRadius: BorderRadius.circular(4),
          onTap: enabled ? onTap : null,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              border: Border.all(
                  color: enabled ? borderColor.withOpacity(0.38) : borderColorDim),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Column(
              children: [
                Text(label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: enabled
                            ? _floorText(_currentFloor)
                            : _floorText(_currentFloor).withOpacity(0.24),
                        fontSize: 14)),
                Text(enabled && sub.isNotEmpty ? sub : '',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: _floorText(_currentFloor).withOpacity(0.38),
                        fontSize: 9)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
