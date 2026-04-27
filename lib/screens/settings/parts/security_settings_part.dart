part of '../settings_screen.dart';

extension SecuritySettingsMethods on _SettingsScreenState {
  // ── Lock Mode section ──────────────────────────────────────────

  Widget _buildLockModeSection() {
    final ss = _ss;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('ストリクトモード',
              style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          const Text('各カテゴリごとに制限を設定できます',
              style: TextStyle(color: Colors.white38, fontSize: 12)),
          const SizedBox(height: 12),
          ...BlockSettings.strictSubKeys.map((key) {
            final label = BlockSettings.strictSubLabels[key] ?? key;
            final desc = BlockSettings.strictSubDescriptions[key] ?? '';
            final enabled = ss.strictSubEnabled(key);
            final type = ss.strictSubType(key);
            final timer = ss.strictSubTimerMinutes(key);
            final cooldown = ss.strictSubCooldownRemaining(key);
            final typeLabel = type == 'block' ? '完全ブロック' : 'タイマー（${timer}分待ち）';
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(label, style: const TextStyle(color: Colors.white, fontSize: 13)),
                          Text(desc, style: const TextStyle(color: Colors.white30, fontSize: 10)),
                          const SizedBox(height: 2),
                          Text(enabled ? typeLabel : 'OFF',
                              style: TextStyle(
                                  color: enabled ? Colors.orangeAccent : Colors.white38,
                                  fontSize: 11)),
                        ],
                      ),
                    ),
                    Switch(
                      value: enabled,
                      activeColor: Colors.orangeAccent,
                      onChanged: (v) async {
                        // Check submode lock when changing non-submode settings
                        if (key != 'submode' && ss.strictSubEnabled('submode')) {
                          if (ss.strictSubType('submode') == 'block') {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('サブモード設定がロックされています')));
                            }
                            return;
                          }
                          // Timer-before-apply
                          final confirmed = await showStrictTimerDialog(context, seconds: 10);
                          if (!confirmed || !mounted) return;
                        }
                        await ss.setStrictSubEnabled(key, v);
                        setState(() {});
                      },
                    ),
                  ],
                ),
                if (enabled)
                  Padding(
                    padding: const EdgeInsets.only(left: 16, bottom: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            _strictTypeChip('完全ブロック', type == 'block', () async {
                              await ss.setStrictSubType(key, 'block');
                              setState(() {});
                            }),
                            const SizedBox(width: 8),
                            _strictTypeChip('タイマー', type == 'timer', () async {
                              await ss.setStrictSubType(key, 'timer');
                              setState(() {});
                            }),
                            if (type == 'timer') ...[
                              const SizedBox(width: 12),
                              GestureDetector(
                                onTap: () async {
                                  final v = await _showIntSliderDialog(
                                      'タイマー（分）', timer.toDouble(), 1, 30);
                                  if (v != null) {
                                    await ss.setStrictSubTimerMinutes(key, v);
                                    setState(() {});
                                  }
                                },
                                child: Text('${timer}分',
                                    style: const TextStyle(
                                        color: Colors.tealAccent, fontSize: 12,
                                        decoration: TextDecoration.underline)),
                              ),
                            ],
                          ],
                        ),
                        // App selector for floor-move lock
                        if (key == 'floorMove') ...[
                          const SizedBox(height: 6),
                          GestureDetector(
                            onTap: () => _showLockAppSelector('floorMoveLockedApps', ss.floorMoveLockedApps, (v) => ss.setFloorMoveLockedApps(v)),
                            child: Row(
                              children: [
                                const Icon(Icons.checklist, color: Colors.white54, size: 16),
                                const SizedBox(width: 6),
                                Text(
                                  ss.floorMoveLockedApps.isEmpty
                                      ? '対象アプリ：全アプリ（タップして選択）'
                                      : '対象アプリ：${ss.floorMoveLockedApps.length}個選択済み',
                                  style: const TextStyle(
                                      color: Colors.tealAccent, fontSize: 11,
                                      decoration: TextDecoration.underline),
                                ),
                              ],
                            ),
                          ),
                        ],
                        // App selector for emergency lock
                        if (key == 'emergency') ...[
                          const SizedBox(height: 6),
                          GestureDetector(
                            onTap: () => _showLockAppSelector('emergencyLockedApps', ss.emergencyLockedApps, (v) => ss.setEmergencyLockedApps(v)),
                            child: Row(
                              children: [
                                const Icon(Icons.checklist, color: Colors.white54, size: 16),
                                const SizedBox(width: 6),
                                Text(
                                  ss.emergencyLockedApps.isEmpty
                                      ? '対象アプリ：全アプリ（タップして選択）'
                                      : '対象アプリ：${ss.emergencyLockedApps.length}個選択済み',
                                  style: const TextStyle(
                                      color: Colors.tealAccent, fontSize: 11,
                                      decoration: TextDecoration.underline),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                if (cooldown != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 16, bottom: 4),
                    child: _Hourglass(remaining: cooldown, message: '反映待ち'),
                  ),
                const Divider(color: Colors.white12, height: 12),
              ],
            );
          }),
          // Legacy lock mode (backward compat)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('レガシーロックモード',
                        style: TextStyle(color: Colors.white38, fontSize: 12)),
                    Text('全フロア移動・全アニメ設定を一括でクールダウン制限する旧モード',
                        style: TextStyle(color: Colors.white24, fontSize: 10)),
                  ],
                ),
              ),
              Switch(
                value: ss.lockModeEnabled,
                activeColor: Colors.orangeAccent,
                onChanged: (v) async {
                  await ss.setLockMode(v);
                  setState(() {});
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _showLockAppSelector(
      String label, List<String> currentApps, Future<void> Function(List<String>) onSave) async {
    final selected = Set<String>.from(currentApps);
    final apps = List<AppConfig>.from(_apps)
      ..sort((a, b) => a.appName.toLowerCase().compareTo(b.appName.toLowerCase()));

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInner) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          title: Row(
            children: [
              const Expanded(
                child: Text('ロック対象アプリを選択',
                    style: TextStyle(color: Colors.white, fontSize: 14)),
              ),
              TextButton(
                onPressed: () {
                  setInner(() {
                    if (selected.length == apps.length) {
                      selected.clear();
                    } else {
                      selected.addAll(apps.map((a) => a.packageName));
                    }
                  });
                },
                child: Text(
                  selected.length == apps.length ? '全解除' : '全選択',
                  style: const TextStyle(color: Colors.tealAccent, fontSize: 12),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            height: 400,
            child: ListView.builder(
              itemCount: apps.length,
              itemBuilder: (_, i) {
                final app = apps[i];
                final checked = selected.contains(app.packageName);
                return CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  activeColor: Colors.orangeAccent,
                  checkColor: Colors.black,
                  title: Text(
                    app.customName?.isNotEmpty == true ? app.customName! : app.appName,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
                  subtitle: Text(floorLabel(app.floor),
                      style: const TextStyle(color: Colors.white38, fontSize: 10)),
                  value: checked,
                  onChanged: (v) {
                    setInner(() {
                      if (v == true) {
                        selected.add(app.packageName);
                      } else {
                        selected.remove(app.packageName);
                      }
                    });
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('キャンセル', style: TextStyle(color: Colors.white54))),
            TextButton(
                onPressed: () async {
                  await onSave(selected.toList());
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: const Text('保存', style: TextStyle(color: Colors.white))),
          ],
        ),
      ),
    );
    setState(() {});
  }

  Widget _strictTypeChip(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? Colors.orangeAccent.withOpacity(0.2) : Colors.transparent,
          border: Border.all(
              color: selected ? Colors.orangeAccent : Colors.white24),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(label,
            style: TextStyle(
                color: selected ? Colors.orangeAccent : Colors.white54,
                fontSize: 11)),
      ),
    );
  }

  Future<int?> _showIntSliderDialog(String title, double initial, double min, double max) async {
    double value = initial;
    return showDialog<int>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInner) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          title: Text(title, style: const TextStyle(color: Colors.white, fontSize: 14)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${value.round()}', style: const TextStyle(color: Colors.white, fontSize: 18)),
              Slider(
                value: value, min: min, max: max, divisions: (max - min).round(),
                activeColor: Colors.tealAccent, inactiveColor: Colors.white24,
                onChanged: (v) => setInner(() => value = v),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('キャンセル', style: TextStyle(color: Colors.white54))),
            TextButton(onPressed: () => Navigator.pop(ctx, value.round()), child: const Text('OK', style: TextStyle(color: Colors.white))),
          ],
        ),
      ),
    );
  }
}
