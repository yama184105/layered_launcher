part of '../settings_screen.dart';

extension SecuritySettingsMethods on _SettingsScreenState {
  // ── Lock Mode section ──────────────────────────────────────────

  Widget _buildLockModeSection() {
    final s = S.of(context);
    final ss = _ss;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(s.strictMode,
              style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          Text(s.strictModeDesc,
              style: const TextStyle(color: Colors.white38, fontSize: 12)),
          const SizedBox(height: 12),
          ...BlockSettings.strictSubKeys.map((key) {
            final label = _strictSubLabel(s, key);
            final desc = _strictSubDesc(s, key);
            final enabled = ss.strictSubEnabled(key);
            final type = ss.strictSubType(key);
            final timer = ss.strictSubTimerMinutes(key);
            final cooldown = ss.strictSubCooldownRemaining(key);
            final typeLabel = type == 'block' ? s.fullBlock : s.timerWaitMinutes(timer);
            final offLabel = s.actionOff;
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
                          Text(enabled ? typeLabel : offLabel,
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
                                SnackBar(content: Text(S.of(context).submodeLocked)));
                            }
                            return;
                          }
                          // Timer-before-apply
                          final confirmed = await showStrictTimerDialog(context, seconds: ss.strictSubTimerSeconds('submode'));
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
                            _strictTypeChip(s.fullBlock, type == 'block', () async {
                              await ss.setStrictSubType(key, 'block');
                              setState(() {});
                            }),
                            const SizedBox(width: 8),
                            _strictTypeChip(s.timer, type == 'timer', () async {
                              await ss.setStrictSubType(key, 'timer');
                              setState(() {});
                            }),
                            if (type == 'timer') ...[
                              const SizedBox(width: 12),
                              GestureDetector(
                                onTap: () async {
                                  final v = await _showIntSliderDialog(
                                      s.timerMinutes, timer.toDouble(), 1, 30);
                                  if (v != null) {
                                    await ss.setStrictSubTimerMinutes(key, v);
                                    setState(() {});
                                  }
                                },
                                child: Text(s.minutesShortValue(timer),
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
                                      ? s.targetAllApps
                                      : s.targetAppsCount(ss.floorMoveLockedApps.length),
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
                                      ? s.targetAllApps
                                      : s.targetAppsCount(ss.emergencyLockedApps.length),
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
                    child: _Hourglass(remaining: cooldown, message: S.of(context).applyPending),
                  ),
                const Divider(color: Colors.white12, height: 12),
              ],
            );
          }),
          // Legacy lock mode (backward compat)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.legacyLockMode,
                        style: const TextStyle(color: Colors.white38, fontSize: 12)),
                    Text(s.legacyLockModeDesc,
                        style: const TextStyle(color: Colors.white24, fontSize: 10)),
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
              Expanded(
                child: Text(S.of(ctx).selectLockedApps,
                    style: const TextStyle(color: Colors.white, fontSize: 14)),
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
                  selected.length == apps.length ? S.of(ctx).deselectAll : S.of(ctx).selectAll,
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
                child: Text(S.of(ctx).actionCancel, style: const TextStyle(color: Colors.white54))),
            TextButton(
                onPressed: () async {
                  await onSave(selected.toList());
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: Text(S.of(ctx).actionSave, style: const TextStyle(color: Colors.white))),
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

  String _strictSubLabel(S s, String key) {
    switch (key) {
      case 'floorMove': return s.strictFloorMoveLabel;
      case 'animation': return s.strictAnimationLabel;
      case 'submode': return s.strictSubmodeLabel;
      case 'emergency': return s.strictEmergencyLabel;
      case 'shortcut': return s.strictShortcutLabel;
      default: return key;
    }
  }

  String _strictSubDesc(S s, String key) {
    switch (key) {
      case 'floorMove': return s.strictFloorMoveDesc;
      case 'animation': return s.strictAnimationDesc;
      case 'submode': return s.strictSubmodeDesc;
      case 'emergency': return s.strictEmergencyDesc;
      case 'shortcut': return s.strictShortcutDesc;
      default: return '';
    }
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
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(S.of(ctx).actionCancel, style: const TextStyle(color: Colors.white54))),
            TextButton(onPressed: () => Navigator.pop(ctx, value.round()), child: Text(S.of(ctx).actionConfirm, style: const TextStyle(color: Colors.white))),
          ],
        ),
      ),
    );
  }
}
