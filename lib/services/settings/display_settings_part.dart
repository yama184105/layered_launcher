part of '../settings_service.dart';

extension DisplaySettings on SettingsService {
  // ── Clock Format ───────────────────────────────────────────────────────────
  String get clockFormat => (_box.get('clockFormat') as String?) ?? 'HH:mm:ss';
  Future<void> setClockFormat(String v) => _box.put('clockFormat', v);

  // ── Clock Size ─────────────────────────────────────────────────────────────
  /// Values: 'normal' | 'large' | 'small'. Default 'normal'.
  String get clockSize => (_box.get('clockSize') as String?) ?? 'normal';
  Future<void> setClockSize(String v) => _box.put('clockSize', v);

  // ── Date Format ────────────────────────────────────────────────────────────
  /// Values: 'long' | 'short'
  String get dateFormat => (_box.get('dateFormat') as String?) ?? 'long';
  Future<void> setDateFormat(String v) => _box.put('dateFormat', v);

  // ── Date Format (full format string) ──────────────────────────────────────
  String get dateFormatString => (_box.get('dateFormatString') as String?) ?? 'M/d (E)';
  Future<void> setDateFormatString(String v) => _box.put('dateFormatString', v);

  // ── Animation Settings ─────────────────────────────────────────────────────
  /// Values: 'slide' | 'fade' | 'zoom' | 'none'
  String get animationType => (_box.get('animationType') as String?) ?? 'slide';
  Future<void> setAnimationType(String v) => _box.put('animationType', v);

  /// Duration in milliseconds for floor-to-floor transitions. Default 600.
  int get animationSpeedMs => (_box.get('animationSpeedMs') as int?) ?? 600;
  Future<void> setAnimationSpeedMs(int v) => _box.put('animationSpeedMs', v);

  // ── Per floor-pair animation speed ────────────────────────────────────────
  /// Key format: 'floorPairSpeed_{lower}_{higher}' where lower <= higher.
  int? floorPairSpeedMs(int from, int to) {
    final lo = from < to ? from : to;
    final hi = from < to ? to : from;
    return _box.get('floorPairSpeed_${lo}_$hi') as int?;
  }
  Future<void> setFloorPairSpeedMs(int from, int to, int ms) {
    final lo = from < to ? from : to;
    final hi = from < to ? to : from;
    return _box.put('floorPairSpeed_${lo}_$hi', ms);
  }
  Future<void> clearFloorPairSpeedMs(int from, int to) {
    final lo = from < to ? from : to;
    final hi = from < to ? to : from;
    return _box.delete('floorPairSpeed_${lo}_$hi');
  }
  /// Clears all per-pair speeds (used when applying global speed).
  Future<void> clearAllFloorPairSpeeds() async {
    final keys = _box.keys.where((k) => k.toString().startsWith('floorPairSpeed_')).toList();
    for (final k in keys) { await _box.delete(k); }
  }
  /// Effective speed for a transition between two floors.
  int effectiveAnimSpeedMs(int from, int to) =>
      floorPairSpeedMs(from, to) ?? animationSpeedMs;

  String? get pendingAnimationType =>
      _box.get('pendingAnimationType') as String?;
  int? get pendingAnimationSpeedMs =>
      _box.get('pendingAnimationSpeedMs') as int?;

  DateTime? get _animCooldownUntil {
    final ms = _box.get('animCooldownUntil') as int?;
    return ms != null ? DateTime.fromMillisecondsSinceEpoch(ms) : null;
  }

  bool get isAnimCooldownActive {
    final u = _animCooldownUntil;
    return u != null && u.isAfter(DateTime.now());
  }

  Duration? get animCooldownRemaining {
    final u = _animCooldownUntil;
    if (u == null) return null;
    final rem = u.difference(DateTime.now());
    return rem.isNegative ? null : rem;
  }

