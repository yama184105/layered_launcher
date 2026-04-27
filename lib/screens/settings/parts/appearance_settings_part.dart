part of '../settings_screen.dart';

extension AppearanceSettingsMethods on _SettingsScreenState {
  List<Widget> _gaikkanSettingRows() {
    final ss = _ss;
    return [
      _expandableRow(
        key: 'gaikkan_background',
        title: '背景',
        summary: '一括 / ホーム / 階層 / 設定',
        children: [
          _settingRow('背景一括変更', '', _showBulkBgColorPicker),
          _rowDivider,
          _settingRow('ホーム背景', '', () async {
            await _showHomeBackgroundDialog();
          }),
          _rowDivider,
          _settingRow('階層背景', '', () {
            Navigator.push(context, MaterialPageRoute(
              builder: (_) => _FloorBgScreen(settingsService: ss),
            )).then((_) => setState(() {}));
          }),
          _rowDivider,
          _settingRow('設定画面背景', '', () async {
            await _showSettingsBgDialog();
          }),
        ],
      ),
      _rowDivider,
      _settingRow('フォント設定', '', () {
        Navigator.push(context, MaterialPageRoute(
          builder: (_) => _FontSettingsScreen(settingsService: ss),
        )).then((_) => setState(() {}));
      }),
    ];
  }

