part of '../settings_screen.dart';

extension ScreenTimeSettingsMethods on _SettingsScreenState {
  List<Widget> _screenTimeSettingRows() {
    const intervalLabels = {30: '30分', 60: '1時間', 120: '2時間', 240: '4時間'};
    final ss = _ss;
    final batchLabel =
        intervalLabels[ss.batchIntervalMinutes] ?? '${ss.batchIntervalMinutes}分';
    return [
      _settingRow('マインドフルディレイ設定', '', () {
        Navigator.push(context, MaterialPageRoute(
          builder: (_) => _MindfulDelaySettingsScreen(appService: _as, settingsService: ss),
        )).then((_) => _load());
      }),
      _rowDivider,
      _expandableRow(
        key: 'screentime_notif',
        title: '通知',
        summary: 'バッチ $batchLabel',
        children: [
          _settingRow('通知制限', '', () {
            Navigator.push(context, MaterialPageRoute(
              builder: (_) => _NotificationSettingsScreen(
                  appService: _as, settingsService: ss),
            ));
          }),
          _rowDivider,
          _settingRow('バッチ通知間隔', batchLabel, () async {
            final v = await _showOptionsDialog('バッチ通知間隔', [
              (30, '30分'),
              (60, '1時間'),
              (120, '2時間'),
              (240, '4時間'),
            ], ss.batchIntervalMinutes);
            if (v != null) {
              await ss.setBatchIntervalMinutes(v);
              setState(() {});
            }
          }),
        ],
      ),
      _rowDivider,
      _settingRow('アプリブロック', '', () {
        Navigator.push(context, MaterialPageRoute(
          builder: (_) => _AppBlockScreen(appService: _as, settingsService: ss),
        ));
      }),
    ];
  }

}

// ── Mindful Delay Settings Screen ────────────────────────────────────────────

class _MindfulDelaySettingsScreen extends StatefulWidget {
  final AppService appService;
  final SettingsService settingsService;

  const _MindfulDelaySettingsScreen({
    required this.appService,
    required this.settingsService,
  });

  @override
  State<_MindfulDelaySettingsScreen> createState() =>
      _MindfulDelaySettingsScreenState();
}