  /// Requests an animation change. Returns false if speed change is blocked/cooldown active.
  /// Animation TYPE changes are always allowed (not locked).
  /// Animation SPEED changes are subject to the 'animation' strict sub-mode.
  Future<bool> requestAnimationChange(String? type, int? speedMs) async {
    // Type changes are always free — apply immediately
    if (type != null) {
      await _box.put('animationType', type);
    }

    // Speed changes go through lock checks
    if (speedMs != null) {
      // Check new strict sub-mode (speed only)
      if (strictSubEnabled('animation')) {
        if (strictSubType('animation') == 'block') return false;
        if (isStrictSubCooldownActive('animation')) return false;
        await _box.put('pendingAnimationSpeedMs', speedMs);
        await startStrictSubCooldown('animation');
        return true;
      }
      // Legacy lock mode fallback
      if (isAnimCooldownActive) return false;
      if (lockModeEnabled) {
        await _box.put('pendingAnimationSpeedMs', speedMs);
        await _box.put(
            'animCooldownUntil',
            DateTime.now()
                .add(const Duration(seconds: 10))
                .millisecondsSinceEpoch);
      } else {
        await _box.put('animationSpeedMs', speedMs);
      }
    }
    return true;
  }

  Future<void> applyPendingAnimationChange() async {
    final t = pendingAnimationType;
    final s = pendingAnimationSpeedMs;
    if (t != null) await _box.put('animationType', t);
    if (s != null) await _box.put('animationSpeedMs', s);
    await _box.delete('pendingAnimationType');
    await _box.delete('pendingAnimationSpeedMs');
    await _box.delete('animCooldownUntil');
  }

  // ── Appearance ─────────────────────────────────────────────────────────────
  /// App tile font size. Default 15.0
  double get fontSize {
    final v = _box.get('fontSize');
    if (v == null) return 15.0;
    return (v as num).toDouble();
  }
  Future<void> setFontSize(double v) => _box.put('fontSize', v);

  /// Row vertical padding in app tile. Default 11.0
  double get rowSpacing {
    final v = _box.get('rowSpacing');
    if (v == null) return 11.0;
    return (v as num).toDouble();
  }
  Future<void> setRowSpacing(double v) => _box.put('rowSpacing', v);

  /// Whether to show the alphabet/kana index sidebar. Default true.
  bool get showAlphabetIndex =>
      (_box.get('showAlphabetIndex') as bool?) ?? true;
  Future<void> setShowAlphabetIndex(bool v) =>
      _box.put('showAlphabetIndex', v);

  /// Values: 'text' | 'border' | 'filled'. Default 'border'.
  String get floorButtonStyle =>
      (_box.get('floorButtonStyle') as String?) ?? 'border';
  Future<void> setFloorButtonStyle(String v) =>
      _box.put('floorButtonStyle', v);

  /// Per-floor custom background color (stored as int ARGB value).
  int? floorCustomBgValue(int floor) =>
      _box.get('floorBgColor_$floor') as int?;

  Future<void> setFloorCustomBgValue(int floor, int? argb) async {
    if (argb == null) {
      await _box.delete('floorBgColor_$floor');
    } else {
      await _box.put('floorBgColor_$floor', argb);
    }
  }

  // ── Home Layout ────────────────────────────────────────────────────────────
  /// Values: 'top' | 'center' | 'bottom'. Default 'top'.
  String get homeClockPosition =>
      (_box.get('homeClockPosition') as String?) ?? 'top';
  Future<void> setHomeClockPosition(String v) =>
      _box.put('homeClockPosition', v);

  /// Values: 'above' | 'below'. Default 'below'.
  String get homeShortcutPosition =>
      (_box.get('homeShortcutPosition') as String?) ?? 'below';
  Future<void> setHomeShortcutPosition(String v) =>
      _box.put('homeShortcutPosition', v);

  /// Number of shortcut apps shown on HOME. 0-10. Default 5.
  int get homeShortcutCount =>
      (_box.get('homeShortcutCount') as int?) ?? 5;
  Future<void> setHomeShortcutCount(int v) =>
      _box.put('homeShortcutCount', v);

  // ── Home Shortcuts ──────────────────────────────────────────────────────────
  bool get showDialShortcut => (_box.get('showDialShortcut') as bool?) ?? false;
  Future<void> setShowDialShortcut(bool v) => _box.put('showDialShortcut', v);
  bool get showCameraShortcut => (_box.get('showCameraShortcut') as bool?) ?? false;
  Future<void> setShowCameraShortcut(bool v) => _box.put('showCameraShortcut', v);
  bool get showAlarmShortcut => (_box.get('showAlarmShortcut') as bool?) ?? true;
  Future<void> setShowAlarmShortcut(bool v) => _box.put('showAlarmShortcut', v);

