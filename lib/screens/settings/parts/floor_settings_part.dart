part of '../settings_screen.dart';

extension FloorSettingsMethods on _SettingsScreenState {
  // ── Floor range widget (f) ─────────────────────────────────────
  Widget _buildFloorRangeWidget() {
    final ss = _ss;
    final maxF = ss.maxFloors;
    final underF = ss.undergroundFloors;
    // Total floors: underground (B1..Bn) + above ground (1F..mF)
    // Underground displayed as negative indices
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Visual number line
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                // Underground floors (B1..Bn, shown right to left = BnF first)
                ...List.generate(underF, (i) {
                  final uFloor = underF - i; // BnF -> B1F
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.15),
                      border: Border.all(color: Colors.blueAccent.withOpacity(0.5)),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text('B${uFloor}F',
                        style: const TextStyle(color: Colors.blueAccent, fontSize: 11)),
                  );
                }),
                if (underF > 0)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4),
                    child: Text('│', style: TextStyle(color: Colors.white24, fontSize: 16)),
                  ),
                // Above-ground floors
                ...List.generate(maxF, (i) {
                  final floor = i + 1;
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.08),
                      border: Border.all(color: Colors.white24),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text('${floor}F',
                        style: const TextStyle(color: Colors.white70, fontSize: 11)),
                  );
                }),
              ],
            ),
          ),
          const SizedBox(height: 10),
          // Controls for max floors
          Row(
            children: [
              Text(S.of(context).maxFloorLabel, style: const TextStyle(color: Colors.white54, fontSize: 12)),
              const SizedBox(width: 8),
              _rangeStepButton(Icons.remove, () async {
                if (maxF > 1) { await ss.setMaxFloors(maxF - 1); setState(() {}); }
              }),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text('${maxF}F', style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
              ),
              _rangeStepButton(Icons.add, () async {
                if (maxF < 20) { await ss.setMaxFloors(maxF + 1); setState(() {}); }
              }),
              const SizedBox(width: 16),
              Text(S.of(context).undergroundLabel, style: const TextStyle(color: Colors.white54, fontSize: 12)),
              const SizedBox(width: 8),
              _rangeStepButton(Icons.remove, () async {
                if (underF > 0) { await ss.setUndergroundFloors(underF - 1); setState(() {}); }
              }),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text('B${underF}F', style: const TextStyle(color: Colors.blueAccent, fontSize: 13, fontWeight: FontWeight.w500)),
              ),
              _rangeStepButton(Icons.add, () async {
                if (underF < 10) { await ss.setUndergroundFloors(underF + 1); setState(() {}); }
              }),
            ],
          ),
        ],
      ),
    );
  }

  Widget _rangeStepButton(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28, height: 28,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white24),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Icon(icon, color: Colors.white54, size: 16),
      ),
    );
  }

  List<Widget> _kaisoSettingRows() {
    final s = S.of(context);
    final ss = _ss;

    // ── Animation summary ──
    final typeLabel = {
          'slide': s.animTypeSlide,
          'stair': s.animTypeStair,
          'fade': s.animTypeFade,
          'zoom': s.animTypeZoom,
          'none': s.noneLabel,
        }[ss.animationType] ??
        ss.animationType;
    final pairCount = _customizedPairCount();
    final animSummary = pairCount > 0
        ? s.animSummaryWithCustom(typeLabel, ss.animationSpeedMs, pairCount)
        : s.animSummary(typeLabel, ss.animationSpeedMs);

    // ── Recently added summary ──
    final recentSummary = ss.showRecentlyAdded
        ? s.enabledWithDays(ss.recentlyAddedDays)
        : s.actionDisabled;

    return [
      _expandableRow(
        key: 'kaiso_animation',
        title: s.animation,
        summary: animSummary,
        children: [_buildAnimationSection()],
      ),
      _rowDivider,
      _settingRow(s.singleFolderMode, ss.singleFolderMode ? s.actionEnabled : s.actionDisabled, () async {
        final v = await _showBoolDialog(s.singleFolderMode, ss.singleFolderMode);
        if (v != null) { await ss.setSingleFolderMode(v); setState(() {}); }
      }),
      _rowDivider,
      _expandableRow(
        key: 'kaiso_floorrange',
        title: s.floorRange,
        summary: ss.undergroundFloors > 0
            ? 'B${ss.undergroundFloors}F 〜 ${ss.maxFloors}F'
            : '1F 〜 ${ss.maxFloors}F',
        children: [_buildFloorRangeWidget()],
      ),
      _rowDivider,
      _expandableRow(
        key: 'kaiso_recent',
        title: s.recentlyAdded,
        summary: recentSummary,
        children: [
          SwitchListTile(
            contentPadding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            title: Text(s.recentlyAddedShow,
                style: const TextStyle(color: Colors.white, fontSize: 14)),
            subtitle: Text(ss.showRecentlyAdded ? s.actionEnabled : s.actionDisabled,
                style: const TextStyle(color: Colors.white54, fontSize: 12)),
            activeColor: Colors.tealAccent,
            value: ss.showRecentlyAdded,
            onChanged: (v) async {
              await ss.setShowRecentlyAdded(v);
              setState(() {});
            },
          ),
          if (ss.showRecentlyAdded)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(s.judgmentDaysLabel,
                          style: const TextStyle(color: Colors.white54, fontSize: 12)),
                      const SizedBox(width: 8),
                      Text(s.daysValue(ss.recentlyAddedDays),
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w500)),
                    ],
                  ),
                  Slider(
                    value: ss.recentlyAddedDays.toDouble(),
                    min: 1,
                    max: 30,
                    divisions: 29,
                    activeColor: Colors.tealAccent,
                    inactiveColor: Colors.white24,
                    onChanged: (v) async {
                      await ss.setRecentlyAddedDays(v.round());
                      setState(() {});
                    },
                  ),
                ],
              ),
            ),
        ],
      ),
      _rowDivider,
      _settingRow(s.alphabetIndex, ss.showAlphabetIndex ? s.actionEnabled : s.actionDisabled, () async {
        final v = await _showBoolDialog(s.alphabetIndex, ss.showAlphabetIndex);
        if (v != null) { await ss.setShowAlphabetIndex(v); setState(() {}); }
      }),
      _rowDivider,
      _settingRow(s.defaultNewAppFloor, floorLabel(ss.defaultNewAppFloor), () async {
        final ug = ss.undergroundFloors;
        final maxF = ss.maxFloors;
        final floors = [
          for (int i = ug; i >= 1; i--) -i,
          for (int i = 1; i <= maxF; i++) i,
        ];
        final v = await showDialog<int>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF1A1A1A),
            title: Text(S.of(ctx).defaultNewAppFloor,
                style: const TextStyle(color: Colors.white, fontSize: 14)),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView(
                shrinkWrap: true,
                children: floors.map((f) => ListTile(
                  dense: true,
                  title: Text(floorLabel(f),
                      style: TextStyle(
                          color: f == ss.defaultNewAppFloor ? Colors.tealAccent : Colors.white,
                          fontSize: 14)),
                  trailing: f == ss.defaultNewAppFloor
                      ? const Icon(Icons.check, color: Colors.tealAccent, size: 18)
                      : null,
                  onTap: () => Navigator.pop(ctx, f),
                )).toList(),
              ),
            ),
            actions: [TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(S.of(ctx).actionCancel, style: const TextStyle(color: Colors.white54)))],
          ),
        );
        if (v != null) { await ss.setDefaultNewAppFloor(v); setState(() {}); }
      }),
    ];
  }


  Future<void> _showBulkBgColorPicker() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: Text(S.of(ctx).bulkBackgroundChange, style: const TextStyle(color: Colors.white, fontSize: 15)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(S.of(ctx).bulkApplyAllMessage,
                style: const TextStyle(color: Colors.white54, fontSize: 12)),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.palette, color: Colors.white54),
              title: Text(S.of(ctx).selectColor, style: const TextStyle(color: Colors.white, fontSize: 13)),
              onTap: () => Navigator.pop(ctx, 'color'),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.image, color: Colors.white54),
              title: Text(S.of(ctx).selectWallpaper, style: const TextStyle(color: Colors.white, fontSize: 13)),
              onTap: () => Navigator.pop(ctx, 'wallpaper'),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.auto_awesome, color: Colors.white54),
              title: Text(S.of(ctx).defaultWallpaper, style: const TextStyle(color: Colors.white, fontSize: 13)),
              onTap: () => Navigator.pop(ctx, 'default_wallpaper'),
            ),
            if (_ss.homeWallpaper != null) ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.opacity, color: Colors.white54),
                title: Text(S.of(ctx).changeWallpaperOpacity, style: const TextStyle(color: Colors.white, fontSize: 13)),
                onTap: () => Navigator.pop(ctx, 'opacity'),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.delete, color: Colors.redAccent),
                title: Text(S.of(ctx).deleteWallpaper, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
                onTap: () => Navigator.pop(ctx, 'delete'),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx),
              child: Text(S.of(ctx).actionCancel, style: const TextStyle(color: Colors.white54))),
        ],
      ),
    );
    if (choice == 'color') {
      await _bulkApplyColor();
    } else if (choice == 'wallpaper') {
      await _bulkApplyWallpaper();
    } else if (choice == 'default_wallpaper') {
      await _showDefaultWallpaperPicker(context, (path) async {
        await _clearAllWallpapers();
        await _ss.setHomeWallpaper(path);
        for (var i = -_ss.undergroundFloors; i <= _ss.maxFloors; i++) {
          if (i == 0) continue;
          await _ss.setFloorWallpaper(i, path);
        }
        await _ss.setSettingsWallpaper(path);
        setState(() {});
      });
    } else if (choice == 'opacity') {
      await _showOverlayOpacitySlider(
        S.of(context).bulkOpacityTitle,
        _ss.homeOverlayOpacity,
        (v) async {
          await _ss.setHomeOverlayOpacity(v);
          for (var i = -_ss.undergroundFloors; i <= _ss.maxFloors; i++) {
            if (i == 0) continue;
            await _ss.setFloorOverlayOpacity(i, v);
          }
          await _ss.setSettingsOverlayOpacity(v);
        },
      );
      setState(() {});
    } else if (choice == 'delete') {
      await _clearAllWallpapers();
      setState(() {});
    }
  }

  Future<void> _clearAllWallpapers() async {
    await _ss.setWallpaperPath(null);
    await _ss.setHomeWallpaper(null);
    for (var i = -_ss.undergroundFloors; i <= _ss.maxFloors; i++) {
      if (i == 0) continue;
      await _ss.setFloorWallpaper(i, null);
    }
    await _ss.setSettingsWallpaper(null);
  }

  Future<void> _bulkApplyColor() async {
    final color = await _showSharedColorPicker(context);
    if (color == null || !mounted) return;
    // Clear all existing wallpapers first
    await _clearAllWallpapers();
    // Apply color to home
    await _ss.setHomeBackground(color);
    // Apply to all floors
    final colors = List<int?>.filled(_ss.maxFloors, color == Colors.transparent ? null : color.value);
    await _ss.applyThemePreset(colors);
    // Apply to settings background
    await _ss.setSettingsBackground(color);
    setState(() {});
  }

  Future<void> _bulkApplyWallpaper() async {
    final path = await _pickAndCropWallpaper(context);
    if (path == null || !mounted) return;
    // Clear all existing wallpapers first
    await _clearAllWallpapers();
    // Apply new wallpaper to home
    await _ss.setHomeWallpaper(path);
    // Apply to all floors (including underground)
    for (var i = -_ss.undergroundFloors; i <= _ss.maxFloors; i++) {
      if (i == 0) continue;
      await _ss.setFloorWallpaper(i, path);
    }
    // Apply to settings
    await _ss.setSettingsWallpaper(path);
    setState(() {});
  }
}

