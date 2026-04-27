part of '../settings_screen.dart';

extension HomeSettingsMethods on _SettingsScreenState {
  // ── Section row builders ───────────────────────────────────────────

  List<Widget> _homeSettingRows() {
    final ss = _ss;

    // ── Shortcut group summary ──
    final shortcutsOn = <String>[
      if (ss.showDialShortcut) '電話',
      if (ss.showCameraShortcut) 'カメラ',
      if (ss.showAlarmShortcut) '時計',
    ];
    final shortcutSummary = shortcutsOn.isEmpty
        ? '無効'
        : shortcutsOn.length == 3
            ? '3つ有効'
            : shortcutsOn.join('・');

    // ── Clock group summary ──
    final clockSizeLabel =
        const {'small': '小', 'normal': '標準', 'large': '大'}[ss.clockSize] ??
            ss.clockSize;
    final clockSummary = '${ss.clockFormat} · $clockSizeLabel';

    // ── Gesture group summary ──
    final activeGestures = <String>[
      if ((ss.gestureUpApp ?? '').isNotEmpty) '上',
      if ((ss.gestureDownApp ?? '').isNotEmpty) '下',
      if ((ss.gestureDoubleTapApp ?? '').isNotEmpty) 'ダブルタップ',
    ];
    final gestureSummary =
        activeGestures.isEmpty ? '未設定' : activeGestures.join('・');

    return [
      _expandableRow(
        key: 'home_shortcuts',
        title: 'ショートカット',
        summary: shortcutSummary,
        children: _shortcutChildren(ss),
      ),
      _rowDivider,
      _expandableRow(
        key: 'home_clock',
        title: '時計',
        summary: clockSummary,
        children: _clockChildren(ss),
      ),
      _rowDivider,
      _expandableRow(
        key: 'home_gesture',
        title: 'ジェスチャー',
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
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile(
            contentPadding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            title: Text(title,
                style: const TextStyle(color: Colors.white, fontSize: 14)),
            subtitle: Text(
              enabled ? '有効 · ${appName(pkg, defaultLabel)}' : '無効',
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
            _settingRow('　$defaultLabel', appName(pkg, 'デフォルト（$defaultLabel）'),
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

    return [
      shortcutBlock(
        title: '電話ショートカット',
        enabled: ss.showDialShortcut,
        pkg: ss.dialShortcutPackage,
        defaultLabel: '電話',
        onToggle: ss.setShowDialShortcut,
        onPickPackage: ss.setDialShortcutPackage,
      ),
      _rowDivider,
      shortcutBlock(
        title: 'カメラショートカット',
        enabled: ss.showCameraShortcut,
        pkg: ss.cameraShortcutPackage,
        defaultLabel: 'カメラ',
        onToggle: ss.setShowCameraShortcut,
        onPickPackage: ss.setCameraShortcutPackage,
      ),
      _rowDivider,
      shortcutBlock(
        title: '時計タップでアラーム',
        enabled: ss.showAlarmShortcut,
        pkg: ss.alarmShortcutPackage,
        defaultLabel: 'アラーム',
        onToggle: ss.setShowAlarmShortcut,
        onPickPackage: ss.setAlarmShortcutPackage,
      ),
    ];
  }

  List<Widget> _clockChildren(SettingsService ss) {
    return [
      _settingRow('時刻フォーマット', ss.clockFormat, () async {
        final v = await _showOptionsDialog('時刻フォーマット',
            [('HH:mm:ss', 'HH:mm:ss'), ('HH:mm', 'HH:mm')], ss.clockFormat);
        if (v != null) {
          await ss.setClockFormat(v);
          setState(() {});
        }
      }),
      _rowDivider,
      _settingRow('日付フォーマット', ss.dateFormatString, () async {
        final v = await _showOptionsDialog('日付フォーマット', [
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
        '時計のサイズ',
        const {'small': '小', 'normal': '標準', 'large': '大'}[ss.clockSize] ??
            ss.clockSize,
        () async {
          final v = await _showOptionsDialog('時計のサイズ',
              [('small', '小'), ('normal', '標準'), ('large', '大')], ss.clockSize);
          if (v != null) {
            await ss.setClockSize(v);
            setState(() {});
          }
        },
      ),
      _rowDivider,
      SwitchListTile(
        contentPadding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
        title: const Text('充電アニメーション',
            style: TextStyle(color: Colors.white, fontSize: 14)),
        subtitle: Text(ss.chargingAnimationEnabled ? '有効' : '無効',
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
      _showSnack('ショートカットアプリの変更がロックされています');
      return false;
    }
    if (ss.isStrictSubCooldownActive('shortcut')) {
      _showSnack('ショートカット変更のクールダウン中です');
      return false;
    }
    final confirmed = await showStrictTimerDialog(context,
        seconds: ss.strictSubTimerMinutes('shortcut') * 60);
    if (!confirmed) return false;
    return true;
  }
}