  // Custom app packages for shortcuts (empty = use default intent)
  String get dialShortcutPackage => (_box.get('dialShortcutPackage') as String?) ?? '';
  Future<void> setDialShortcutPackage(String v) => _box.put('dialShortcutPackage', v);
  String get cameraShortcutPackage => (_box.get('cameraShortcutPackage') as String?) ?? '';
  Future<void> setCameraShortcutPackage(String v) => _box.put('cameraShortcutPackage', v);
  String get alarmShortcutPackage => (_box.get('alarmShortcutPackage') as String?) ?? '';
  Future<void> setAlarmShortcutPackage(String v) => _box.put('alarmShortcutPackage', v);

  // ── Charging Animation ─────────────────────────────────────────────────────
  bool get chargingAnimationEnabled => (_box.get('chargingAnimationEnabled') as bool?) ?? true;
  Future<void> setChargingAnimationEnabled(bool v) => _box.put('chargingAnimationEnabled', v);

  // ── Font Family ────────────────────────────────────────────────────────────
  String get fontFamily => (_box.get('fontFamily') as String?) ?? '';
  Future<void> setFontFamily(String v) => _box.put('fontFamily', v);

  // ── Font Color ─────────────────────────────────────────────────────────────
  /// Values: 'white' | 'black'
  String get fontColor => (_box.get('fontColor') as String?) ?? 'white';
  Future<void> setFontColor(String v) => _box.put('fontColor', v);
  Color get effectiveFontColor => fontColor == 'black' ? Colors.black : Colors.white;

  // ── Wallpaper ──────────────────────────────────────────────────────────────
  String? get wallpaperPath => _box.get('wallpaperPath') as String?;
  Future<void> setWallpaperPath(String? v) async {
    if (v == null) {
      await _box.delete('wallpaperPath');
    } else {
      await _box.put('wallpaperPath', v);
    }
  }
  double get wallpaperOverlayOpacity {
    final v = _box.get('wallpaperOverlayOpacity');
    if (v == null) return 0.5;
    return (v as num).toDouble();
  }
  Future<void> setWallpaperOverlayOpacity(double v) => _box.put('wallpaperOverlayOpacity', v);

  // ── Home Background ────────────────────────────────────────────────────────
  Color? get homeBackground {
    final v = _box.get('homeBackground') as int?;
    return v != null ? Color(v) : null;
  }
  Future<void> setHomeBackground(Color? c) async {
    if (c == null) await _box.delete('homeBackground');
    else await _box.put('homeBackground', c.value);
  }
  String? get homeWallpaper => (_box.get('homeWallpaper') as String?) ?? wallpaperPath;
  Future<void> setHomeWallpaper(String? v) async {
    if (v == null) { await _box.delete('homeWallpaper'); } else { await _box.put('homeWallpaper', v); }
  }
  double get homeOverlayOpacity {
    final v = _box.get('homeOverlayOpacity');
    if (v != null) return (v as num).toDouble();
    return wallpaperOverlayOpacity; // fallback to old key
  }
  Future<void> setHomeOverlayOpacity(double v) => _box.put('homeOverlayOpacity', v);

  // ── Per-floor Wallpaper / Overlay ──────────────────────────────────────────
  String? floorWallpaper(int floor) => _box.get('floorWallpaper_$floor') as String?;
  Future<void> setFloorWallpaper(int floor, String? v) async {
    if (v == null) await _box.delete('floorWallpaper_$floor');
    else await _box.put('floorWallpaper_$floor', v);
  }
  double floorOverlayOpacity(int floor) {
    final v = _box.get('floorOverlayOpacity_$floor');
    return v != null ? (v as num).toDouble() : 0.3;
  }
  Future<void> setFloorOverlayOpacity(int floor, double v) =>
      _box.put('floorOverlayOpacity_$floor', v);