// ── Floor Background Screen ───────────────────────────────────────────────────

class _FloorBgScreen extends StatefulWidget {
  final SettingsService settingsService;
  const _FloorBgScreen({required this.settingsService});

  @override
  State<_FloorBgScreen> createState() => _FloorBgScreenState();
}

class _FloorBgScreenState extends State<_FloorBgScreen> {
  SettingsService get _ss => widget.settingsService;

  List<(int, String)> _presetColorsFor(BuildContext ctx) {
    final s = S.of(ctx);
    return [
      (0xFF000000, s.colorPureBlack), (0xFF1A1A1A, s.colorCharcoal), (0xFF333333, s.colorDarkGray),
      (0xFF666666, s.colorMediumGray), (0xFFAAAAAA, s.colorLightGray), (0xFFFFFFFF, s.colorWhite),
      (0xFF5C0000, s.colorDarkRed), (0xFFB22222, s.colorRedDeep), (0xFF8B2500, s.colorOrangeRed),
      (0xFF7A3500, s.colorDarkOrange), (0xFF4A2800, s.colorBrown), (0xFF4A0020, s.colorBurgundy),
      (0xFF000428, s.colorDarkNavy), (0xFF001F5B, s.colorNavy), (0xFF0A0A5C, s.colorDarkBlue),
      (0xFF191970, s.colorMidnightBlue), (0xFF003333, s.colorTeal), (0xFF003D3D, s.colorDarkCyan),
      (0xFF0A2E0A, s.colorForestGreen), (0xFF1A3D1A, s.colorDarkGreen),
      (0xFF2A3000, s.colorOlive), (0xFF004D00, s.colorHunterGreen),
      (0xFF1E0033, s.colorDarkPurple), (0xFF3D0066, s.colorPurple),
      (0xFF1A0066, s.colorIndigo), (0xFF3D003D, s.colorPlum),
      (0xFF2D0015, s.colorDarkMaroon), (0xFF3D001A, s.colorDarkWine),
      (0xFF2D1A2D, s.colorDarkMauve), (0xFF1A1A2E, s.colorDarkSlate), (0xFF1A2E1A, s.colorDarkMoss),
    ];
  }

