part of '../settings_screen.dart';

extension HomeSettingsMethods on _SettingsScreenState {
  // ── Section row builders ───────────────────────────────────────────

  List<Widget> _homeSettingRows() {
    final s = S.of(context);
    final ss = _ss;

    // ── Shortcut group summary ──
    final shortcutsOn = <String>[
      if (ss.showDialShortcut) s.shortcutPhone,
      if (ss.showCameraShortcut) s.shortcutCamera,
      if (ss.showAlarmShortcut) s.shortcutClock,
    ];
    final shortcutSummary = shortcutsOn.isEmpty
        ? s.actionDisabled
        : shortcutsOn.length == 3
            ? s.threeEnabled
            : shortcutsOn.join('・');

    // ── Clock group summary ──
    final clockSizeLabel =
        {'small': s.clockSizeSmall, 'normal': s.clockSizeNormal, 'large': s.clockSizeLarge}[ss.clockSize] ??
            ss.clockSize;
    final clockSummary = s.clockSummary(ss.clockFormat, clockSizeLabel);

    // ── Gesture group summary ──
    final activeGestures = <String>[
      if ((ss.gestureUpApp ?? '').isNotEmpty) s.gestureUp,
      if ((ss.gestureDownApp ?? '').isNotEmpty) s.gestureDown,
      if ((ss.gestureDoubleTapApp ?? '').isNotEmpty) s.gestureDoubleTap,
    ];
    final gestureSummary =
        activeGestures.isEmpty ? s.notSet : activeGestures.join('・');

    return [
      _expandableRow(
        key: 'home_shortcuts',
        title: s.shortcuts,
        summary: shortcutSummary,
        children: _shortcutChildren(ss),
      ),
      _rowDivider,
      _expandableRow(
        key: 'home_clock',
        title: s.clock,
        summary: clockSummary,
        children: _clockChildren(ss),
      ),
      _rowDivider,
      _expandableRow(
        key: 'home_gesture',
        title: s.gestures,
        summary: gestureSummary,
        children: _gestureSettingRows(),
      ),
    ];
  }

  List<Widget> _shortcutChildren(SettingsService ss) {
    String appName(String pkg, String def) {
      if (pkg.isEmpty) return def;
      return _apps
          .firstWhere(
            (a) => a.packageName == pkg,
            orElse: () => AppConfig(packageName: pkg, appName: pkg, floor: 1),
          )
          .appName;
    }

    Widget shortcutBlock({
      required String title,
      required bool enabled,
      required String pkg,
      required String defaultLabel,
      required Future<void> Function(bool) onToggle,
      required Future<void> Function(String) onPickPackage,
    }) {
      final s = S.of(context);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile(
            contentPadding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            title: Text(title,
                style: const TextStyle(color: Colors.white, fontSize: 14)),
            subtitle: Text(
              enabled ? s.enabledWithApp(appName(pkg, defaultLabel)) : s.actionDisabled,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            activeColor: Colors.tealAccent,
            value: enabled,
            onChanged: (v) async {
              await onToggle(v);
              setState(() {});
            },
          ),
          if (enabled)
            _settingRow(s.indentedLabel(defaultLabel), appName(pkg, s.defaultWithLabel(defaultLabel)),
                () async {
              if (!await _checkShortcutLock()) return;
              final picked = await _pickShortcutApp(pkg);
              if (picked != null) {
                await onPickPackage(picked);
                setState(() {});
              }
            }),
        ],
      );
    }

    final s = S.of(context);
    return [
      shortcutBlock(
        title: s.phoneShortcut,
        enabled: ss.showDialShortcut,
        pkg: ss.dialShortcutPackage,
        defaultLabel: s.shortcutPhone,
        onToggle: ss.setShowDialShortcut,
        onPickPackage: ss.setDialShortcutPackage,
      ),
      _rowDivider,
      shortcutBlock(
        title: s.cameraShortcut,
        enabled: ss.showCameraShortcut,
        pkg: ss.cameraShortcutPackage,
        defaultLabel: s.shortcutCamera,
        onToggle: ss.setShowCameraShortcut,
        onPickPackage: ss.setCameraShortcutPackage,
      ),
      _rowDivider,
      shortcutBlock(
        title: s.alarmShortcut,
        enabled: ss.showAlarmShortcut,
        pkg: ss.alarmShortcutPackage,
        defaultLabel: s.shortcutAlarm,
        onToggle: ss.setShowAlarmShortcut,
        onPickPackage: ss.setAlarmShortcutPackage,
      ),
    ];
  }

  List<Widget> _clockChildren(SettingsService ss) {
    final s = S.of(context);
    return [
      _settingRow(s.clockFormat, ss.clockFormat, () async {
        final v = await _showOptionsDialog(s.clockFormat,
            [('HH:mm:ss', 'HH:mm:ss'), ('HH:mm', 'HH:mm')], ss.clockFormat);
        if (v != null) {
          await ss.setClockFormat(v);
          setState(() {});
        }
      }),
      _rowDivider,
      _settingRow(s.dateFormat, ss.dateFormatString, () async {
        final v = await _showOptionsDialog(s.dateFormat, [
          ('M/d (E)', 'M/d (E)'),
          ('yyyy/MM/dd', 'yyyy/MM/dd'),
          ('MM/dd (E)', 'MM/dd (E)'),
          ('M月d日(E)', 'M月d日(E)'),
        ], ss.dateFormatString);
        if (v != null) {
          await ss.setDateFormatString(v);
          setState(() {});
        }
      }),
      _rowDivider,
      _settingRow(
        s.clockSize,
        {'small': s.clockSizeSmall, 'normal': s.clockSizeNormal, 'large': s.clockSizeLarge}[ss.clockSize] ??
            ss.clockSize,
        () async {
          final v = await _showOptionsDialog(s.clockSize,
              [('small', s.clockSizeSmall), ('normal', s.clockSizeNormal), ('large', s.clockSizeLarge)], ss.clockSize);
          if (v != null) {
            await ss.setClockSize(v);
            setState(() {});
          }
        },
      ),
      _rowDivider,
      SwitchListTile(
        contentPadding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
        title: Text(s.chargingAnimation,
            style: const TextStyle(color: Colors.white, fontSize: 14)),
        subtitle: Text(ss.chargingAnimationEnabled ? s.actionEnabled : s.actionDisabled,
            style: const TextStyle(color: Colors.white54, fontSize: 12)),
        activeColor: Colors.tealAccent,
        value: ss.chargingAnimationEnabled,
        onChanged: (v) async {
          await ss.setChargingAnimationEnabled(v);
          setState(() {});
        },
      ),
    ];
  }

  /// Returns true if the shortcut change should proceed.
  Future<bool> _checkShortcutLock() async {
    final ss = _ss;
    if (!ss.strictSubEnabled('shortcut')) return true;
    if (ss.strictSubType('shortcut') == 'block') {
      _showSnack(S.of(context).shortcutLocked);
      return false;
    }
    if (ss.isStrictSubCooldownActive('shortcut')) {
      _showSnack(S.of(context).shortcutCooldown);
      return false;
    }
    final confirmed = await showStrictTimerDialog(context,
        seconds: ss.strictSubTimerMinutes('shortcut') * 60);
    if (!confirmed) return false;
    return true;
  }
}
