part of '../settings_screen.dart';

extension GestureSettingsMethods on _SettingsScreenState {
  List<Widget> _gestureSettingRows() {
    return [
      _settingRow('上スワイプ', _gestureLabel(_ss.gestureUpApp), () async {
        final result = await _pickGestureAction(_ss.gestureUpApp, forUpSwipe: true);
        await _ss.setGestureUpApp(result);
        setState(() {});
      }),
      _rowDivider,
      _settingRow('下スワイプ', _gestureLabel(_ss.gestureDownApp), () async {
        final result = await _pickGestureAction(_ss.gestureDownApp);
        await _ss.setGestureDownApp(result);
        setState(() {});
      }),
      _rowDivider,
      _settingRow('ダブルタップ', _gestureLabel(_ss.gestureDoubleTapApp), () async {
        final result = await _pickGestureAction(_ss.gestureDoubleTapApp);
        await _ss.setGestureDoubleTapApp(result);
        setState(() {});
      }),
    ];
  }


  // ── gesture picker ────────────────────────────────────────────

  Future<String?> _pickGestureAction(String? current, {bool forUpSwipe = false}) async {
    String? selected = current;
    final result = await showDialog<String?>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInner) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          title: const Text('ジェスチャーアクション',
              style: TextStyle(color: Colors.white)),
          content: SizedBox(
            width: double.maxFinite,
            height: 400,
            child: ListView(
              children: [
                // None option
                _gestureOption(ctx, null, selected, 'なし',
                    () => setInner(() => selected = null)),
                // Screen off option
                _gestureOption(ctx, 'screen_off', selected,
                    '画面オフ',
                    () => setInner(() => selected = 'screen_off')),
                // Notification panel option
                _gestureOption(ctx, 'notification_panel', selected,
                    '通知パネルを表示',
                    () => setInner(() => selected = 'notification_panel')),
                const Divider(color: Colors.white12),
                if (forUpSwipe) ...[
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 6),
                    child: Text('推奨アプリ', style: TextStyle(color: Colors.white54, fontSize: 11)),
                  ),
                  ..._recommendedApps().map((app) => _gestureOption(ctx, app.packageName, selected,
                      _displayName(app), () => setInner(() => selected = app.packageName))),
                  const Divider(color: Colors.white12),
                ],
                ..._apps.map((app) => _gestureOption(
                      ctx,
                      app.packageName,
                      selected,
                      _displayName(app),
                      () => setInner(
                          () => selected = app.packageName),
                    )),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, current),
                child: const Text('キャンセル',
                    style: TextStyle(color: Colors.white54))),
            TextButton(
              onPressed: () => Navigator.pop(ctx, selected),
              child: const Text('完了',
                  style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
    return result;
  }

  List<AppConfig> _recommendedApps() {
    const patterns = [
      'com.google.android.googlequicksearchbox',
      'com.android.chrome',
      'org.mozilla.firefox',
      'com.microsoft.bing',
      'com.duckduckgo.mobile.android',
      'com.brave.browser',
      'com.opera.browser',
    ];
    return _apps.where((a) => patterns.contains(a.packageName)).toList();
  }

  Widget _gestureOption(BuildContext ctx, String? value,
      String? selected, String label, VoidCallback onTap) {
    final isSelected = value == selected;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          children: [
            Expanded(
              child: Text(label,
                  style: TextStyle(
                      color:
                          isSelected ? Colors.white : Colors.white70,
                      fontSize: 14)),
            ),
            if (isSelected)
              const Icon(Icons.check, color: Colors.white, size: 16),
          ],
        ),
      ),
    );
  }

  String _gestureLabel(String? v) {
    if (v == null) return 'なし';
    if (v == 'screen_off') return '画面オフ';
    if (v == 'notification_panel') return '通知パネルを表示';
    final app = _apps.firstWhere(
      (a) => a.packageName == v,
      orElse: () => AppConfig(packageName: v, appName: v, floor: 1),
    );
    return _displayName(app);
  }

}