  Widget _buildAnimationSection() {
    const types = [
      ('slide', 'スライド'),
      ('stair', '階段'),
      ('fade', 'フェード'),
      ('zoom', 'ズーム'),
      ('none', 'なし'),
    ];
    const speedPresets = [
      (50, '瞬速'),
      (150, '超速'),
      (300, '速い'),
      (500, 'やや速い'),
      (700, '普通'),
      (1000, 'やや遅い'),
      (1400, '遅い'),
      (1800, 'とても遅い'),
      (2400, '超遅い'),
      (3000, '極遅い'),
    ];

    final typeLabel = types.firstWhere(
      (t) => t.$1 == _ss.animationType,
      orElse: () => ('slide', 'スライド'),
    ).$2;

    final currentSpeed = _ss.animationSpeedMs;
    final speedPresetMatch = speedPresets
        .where((p) => p.$1 == currentSpeed)
        .map((p) => p.$2)
        .firstOrNull;
    final speedLabel = speedPresetMatch != null
        ? '$speedPresetMatch (${currentSpeed}ms)'
        : 'カスタム (${currentSpeed}ms)';

    final pairCount = _customizedPairCount();
    final pairLabel = pairCount > 0 ? '$pairCount件 設定中' : '未設定';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _animSubRow(
          'type',
          '種類',
          typeLabel,
          _buildAnimTypeBody(types),
        ),
        const Divider(height: 1, color: Colors.white12, indent: 16, endIndent: 16),
        _animSubRow(
          'speed',
          'デフォルト速度',
          speedLabel,
          _buildAnimSpeedBody(speedPresets),
        ),
        const Divider(height: 1, color: Colors.white12, indent: 16, endIndent: 16),
        _animSubRow(
          'pair',
          'フロア間ごとの個別速度',
          pairLabel,
          _buildAnimPairBody(),
        ),
      ],
    );
  }

  Widget _animSubRow(String key, String title, String value, Widget body) {
    final open = _openAnimSubSection == key;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              setState(() {
                _openAnimSubSection = open ? null : key;
              });
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(title,
                        style: const TextStyle(color: Colors.white, fontSize: 14)),
                  ),
                  Text(value,
                      style: const TextStyle(color: Colors.white54, fontSize: 12)),
                  const SizedBox(width: 6),
                  Icon(open ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                      color: Colors.white38, size: 18),
                ],
              ),
            ),
          ),
        ),
        if (open)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: body,
          ),
      ],
    );
  }

  Widget _buildAnimTypeBody(List<(String, String)> types) {
    final currentType = _ss.animationType;
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: types.map((t) {
        final sel = currentType == t.$1;
        return GestureDetector(
          onTap: () async {
            await _ss.setAnimationType(t.$1);
            setState(() {});
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: sel ? Colors.white : Colors.transparent,
              border: Border.all(color: sel ? Colors.white : Colors.white38),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(t.$2,
                style: TextStyle(
                    color: sel ? Colors.black : Colors.white70, fontSize: 12)),
          ),
        );
      }).toList(),
    );
  }

  Future<bool> _confirmStrictBeforeSpeedChange() async {
    if (!_ss.strictSubEnabled('animation')) return true;
    if (_ss.strictSubType('animation') == 'block') {
      _showSnack('アニメーション速度がロックされています');
      return false;
    }
    final confirmed = await showStrictTimerDialog(context, seconds: 10);
    return confirmed && mounted;
  }

  Widget _buildAnimSpeedBody(List<(int, String)> presets) {
    final currentSpeed = _ss.animationSpeedMs;
    final presetValues = presets.map((p) => p.$1).toSet();
    final isCustom = !presetValues.contains(currentSpeed);

    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        ...presets.map((preset) {
          final sel = currentSpeed == preset.$1;
          return GestureDetector(
            onTap: () async {
              if (!await _confirmStrictBeforeSpeedChange()) return;
              await _ss.setAnimationSpeedMs(preset.$1);
              setState(() {});
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: sel ? Colors.white : Colors.transparent,
                border: Border.all(color: sel ? Colors.white : Colors.white38),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text('${preset.$2} (${preset.$1}ms)',
                  style: TextStyle(
                      color: sel ? Colors.black : Colors.white70, fontSize: 11)),
            ),
          );
        }),
        GestureDetector(
          onTap: () async {
            _customSpeedCtrl.text = isCustom ? currentSpeed.toString() : '';
            final result = await showDialog<int>(
              context: context,
              builder: (ctx) => AlertDialog(
                backgroundColor: const Color(0xFF1A1A1A),
                title: const Text('カスタム速度 (ms)',
                    style: TextStyle(color: Colors.white)),
                content: TextField(
                  controller: _customSpeedCtrl,
                  keyboardType: TextInputType.number,
                  autofocus: true,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: '50〜5000',
                    hintStyle: const TextStyle(color: Colors.white38),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.07),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('キャンセル',
                        style: TextStyle(color: Colors.white54)),
                  ),
                  TextButton(
                    onPressed: () {
                      final v = int.tryParse(_customSpeedCtrl.text);
                      if (v != null && v >= 50 && v <= 5000) {
                        Navigator.pop(ctx, v);
                      }
                    },
                    child: const Text('決定',
                        style: TextStyle(color: Colors.white)),
                  ),
                ],
              ),
            );
            if (result == null) return;
            if (!await _confirmStrictBeforeSpeedChange()) return;
            await _ss.setAnimationSpeedMs(result);
            setState(() {});
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isCustom ? Colors.white : Colors.transparent,
              border:
                  Border.all(color: isCustom ? Colors.white : Colors.white38),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(isCustom ? 'カスタム (${currentSpeed}ms)' : 'カスタム',
                style: TextStyle(
                    color: isCustom ? Colors.black : Colors.white70,
                    fontSize: 11)),
          ),
        ),
      ],
    );
  }

  int _customizedPairCount() {
    final maxF = _ss.maxFloors;
    final underF = _ss.undergroundFloors;
    final pairs = _floorPairs(maxF, underF);
    int n = 0;
    for (final p in pairs) {
      if (_ss.floorPairSpeedMs(p.$1, p.$2) != null) n++;
    }
    return n;
  }

  List<(int, int)> _floorPairs(int maxF, int underF) {
    final pairs = <(int, int)>[];
    if (underF > 0) {
      for (int i = underF; i > 1; i--) pairs.add((-i, -(i - 1)));
      pairs.add((-1, 1));
    }
    for (int i = 1; i < maxF; i++) pairs.add((i, i + 1));
    return pairs;
  }

  Widget _buildAnimPairBody() {
    final pairs = _floorPairs(_ss.maxFloors, _ss.undergroundFloors);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: GestureDetector(
            onTap: () async {
              if (!await _confirmStrictBeforeSpeedChange()) return;
              await _ss.clearAllFloorPairSpeeds();
              if (!mounted) return;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) setState(() {});
              });
            },
            child: const Text('一括リセット',
                style: TextStyle(
                    color: Colors.redAccent,
                    fontSize: 11,
                    decoration: TextDecoration.underline)),
          ),
        ),
        const SizedBox(height: 6),
        ...pairs.map((pair) {
          final from = pair.$1;
          final to = pair.$2;
          final custom = _ss.floorPairSpeedMs(from, to);
          final label = from < 0
              ? (to < 0 ? 'B${-from}F ↔ B${-to}F' : 'B${-from}F ↔ ${to}F')
              : '${from}F ↔ ${to}F';
          final valLabel = custom != null ? '${custom}ms' : '(デフォルト)';
          return GestureDetector(
            onTap: () async {
              if (!await _confirmStrictBeforeSpeedChange()) return;
              final result = await showDialog<int>(
                context: context,
                builder: (dctx) {
                  final ctrl = TextEditingController(
                      text: custom?.toString() ??
                          _ss.animationSpeedMs.toString());
                  return AlertDialog(
                    backgroundColor: const Color(0xFF1A1A1A),
                    title: Text('$label の速度 (ms)',
                        style: const TextStyle(
                            color: Colors.white, fontSize: 13)),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextField(
                          controller: ctrl,
                          keyboardType: TextInputType.number,
                          autofocus: true,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            hintText: '50〜5000',
                            hintStyle: const TextStyle(color: Colors.white38),
                            filled: true,
                            fillColor: Colors.white.withOpacity(0.07),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 8),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(4),
                                borderSide: BorderSide.none),
                          ),
                        ),
                        const SizedBox(height: 6),
                        GestureDetector(
                          onTap: () => Navigator.pop(dctx, -1),
                          child: const Text('デフォルトに戻す',
                              style: TextStyle(
                                  color: Colors.redAccent,
                                  fontSize: 12,
                                  decoration: TextDecoration.underline)),
                        ),
                      ],
                    ),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(dctx),
                          child: const Text('キャンセル',
                              style: TextStyle(color: Colors.white54))),
                      TextButton(
                        onPressed: () {
                          final v = int.tryParse(ctrl.text);
                          if (v != null && v >= 50 && v <= 5000) {
                            Navigator.pop(dctx, v);
                          }
                        },
                        child: const Text('適用',
                            style: TextStyle(color: Colors.tealAccent)),
                      ),
                    ],
                  );
                },
              );
              if (!mounted) return;
              if (result == -1) {
                await _ss.clearFloorPairSpeedMs(from, to);
              } else if (result != null) {
                await _ss.setFloorPairSpeedMs(from, to, result);
              } else {
                return;
              }
              if (!mounted) return;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) setState(() {});
              });
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(
                      child: Text(label,
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 12))),
                  Text(valLabel,
                      style: TextStyle(
                          color:
                              custom != null ? Colors.tealAccent : Colors.white38,
                          fontSize: 11)),
                  const SizedBox(width: 4),
                  const Icon(Icons.chevron_right,
                      color: Colors.white24, size: 14),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

}