  // ── Settings Background ────────────────────────────────────────────────────
  Color? get settingsBackground {
    final v = _box.get('settingsBackground') as int?;
    return v != null ? Color(v) : null;
  }
  Future<void> setSettingsBackground(Color? c) async {
    if (c == null) await _box.delete('settingsBackground');
    else await _box.put('settingsBackground', c.value);
  }
  String? get settingsWallpaper => _box.get('settingsWallpaper') as String?;
  Future<void> setSettingsWallpaper(String? v) async {
    if (v == null) await _box.delete('settingsWallpaper');
    else await _box.put('settingsWallpaper', v);
  }
  double get settingsOverlayOpacity {
    final v = _box.get('settingsOverlayOpacity');
    return v != null ? (v as num).toDouble() : 0.3;
  }
  Future<void> setSettingsOverlayOpacity(double v) => _box.put('settingsOverlayOpacity', v);

  // ── Per-floor text color override ──────────────────────────────────────────
  int? floorCustomTextValue(int floor) =>
      _box.get('floorTextColor_$floor') as int?;

  Future<void> setFloorCustomTextValue(int floor, int? argb) async {
    if (argb == null) {
      await _box.delete('floorTextColor_$floor');
    } else {
      await _box.put('floorTextColor_$floor', argb);
    }
  }

