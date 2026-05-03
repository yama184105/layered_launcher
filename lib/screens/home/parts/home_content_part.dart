part of '../home_screen.dart';

extension HomeContentMethods on _HomeScreenState {
  // ── notifications init ────────────────────────────────────────

  Future<void> _initNotifications() async {
    const androidInit =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    await _flnp.initialize(
        const InitializationSettings(android: androidInit));
  }

  Future<void> _checkNotifPerm() async {
    if (_notifPermAsked) return;
    _notifPermAsked = true;
    final enabled = await _native.isNotificationServiceEnabled();
    if (!enabled && mounted) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          title: Text(S.of(ctx).notificationAccessTitle,
              style: const TextStyle(color: Colors.white)),
          content: Text(
            S.of(ctx).notificationAccessMessage,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(S.of(ctx).actionLater,
                    style: const TextStyle(color: Colors.white54))),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _native.openNotificationAccessSettings();
              },
              child: Text(S.of(ctx).openSettings,
                  style: const TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
    }
  }

  // ── batch timer ───────────────────────────────────────────────

  void _startBatchTimer() {
    _batchTimer?.cancel();
    final ss = widget.settingsService;
    final interval =
        Duration(minutes: ss.batchIntervalMinutes);
    _batchTimer = Timer.periodic(interval, (_) => _processBatchNotifs());
  }

  Future<void> _processBatchNotifs() async {
    final ss = widget.settingsService;
    final batchApps = ss.batchApps;
    if (batchApps.isEmpty) return;
    final counts = await _native.getNotificationCounts();
    for (final pkg in batchApps) {
      final count = counts[pkg] ?? 0;
      if (count > 0) {
        final app = _allApps.firstWhere(
          (a) => a.packageName == pkg,
          orElse: () =>
              AppConfig(packageName: pkg, appName: pkg, floor: 1),
        );
        final name = (app.customName?.isNotEmpty == true)
            ? app.customName!
            : app.appName;
        if (!mounted) continue;
        final s = S.of(context);
        await _flnp.show(
          pkg.hashCode,
          s.appNotification(name),
          s.notificationCountBody(count),
          NotificationDetails(
            android: AndroidNotificationDetails(
              'batch_channel',
              s.batchNotificationChannel,
              importance: Importance.defaultImportance,
              priority: Priority.defaultPriority,
            ),
          ),
        );
      }
    }
  }

  // ── home widget loading ───────────────────────────────────────

  Future<void> _loadHomeWidgets() async {
    // Notifications
    final counts = await _native.getNotificationCounts();
    if (mounted) setState(() => _notifCounts = counts);

    // Battery
    final battery = await _native.getBatteryLevel();
    if (mounted) setState(() => _batteryLevel = battery);

    // Screen time
    final usageGranted = await _native.isUsageStatsPermissionGranted();
    if (mounted) setState(() => _usagePermGranted = usageGranted);
    if (usageGranted) {
      final screenTime = await _native.getTodayScreenTime();
      if (mounted) setState(() => _screenTimeMinutes = screenTime);
    }

    // Weather
    await _loadWeather();

    // Calendar
    await _loadCalendar();
  }

  Future<void> _loadWeather() async {
    try {
      double lat = 35.68;
      double lon = 139.69;
      final loc = await _native.getLastKnownLocation();
      if (loc != null) {
        lat = loc['lat']!;
        lon = loc['lon']!;
      }
      final url = Uri.parse(
          'https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lon&current_weather=true&timezone=auto');
      await http.get(url).timeout(const Duration(seconds: 8));
    } catch (_) {
      // weather fetch failed – nothing to update
    }
  }

  Future<void> _loadCalendar() async {
    try {
      await _native.getCalendarEvents();
      // calendar events fetched – no display target yet
    } catch (_) {
      // calendar fetch failed – nothing to update
    }
  }

  // ── charging timer ────────────────────────────────────────────

  void _startChargingTimer() {
    _chargingCheckTimer?.cancel();
    _chargingCheckTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      final charging = await _native.isCharging();
      if (mounted) setState(() => _isCharging = charging);
    });
    // Check immediately
    _native.isCharging().then((v) {
      if (mounted) setState(() => _isCharging = v);
    });
  }

  // ── clock / date format helpers ───────────────────────────────

  String _formatClock() {
    final ss = widget.settingsService;
    final fmt = ss.clockFormat;
    final h = _now.hour.toString().padLeft(2, '0');
    final min = _now.minute.toString().padLeft(2, '0');
    final sec = _now.second.toString().padLeft(2, '0');
    if (fmt == 'HH:mm') return '$h:$min';
    return '$h:$min:$sec';
  }

  String _formatDate() {
    final s = S.of(context);
    final wd = [s.weekdayMon, s.weekdayTue, s.weekdayWed, s.weekdayThu, s.weekdayFri, s.weekdaySat, s.weekdaySun];
    final ss = widget.settingsService;
    final fmt = ss.dateFormatString;
    // Simple substitution-based formatter
    return fmt
        .replaceAll('yyyy', _now.year.toString())
        .replaceAll('MM', _now.month.toString().padLeft(2, '0'))
        .replaceAll('M', _now.month.toString())
        .replaceAll('dd', _now.day.toString().padLeft(2, '0'))
        .replaceAll('d', _now.day.toString())
        .replaceAll('E', wd[_now.weekday - 1]);
  }

  // ── data helpers ──────────────────────────────────────────────

  Future<void> _loadApps() async {
    final apps = await widget.appService.getAllApps(
        defaultFloor: widget.settingsService.defaultNewAppFloor);
    if (!mounted) return;
    setState(() {
      _allApps = apps;
      _loading = false;
    });
    _tick();
  }

  void _tick() {
    if (!mounted) return;
    _now = DateTime.now();
    final now = _now;
    Duration? earliest;
    bool changed = false;
    for (final app in _allApps) {
      if (app.isEmergency && app.emergencyUntil != null) {
        final rem = app.emergencyUntil!.difference(now);
        if (rem.isNegative) {
          app.emergencyUntil = null;
          app.save();
          changed = true;
        } else if (earliest == null || rem < earliest) {
          earliest = rem;
        }
      }
    }
    // Check new emergency 1F mode expiry
    if (_emergencyEndTime != null) {
      if (_emergencyEndTime!.isBefore(now)) {
        _emergency1FApps.clear();
        _emergencyEndTime = null;
        changed = true;
      }
    }
    if (!widget.settingsService.isLockCooldownActive &&
        widget.settingsService.hasPendingFloorChanges) {
      widget.settingsService
          .applyPendingFloorChanges(widget.appService.box)
          .then((_) {
        if (mounted) _loadApps();
      });
    }
    // Auto-move check (once per minute)
    final currentMinute = now.hour * 60 + now.minute;
    if (currentMinute != _lastAutoMoveMinute) {
      _lastAutoMoveMinute = currentMinute;
      _processAutoMoves();
    }
    // Refresh lastTimeUsed cache once per minute when any apps are configured
    if (currentMinute != _lastUsedFetchMinute &&
        widget.settingsService.lastUsedDisplayApps.isNotEmpty) {
      _lastUsedFetchMinute = currentMinute;
      _native.getLastTimeUsedMap().then((m) {
        if (!mounted || m.isEmpty) return;
        setState(() => _lastUsedMap = m);
      });
    }
    setState(() {
      _emergencyRemaining = earliest;
      if (changed) _allApps = List.of(_allApps);
    });
  }

  // ── screen time format helper ─────────────────────────────────

  String _fmtScreenTime(int minutes) {
    if (minutes < 0) return '';
    final s = S.of(context);
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h > 0) return s.screenTimeHM(h, m);
    return s.screenTimeM(m);
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  // ── home background (wallpaper or solid color) ─────────────────

  Widget _buildHomeBackground({required Widget child}) {
    final ss = widget.settingsService;
    final wallpaperPath = ss.homeWallpaper;
    if (wallpaperPath != null && wallpaperPath.isNotEmpty) {
      final file = File(wallpaperPath);
      return Stack(
        fit: StackFit.expand,
        children: [
          Image.file(file, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox.shrink()),
          ColoredBox(color: Colors.black.withOpacity(ss.homeOverlayOpacity)),
          child,
        ],
      );
    }
    final bg = ss.homeBackground ?? Colors.black;
    return ColoredBox(color: bg, child: child);
  }

  Widget _buildFloorBackground(int floor, {required Widget child}) {
    final ss = widget.settingsService;
    final wallpaper = ss.floorWallpaper(floor);
    if (wallpaper != null && wallpaper.isNotEmpty) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Image.file(File(wallpaper), fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox.shrink()),
          ColoredBox(color: Colors.black.withOpacity(ss.floorOverlayOpacity(floor))),
          child,
        ],
      );
    }
    return ColoredBox(color: _effectiveFloorBg(floor), child: child);
  }

  // ── home floor (0) ────────────────────────────────────────────

  Widget _buildHomeContent() {
    final ss = widget.settingsService;
    final textColor = _fontColor;
    final clockFontSize = ss.clockSize == 'large'
        ? 48.0
        : ss.clockSize == 'small'
            ? 32.0
            : 40.0;
    TextStyle clockStyle() {
      final base = TextStyle(
        color: textColor,
        fontSize: clockFontSize,
        fontWeight: FontWeight.w200,
        fontFeatures: const [FontFeature.tabularFigures()],
      );
      final ff = ss.fontFamily;
      if (ff.isEmpty) return base;
      try {
        return GoogleFonts.getFont(ff, textStyle: base);
      } catch (_) {
        return base;
      }
    }

    // Compute circle size from clock + date text metrics so the ring
    // always fits the content regardless of font size setting.
    final clockTp = TextPainter(
      text: TextSpan(text: _formatClock(), style: clockStyle()),
      textDirection: TextDirection.ltr,
    )..layout();
    final dateTp = TextPainter(
      text: TextSpan(
          text: _formatDate(),
          style: TextStyle(color: textColor.withOpacity(0.54), fontSize: 13)),
      textDirection: TextDirection.ltr,
    )..layout();
    final contentW = max(clockTp.width, dateTp.width);
    final contentH = clockTp.height + 4 + dateTp.height;
    // Circle diameter = diagonal of the content box + padding on each side
    final diagonal = sqrt(contentW * contentW + contentH * contentH);
    final circleSize = diagonal + 60; // 30px padding on each side

    final clockCircle = Center(
      child: SizedBox(
        width: circleSize,
        height: circleSize,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Background circle + optional charging arc
            _isCharging && ss.chargingAnimationEnabled
                ? AnimatedBuilder(
                    animation: _chargingAnim,
                    builder: (ctx, _) => CustomPaint(
                      painter: _HomeClockPainter(
                        animValue: _chargingAnim.value,
                        isCharging: true,
                      ),
                      child: const SizedBox.expand(),
                    ),
                  )
                : CustomPaint(
                    painter: _HomeClockPainter(
                      animValue: 0.0,
                      isCharging: false,
                    ),
                    child: const SizedBox.expand(),
                  ),
            // Clock + date inside circle
            GestureDetector(
              onTap: ss.showAlarmShortcut
                  ? () {
                      final pkg = ss.alarmShortcutPackage;
                      if (pkg.isNotEmpty) {
                        widget.appService.launchApp(pkg);
                      } else {
                        _native.openAlarmClock();
                      }
                    }
                  : null,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_formatClock(), style: clockStyle()),
                  const SizedBox(height: 4),
                  Text(
                    _formatDate(),
                    style: TextStyle(
                        color: textColor.withOpacity(0.54), fontSize: 13),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    // Status info below circle: battery + screen time (always visible when available)
    final hasStatusInfo = _batteryLevel >= 0 ||
        (_usagePermGranted && _screenTimeMinutes >= 0) ||
        !_usagePermGranted;

    final statusInfo = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_batteryLevel >= 0)
          Text('🔋 $_batteryLevel%',
              style: TextStyle(color: textColor.withOpacity(0.6), fontSize: 12)),
        if (_usagePermGranted && _screenTimeMinutes >= 0)
          Text('📱 ${_fmtScreenTime(_screenTimeMinutes)}',
              style: TextStyle(color: textColor.withOpacity(0.6), fontSize: 12)),
        if (!_usagePermGranted)
          GestureDetector(
            onTap: () => _native.openUsageStatsSettings(),
            child: Text(S.of(context).usageStatsPermissionRequired,
                style: TextStyle(color: Colors.amber.withOpacity(0.8), fontSize: 11)),
          ),
      ],
    );

    final favoriteItems = _orderedFavoriteItems();

    Widget? favoritesWidget;
    if (favoriteItems.isNotEmpty) {
      if (_reorderMode) {
        favoritesWidget = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                S.of(context).dragToReorder,
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ),
            ReorderableListView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              proxyDecorator: (child, index, animation) => Material(
                elevation: 0,
                color: Colors.transparent,
                child: child,
              ),
              onReorder: (oldIdx, newIdx) async {
                if (newIdx > oldIdx) newIdx--;
                setState(() {
                  final item = _cachedFavorites.removeAt(oldIdx);
                  _cachedFavorites.insert(newIdx, item);
                });
                await widget.settingsService.setFavoriteOrder(
                  _cachedFavorites.map((a) => a.packageName).toList(),
                );
              },
              children: [
                for (int i = 0; i < _cachedFavorites.length; i++)
                  _favoriteTileReorder(_cachedFavorites[i], i),
              ],
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => setState(() => _reorderMode = false),
                child: Text(S.of(context).actionDone,
                    style: const TextStyle(color: Colors.white)),
              ),
            ),
          ],
        );
      } else {
        favoritesWidget = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: favoriteItems.map((item) {
            if (item.isFolder) {
              return _favoriteFolderTile(item.folderName!);
            }
            return _appTile(item.app!, item.app!.floor, onLongPressOverride: () {
              setState(() {
                _reorderMode = true;
                _cachedFavorites = _orderedFavorites();
              });
            });
          }).toList(),
        );
      }
    }

    // Layout: large clock circle → status info → gesture strip → favorites → gesture strip → shortcuts
    final statusBarH = MediaQuery.of(context).padding.top;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Large clock circle at top — push below status bar
        Padding(
          padding: EdgeInsets.fromLTRB(0, statusBarH + 16, 0, 0),
          child: clockCircle,
        ),
        // Status info (battery + screen time) below circle
        if (hasStatusInfo)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: statusInfo,
          ),
        // Top gesture strip (above favorites) — catches swipe/double-tap gestures
        GestureDetector(
          behavior: HitTestBehavior.translucent,
          onVerticalDragEnd: _handleHomeGestureUp,
          onDoubleTap: () =>
              _executeGestureAction(ss.gestureDoubleTapApp),
          child: const SizedBox(height: 40, width: double.infinity),
        ),
        // Favorites in middle (scroll-only, no gesture conflict)
        if (favoritesWidget != null)
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
              child: favoritesWidget,
            ),
          )
        else
          const Spacer(),
        // Bottom gesture strip (below favorites, above shortcuts)
        GestureDetector(
          behavior: HitTestBehavior.translucent,
          onVerticalDragEnd: _handleHomeGestureUp,
          onDoubleTap: () =>
              _executeGestureAction(ss.gestureDoubleTapApp),
          child: const SizedBox(height: 40, width: double.infinity),
        ),
        // Phone / Camera shortcuts at bottom — above nav bar
        if (ss.showDialShortcut || ss.showCameraShortcut)
          Padding(
            padding: EdgeInsets.fromLTRB(4, 0, 4, MediaQuery.of(context).viewPadding.bottom + 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (ss.showDialShortcut)
                  IconButton(
                    onPressed: () {
                      final pkg = ss.dialShortcutPackage;
                      pkg.isNotEmpty ? widget.appService.launchApp(pkg) : _native.openDial();
                    },
                    icon: Icon(Icons.phone, color: _fontColor, size: 28),
                    padding: const EdgeInsets.all(12),
                  ),
                if (!ss.showDialShortcut) const SizedBox.shrink(),
                if (ss.showCameraShortcut)
                  IconButton(
                    onPressed: () {
                      final pkg = ss.cameraShortcutPackage;
                      pkg.isNotEmpty ? widget.appService.launchApp(pkg) : _native.openCamera();
                    },
                    icon: Icon(Icons.camera_alt, color: _fontColor, size: 28),
                    padding: const EdgeInsets.all(12),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
