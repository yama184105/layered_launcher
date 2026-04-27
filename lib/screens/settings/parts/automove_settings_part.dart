part of '../settings_screen.dart';

extension AutoMoveSettingsMethods on _SettingsScreenState {
  List<Widget> _autoMoveSettingRows() {
    final autoApps = _ss.allAutoMoveApps;
    String modeName(String mode) {
      switch (mode) {
        case 'schedule': return 'スケジュール制';
        case 'interval': return '日数間隔ランダム';
        default: return '未設定';
      }
    }
    return [
      // Collapsible header
      if (autoApps.isNotEmpty)
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => setState(() => _autoMoveListExpanded = !_autoMoveListExpanded),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text('${autoApps.length}アプリに自動移動が設定されています',
                        style: const TextStyle(color: Colors.white54, fontSize: 12)),
                  ),
                  Icon(
                    _autoMoveListExpanded ? Icons.expand_less : Icons.expand_more,
                    color: Colors.white38, size: 18,
                  ),
                ],
              ),
            ),
          ),
        ),
      if (autoApps.isEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
          child: const Text('自動移動が設定されているアプリはありません',
              style: TextStyle(color: Colors.white38, fontSize: 12)),
        ),
      // Expanded app list
      if (_autoMoveListExpanded)
        ...autoApps.map((pkg) {
          final name = _apps.firstWhere(
            (a) => a.packageName == pkg,
            orElse: () => AppConfig(packageName: pkg, appName: pkg, floor: 1),
          );
          final displayName = (name.customName?.isNotEmpty == true) ? name.customName! : name.appName;
          final mode = _ss.autoMoveMode(pkg);
          return _settingRow(displayName, modeName(mode), () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => AutoMoveScreen(
                  settingsService: _ss,
                  packageNames: [pkg],
                  allApps: _apps,
                ),
              ),
            );
            setState(() {});
          });
        }),
      _settingRow('アプリを選んで設定', '', () async {
        final selected = await _showAppMultiSelectDialog();
        if (selected != null && selected.isNotEmpty) {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => AutoMoveScreen(
                settingsService: _ss,
                packageNames: selected,
                allApps: _apps,
              ),
            ),
          );
          setState(() {});
        }
      }),
    ];
  }

  Future<List<String>?> _showAppMultiSelectDialog() async {
    final selected = <String>{};
    return showDialog<List<String>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInner) {
          final sorted = List<AppConfig>.from(_apps)
            ..sort((a, b) => a.appName.compareTo(b.appName));
          return AlertDialog(
            backgroundColor: const Color(0xFF1A1A1A),
            title: Row(
              children: [
                const Expanded(child: Text('アプリを選択', style: TextStyle(color: Colors.white, fontSize: 14))),
                Text('${selected.length}個', style: const TextStyle(color: Colors.white38, fontSize: 12)),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              height: 400,
              child: ListView.builder(
                itemCount: sorted.length,
                itemBuilder: (_, i) {
                  final app = sorted[i];
                  final isSel = selected.contains(app.packageName);
                  final name = (app.customName?.isNotEmpty == true) ? app.customName! : app.appName;
                  return CheckboxListTile(
                    dense: true,
                    title: Text(name, style: const TextStyle(color: Colors.white, fontSize: 13)),
                    subtitle: Text(
                      _ss.autoMoveMode(app.packageName) != 'none'
                          ? '設定済み'
                          : '',
                      style: const TextStyle(color: Colors.white38, fontSize: 10),
                    ),
                    value: isSel,
                    activeColor: Colors.white,
                    checkColor: Colors.black,
                    onChanged: (_) => setInner(() {
                      if (isSel) selected.remove(app.packageName);
                      else selected.add(app.packageName);
                    }),
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('キャンセル', style: TextStyle(color: Colors.white54)),
              ),
              TextButton(
                onPressed: selected.isEmpty ? null : () => Navigator.pop(ctx, selected.toList()),
                child: const Text('設定', style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        },
      ),
    );
  }
}