  // ── Custom Themes ──────────────────────────────────────────────────────────
  List<Map<String, dynamic>> get customThemes {
    final raw = _box.get('customThemes') as List<dynamic>?;
    if (raw == null) return [];
    return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<void> saveCustomTheme(String name, int bgArgb, int textArgb) async {
    final list = customThemes;
    list.removeWhere((t) => t['name'] == name);
    list.add({'name': name, 'bg': bgArgb, 'text': textArgb});
    await _box.put('customThemes', list);
  }

  Future<void> deleteCustomTheme(String name) async {
    final list = customThemes;
    list.removeWhere((t) => t['name'] == name);
    await _box.put('customThemes', list);
  }

  Future<void> applyGlobalTheme(int bgArgb, int textArgb) async {
    for (int i = 1; i <= maxFloors; i++) {
      await setFloorCustomBgValue(i, bgArgb);
    }
    await setHomeBackground(Color(bgArgb));
    final textColor = Color(textArgb);
    if (textColor.computeLuminance() > 0.5) {
      await setFontColor('white');
    } else {
      await setFontColor('black');
    }
  }

  // ── Theme Preset ───────────────────────────────────────────────────────────

  /// Applies a list of ARGB color values (or null to reset) to floors starting at 1.
  Future<void> applyThemePreset(List<int?> colorsForFloors) async {
    for (int i = 0; i < colorsForFloors.length; i++) {
      await setFloorCustomBgValue(i + 1, colorsForFloors[i]);
    }
  }

  // ── Custom Colors ──────────────────────────────────────────────────────────
  List<Color> get customColors {
    final raw = _box.get('customColors') as List?;
    if (raw == null) return [];
    return raw.map((v) => Color(v as int)).toList();
  }

  Future<void> addCustomColor(Color c) async {
    final list = customColors;
    if (list.length >= 8) list.removeAt(0);
    if (!list.any((x) => x.value == c.value)) list.add(c);
    await _box.put('customColors', list.map((c) => c.value).toList());
  }

  Future<void> removeCustomColor(Color c) async {
    final list = customColors..removeWhere((x) => x.value == c.value);
    await _box.put('customColors', list.map((c) => c.value).toList());
  }

  // ── Pinned Folders ─────────────────────────────────────────────────────────
  List<String> get pinnedFolderNames {
    final raw = (_box.get('pinnedFolderNames') as List?) ?? [];
    return List<String>.from(raw);
  }
  Future<void> setPinnedFolderNames(List<String> v) => _box.put('pinnedFolderNames', v);

  // ── Swipe Deadzone ────────────────────────────────────────────────────────

  int get swipeDeadzone => (_box.get('swipeDeadzone') as int?) ?? 80;
  Future<void> setSwipeDeadzone(int v) => _box.put('swipeDeadzone', v);

  // ── Favorite / Folder Order ───────────────────────────────────────────────

  List<String> get favoriteOrder {
    final raw = (_box.get('favoriteOrder') as List?) ?? [];
    return List<String>.from(raw);
  }

  Future<void> setFavoriteOrder(List<String> order) =>
      _box.put('favoriteOrder', order);

  List<String> getFolderOrder(String folderName) {
    final raw = (_box.get('folderOrder_$folderName') as List?) ?? [];
    return List<String>.from(raw);
  }

  Future<void> setFolderOrder(String folderName, List<String> order) =>
      _box.put('folderOrder_$folderName', order);

  // ── Fixed Folder Order (top/bottom pinned) ────────────────────────────────

  List<String> getFixedTopFolderOrder(int floor) {
    final raw = _box.get('fixedTopFolderOrder_$floor') as List?;
    return raw != null ? List<String>.from(raw) : [];
  }

  Future<void> setFixedTopFolderOrder(int floor, List<String> order) =>
      _box.put('fixedTopFolderOrder_$floor', order);

  List<String> getFixedBottomFolderOrder(int floor) {
    final raw = _box.get('fixedBottomFolderOrder_$floor') as List?;
    return raw != null ? List<String>.from(raw) : [];
  }

  Future<void> setFixedBottomFolderOrder(int floor, List<String> order) =>
      _box.put('fixedBottomFolderOrder_$floor', order);

  // ── Emergency App Display Settings ─────────────────────────────────────────
  /// Font color for emergency apps on 1F. Stored as ARGB int. Default = redAccent.
  int get emergencyAppFontColor =>
      (_box.get('emergencyAppFontColor') as int?) ?? 0xFFFF5252;
  Future<void> setEmergencyAppFontColor(int v) =>
      _box.put('emergencyAppFontColor', v);

  /// 'section' = grouped at top with header, 'normal' = mixed alphabetically
  String get emergencyAppDisplayMode =>
      (_box.get('emergencyAppDisplayMode') as String?) ?? 'section';
  Future<void> setEmergencyAppDisplayMode(String v) =>
      _box.put('emergencyAppDisplayMode', v);

  /// Whether to show a special index entry for emergency section in sidebar
  bool get emergencyAppShowIndex =>
      (_box.get('emergencyAppShowIndex') as bool?) ?? true;
  Future<void> setEmergencyAppShowIndex(bool v) =>
      _box.put('emergencyAppShowIndex', v);

  // ── Last-used time display ────────────────────────────────────────────────
  /// Packages for which the home screen shows "3分前" / "2時間前" beside the
  /// app name. Backed by UsageStatsManager.lastTimeUsed.
  List<String> get lastUsedDisplayApps {
    final raw = _box.get('lastUsedDisplayApps') as List?;
    return raw == null ? <String>[] : List<String>.from(raw);
  }
  Future<void> setLastUsedDisplayApps(List<String> apps) =>
      _box.put('lastUsedDisplayApps', apps);

  // ── Single Folder Mode ─────────────────────────────────────────────────────
  bool get singleFolderMode => (_box.get('singleFolderMode') as bool?) ?? false;
  Future<void> setSingleFolderMode(bool v) => _box.put('singleFolderMode', v);

  // ── Max / Underground Floors ───────────────────────────────────────────────
  int get maxFloors => (_box.get('maxFloors') as int?) ?? 10;
  Future<void> setMaxFloors(int v) => _box.put('maxFloors', v);

  int get undergroundFloors => (_box.get('undergroundFloors') as int?) ?? 0;
  Future<void> setUndergroundFloors(int v) => _box.put('undergroundFloors', v);

  // ��─ Default Floor for New Apps ──────────────────────────────────────────────
  int get defaultNewAppFloor => (_box.get('defaultNewAppFloor') as int?) ?? 1;
  Future<void> setDefaultNewAppFloor(int v) => _box.put('defaultNewAppFloor', v);

  // ── Backup / Export ────────────────────────────────────────────────────────
  Map<String, dynamic> exportAllSettings() {
    final result = <String, dynamic>{};
    for (final key in _box.keys) {
      final val = _box.get(key);
      result[key.toString()] = val?.toString() ?? '';
    }
    return result;
  }
}