class _MindfulDelaySettingsScreenState
    extends State<_MindfulDelaySettingsScreen> {
  List<AppConfig> _apps = [];
  bool _loading = true;
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';
  final TextEditingController _customSecsCtrl = TextEditingController();

  SettingsService get _ss => widget.settingsService;
  AppService get _as => widget.appService;

  @override
  void initState() {
    super.initState();
    _searchCtrl
        .addListener(() => setState(() => _searchQuery = _searchCtrl.text));
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _customSecsCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final apps = await _as.getAllApps();
    if (!mounted) return;
    setState(() {
      _apps = apps;
      _loading = false;
    });
  }

  String _displayName(AppConfig app) =>
      (app.customName?.isNotEmpty == true) ? app.customName! : app.appName;

  List<AppConfig> get _filteredApps {
    final sorted = List<AppConfig>.from(_apps)
      ..sort((a, b) => _displayName(a).compareTo(_displayName(b)));
    if (_searchQuery.isEmpty) return sorted;
    final q = _searchQuery.toLowerCase();
    return sorted
        .where((a) =>
            _displayName(a).toLowerCase().contains(q) ||
            a.appName.toLowerCase().contains(q))
        .toList();
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 8, bottom: 6),
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.transparent,
          border:
              Border.all(color: selected ? Colors.white : Colors.white38),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          label,
          style: TextStyle(
              color: selected ? Colors.black : Colors.white70,
              fontSize: 12),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const presetSecs = [3, 5, 10, 30, 60];
    final customSecs = _ss.mindfulDelaySeconds;
    final isCustom = !presetSecs.contains(customSecs);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('マインドフルディレイ設定',
            style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Column(
        children: [
          // ── Global settings ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Global toggle
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('マインドフルディレイを有効にする',
                      style:
                          TextStyle(color: Colors.white, fontSize: 14)),
                  subtitle: const Text('ONにすると対象アプリ起動時に遅延が発生します',
                      style:
                          TextStyle(color: Colors.white38, fontSize: 11)),
                  activeColor: Colors.tealAccent,
                  value: _ss.mindfulDelayEnabled,
                  onChanged: (v) async {
                    await _ss.setMindfulDelayEnabled(v);
                    setState(() {});
                  },
                ),
                const Divider(color: Colors.white12),
                const SizedBox(height: 8),
                const Text('待機時間',
                    style:
                        TextStyle(color: Colors.white70, fontSize: 13)),
                const SizedBox(height: 8),
                Wrap(
                  children: [
                    ...presetSecs.map((s) => _chip(
                          s < 60 ? '$s秒' : '${s ~/ 60}分',
                          customSecs == s && !isCustom,
                          () async {
                            await _ss.setMindfulDelaySeconds(s);
                            setState(() {});
                          },
                        )),
                    _chip(
                        'カスタム',
                        isCustom,
                        () async {
                          _customSecsCtrl.text =
                              isCustom ? '$customSecs' : '';
                          final result = await showDialog<int>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              backgroundColor: const Color(0xFF1A1A1A),
                              title: const Text('カスタム秒数',
                                  style:
                                      TextStyle(color: Colors.white)),
                              content: TextField(
                                controller: _customSecsCtrl,
                                keyboardType: TextInputType.number,
                                autofocus: true,
                                style: const TextStyle(
                                    color: Colors.white),
                                decoration: InputDecoration(
                                  hintText: '秒数を入力',
                                  hintStyle: const TextStyle(
                                      color: Colors.white38),
                                  filled: true,
                                  fillColor:
                                      Colors.white.withOpacity(0.07),
                                  border: OutlineInputBorder(
                                    borderRadius:
                                        BorderRadius.circular(4),
                                    borderSide: BorderSide.none,
                                  ),
                                ),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(ctx),
                                  child: const Text('キャンセル',
                                      style: TextStyle(
                                          color: Colors.white54)),
                                ),
                                TextButton(
                                  onPressed: () {
                                    final v = int.tryParse(
                                        _customSecsCtrl.text);
                                    if (v != null && v > 0) {
                                      Navigator.pop(ctx, v);
                                    }
                                  },
                                  child: const Text('完了',
                                      style: TextStyle(
                                          color: Colors.white)),
                                ),
                              ],
                            ),
                          );
                          if (result != null) {
                            await _ss.setMindfulDelaySeconds(result);
                            setState(() {});
                          }
                        }),
                  ],
                ),
                const SizedBox(height: 12),
                const Text('時間終了後の動作',
                    style:
                        TextStyle(color: Colors.white70, fontSize: 13)),
                const SizedBox(height: 8),
                ...[
                  ('launch', 'そのままアプリを開く'),
                  ('confirm', 'もう一度確認ダイアログを表示'),
                  ('cancel', 'キャンセルしてホームに戻る'),
                ].map((opt) {
                  final sel = _ss.mindfulDelayAction == opt.$1;
                  return InkWell(
                    onTap: () async {
                      await _ss.setMindfulDelayAction(opt.$1);
                      setState(() {});
                    },
                    child: Padding(
                      padding:
                          const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          Radio<String>(
                            value: opt.$1,
                            groupValue: _ss.mindfulDelayAction,
                            activeColor: Colors.white,
                            fillColor: WidgetStateProperty.all(
                                sel
                                    ? Colors.white
                                    : Colors.white38),
                            onChanged: (v) async {
                              if (v != null) {
                                await _ss.setMindfulDelayAction(v);
                                setState(() {});
                              }
                            },
                          ),
                          Text(opt.$2,
                              style: TextStyle(
                                  color: sel
                                      ? Colors.white
                                      : Colors.white70,
                                  fontSize: 14)),
                        ],
                      ),
                    ),
                  );
                }),
                const Divider(color: Colors.white12),
                const SizedBox(height: 4),
              ],
            ),
          ),
          // ── App list ──
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
            child: TextField(
              controller: _searchCtrl,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'アプリを検索...',
                hintStyle: const TextStyle(
                    color: Colors.white38, fontSize: 13),
                prefixIcon: const Icon(Icons.search,
                    color: Colors.white38, size: 18),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear,
                            color: Colors.white38, size: 18),
                        onPressed: _searchCtrl.clear,
                      )
                    : null,
                filled: true,
                fillColor: Colors.white.withOpacity(0.07),
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 6),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '以下のアプリに適用  ${_filteredApps.where((a) => a.mindfulDelay).length}件ON',
                style: const TextStyle(
                    color: Colors.white54, fontSize: 12),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(
                    child:
                        CircularProgressIndicator(color: Colors.white))
                : ListView.builder(
                    itemCount: _filteredApps.length,
                    itemBuilder: (_, i) {
                      final app = _filteredApps[i];
                      return SwitchListTile(
                        title: Text(
                          _displayName(app),
                          style: const TextStyle(
                              color: Colors.white, fontSize: 14),
                        ),
                        subtitle: Text(
                          floorLabel(app.floor),
                          style: const TextStyle(
                              color: Colors.white38, fontSize: 12),
                        ),
                        activeColor: Colors.tealAccent,
                        value: app.mindfulDelay,
                        onChanged: (v) async {
                          app.mindfulDelay = v;
                          await _as.saveConfig(app);
                          setState(() {});
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