// ── Font Settings Screen ──────────────────────────────────────────────────────

class _FontSettingsScreen extends StatefulWidget {
  final SettingsService settingsService;
  const _FontSettingsScreen({required this.settingsService});

  @override
  State<_FontSettingsScreen> createState() => _FontSettingsScreenState();
}

class _FontSettingsScreenState extends State<_FontSettingsScreen> {
  SettingsService get _ss => widget.settingsService;

  static const _fontOptions = [
    ('', 'デフォルト'),
    ('Roboto', 'Roboto'),
    ('Roboto Mono', 'Roboto Mono'),
    ('Noto Sans JP', 'Noto Sans JP'),
    ('Source Code Pro', 'Source Code Pro'),
    ('Lato', 'Lato'),
    ('Montserrat', 'Montserrat'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0D0D),
        foregroundColor: Colors.white,
        title: const Text('フォント設定', style: TextStyle(color: Colors.white, fontSize: 16)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // フォントカラー
          const Text('フォントカラー',
              style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [('white', '白'), ('black', '黒')].map((opt) {
              final sel = _ss.fontColor == opt.$1;
              return GestureDetector(
                onTap: () async { await _ss.setFontColor(opt.$1); setState(() {}); },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: sel ? Colors.white : Colors.transparent,
                    border: Border.all(color: sel ? Colors.white : Colors.white38),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(opt.$2, style: TextStyle(color: sel ? Colors.black : Colors.white70, fontSize: 13)),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),

          // フォントサイズ
          const Text('フォントサイズ',
              style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          StatefulBuilder(builder: (ctx, setInner) {
            double pending = _ss.fontSize;
            return Column(
              children: [
                Row(
                  children: [
                    const Expanded(child: Text('サイズ', style: TextStyle(color: Colors.white, fontSize: 14))),
                    Text('${_ss.fontSize.round()}', style: const TextStyle(color: Colors.white54, fontSize: 12)),
                  ],
                ),
                Slider(
                  value: pending.clamp(12.0, 24.0),
                  min: 12, max: 24, divisions: 12,
                  activeColor: Colors.white, inactiveColor: Colors.white24,
                  onChanged: (v) => setInner(() => pending = v),
                  onChangeEnd: (v) async { await _ss.setFontSize(v); setState(() {}); },
                ),
              ],
            );
          }),
          const SizedBox(height: 16),

          // 行間隔
          const Text('行間隔',
              style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          StatefulBuilder(builder: (ctx, setInner) {
            double pending = _ss.rowSpacing;
            return Column(
              children: [
                Row(
                  children: [
                    const Expanded(child: Text('間隔', style: TextStyle(color: Colors.white, fontSize: 14))),
                    Text('${_ss.rowSpacing.round()}', style: const TextStyle(color: Colors.white54, fontSize: 12)),
                  ],
                ),
                Slider(
                  value: pending.clamp(4.0, 20.0),
                  min: 4, max: 20, divisions: 16,
                  activeColor: Colors.white, inactiveColor: Colors.white24,
                  onChanged: (v) => setInner(() => pending = v),
                  onChangeEnd: (v) async { await _ss.setRowSpacing(v); setState(() {}); },
                ),
              ],
            );
          }),
          const SizedBox(height: 20),

          // フォントスタイル
          const Text('フォントスタイル',
              style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _fontOptions.map((f) {
              final sel = _ss.fontFamily == f.$1;
              return GestureDetector(
                onTap: () async { await _ss.setFontFamily(f.$1); setState(() {}); },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: sel ? Colors.white : Colors.transparent,
                    border: Border.all(color: sel ? Colors.white : Colors.white38),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(f.$2,
                      style: TextStyle(
                          color: sel ? Colors.black : Colors.white70,
                          fontSize: 12,
                          fontFamily: f.$1.isEmpty ? null : f.$1)),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