  Future<void> _pickColor(int floor) async {
    final currentVal = _ss.floorCustomBgValue(floor);
    final current = currentVal != null ? Color(currentVal) : null;
    final color = await _showSharedColorPicker(context, current: current);
    if (!mounted) return;
    if (color == null) return;
    final argb = color == Colors.transparent ? null : color.value;
    await _ss.setFloorCustomBgValue(floor, argb);
    setState(() {});
  }

  Future<void> _pickWallpaper(int floor) async {
    final picker = ImagePicker();
    final xfile = await picker.pickImage(source: ImageSource.gallery);
    if (xfile == null || !mounted) return;
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => _WallpaperCropScreen(imagePath: xfile.path)),
    );
    if (result != null) {
      await _ss.setFloorWallpaper(floor, result);
      if (mounted) setState(() {});
    }
  }

  List<int> get _allFloors => [
    for (int i = _ss.undergroundFloors; i >= 1; i--) -i,
    for (int i = 1; i <= _ss.maxFloors; i++) i,
  ];

  Future<void> _pickColorAll() async {
    final color = await _showSharedColorPicker(context, current: null);
    if (!mounted || color == null) return;
    final argb = color == Colors.transparent ? null : color.value;
    for (final f in _allFloors) {
      await _ss.setFloorCustomBgValue(f, argb);
    }
    setState(() {});
  }

  Future<void> _pickWallpaperAll() async {
    final picker = ImagePicker();
    final xfile = await picker.pickImage(source: ImageSource.gallery);
    if (xfile == null || !mounted) return;
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => _WallpaperCropScreen(imagePath: xfile.path)),
    );
    if (result != null) {
      for (final f in _allFloors) {
        await _ss.setFloorWallpaper(f, result);
      }
      if (mounted) {
        // Show opacity slider after setting wallpaper
        await _showBulkOpacitySlider();
        setState(() {});
      }
    }
  }

  Future<void> _showBulkOpacitySlider() async {
    double opacity = _ss.floorOverlayOpacity(_allFloors.first);
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInner) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          title: Text(S.of(ctx).bulkOpacityTitle, style: const TextStyle(color: Colors.white, fontSize: 14)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${(opacity * 100).round()}%', style: const TextStyle(color: Colors.white70, fontSize: 13)),
              Slider(
                value: opacity, min: 0, max: 1, divisions: 20,
                activeColor: Colors.white, inactiveColor: Colors.white24,
                onChanged: (v) => setInner(() => opacity = v),
              ),
              Text(S.of(ctx).opacityScaleHint, style: const TextStyle(color: Colors.white38, fontSize: 11)),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(S.of(ctx).actionCancel, style: const TextStyle(color: Colors.white54))),
            TextButton(
              onPressed: () async {
                for (final f in _allFloors) {
                  await _ss.setFloorOverlayOpacity(f, opacity);
                }
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: Text(S.of(ctx).actionApply, style: const TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final presetColors = _presetColorsFor(context);
    final floors = _allFloors;
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0D0D),
        foregroundColor: Colors.white,
        title: Text(s.floorBackground, style: const TextStyle(color: Colors.white, fontSize: 16)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── 全階層一括変更 ──────────────────────────────────────
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.bulkAllFloorChange,
                    style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: _pickColorAll,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white70,
                        side: const BorderSide(color: Colors.white24),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      ),
                      icon: const Icon(Icons.palette, size: 14),
                      label: Text(s.bulkColorSet, style: const TextStyle(fontSize: 12)),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: _pickWallpaperAll,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white70,
                        side: const BorderSide(color: Colors.white24),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      ),
                      icon: const Icon(Icons.image, size: 14),
                      label: Text(s.bulkWallpaperSet, style: const TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _showBulkOpacitySlider,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: const BorderSide(color: Colors.white24),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  ),
                  icon: const Icon(Icons.opacity, size: 14),
                  label: Text(s.bulkOpacitySet, style: const TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ),
          const Divider(color: Colors.white12),
          const SizedBox(height: 4),
          // ── Per-floor settings ─────────────────────────────────
          ...floors.map((floor) {
          final label = floorLabel(floor);
          final bgVal = _ss.floorCustomBgValue(floor);
          final wallpaper = _ss.floorWallpaper(floor);
          return Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    // Color swatch
                    Container(
                      width: 24, height: 24,
                      decoration: BoxDecoration(
                        color: bgVal != null ? Color(bgVal) : Colors.transparent,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white38),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        bgVal != null
                            ? (presetColors.where((p) => p.$1 == bgVal).map((p) => p.$2).firstOrNull
                                ?? '#${bgVal.toRadixString(16).padLeft(8, '0').substring(2)}')
                            : s.noColorSet,
                        style: const TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                    ),
                    TextButton(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: () => _pickColor(floor),
                      child: Text(s.selectColor, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                    ),
                    if (bgVal != null)
                      GestureDetector(
                        onTap: () async { await _ss.setFloorCustomBgValue(floor, null); setState(() {}); },
                        child: const Icon(Icons.restart_alt, color: Colors.white38, size: 18),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    if (wallpaper != null && wallpaper.isNotEmpty) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: Image.file(
                          File(wallpaper),
                          height: 40, width: 60,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Slider(
                          value: _ss.floorOverlayOpacity(floor),
                          min: 0, max: 1, divisions: 20,
                          activeColor: Colors.white, inactiveColor: Colors.white24,
                          onChanged: (v) async {
                            await _ss.setFloorOverlayOpacity(floor, v);
                            setState(() {});
                          },
                        ),
                      ),
                      TextButton(
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: () async { await _ss.setFloorWallpaper(floor, null); setState(() {}); },
                        child: Text(s.actionDelete, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
                      ),
                    ] else ...[
                      const Expanded(child: SizedBox()),
                    ],
                    OutlinedButton.icon(
                      onPressed: () => _pickWallpaper(floor),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white70,
                        side: const BorderSide(color: Colors.white24),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      ),
                      icon: const Icon(Icons.image, size: 14),
                      label: Text(s.selectWallpaper, style: const TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
                const Divider(color: Colors.white12),
              ],
            ),
          );
        }).toList(),
        ],
      ),
    );
  }
}

