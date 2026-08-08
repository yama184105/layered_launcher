part of '../settings_screen.dart';

extension SecuritySettingsMethods on _SettingsScreenState {
  // ── Lock Mode section ──────────────────────────────────────────

  Widget _buildLockModeSection() {
    final s = S.of(context);
    final ss = _ss;
    final reservations = ss.strictReservations;
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
          // ── 予約変更 ────────────────────────────────────────────
          // ロックされた変更を今すぐではなく指定時間後に自動適用する。
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.strictReservation,
                        style: const TextStyle(color: Colors.white, fontSize: 13)),
                    Text(s.strictReservationDesc,
                        style: const TextStyle(color: Colors.white30, fontSize: 10)),
                  ],
                ),
              ),
              Switch(
                value: ss.strictReservationEnabled,
                activeColor: Colors.tealAccent,
                onChanged: (v) async {
                  await ss.setStrictReservationEnabled(v);
                  setState(() {});
                },
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 16, bottom: 4),
            child: Row(
              children: [
                if (ss.strictReservationEnabled)
                  GestureDetector(
                    onTap: _showReservationDelayPicker,
                    child: Text(
                      s.reservationAppliesIn(_reservationDelayLabel()),
                      style: const TextStyle(
                          color: Colors.tealAccent, fontSize: 11,
                          decoration: TextDecoration.underline),
                    ),
                  ),
                const Spacer(),
                GestureDetector(
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            StrictReservationsScreen(settingsService: ss),
                      ),
                    );
                    if (mounted) setState(() {});
                  },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.event_available,
                          color: reservations.isEmpty
                              ? Colors.white38
                              : Colors.tealAccent,
                          size: 16),
                      const SizedBox(width: 4),
                      Text(
                        reservations.isEmpty
                            ? s.reservationsTitle
                            : s.reservationPendingCount(reservations.length),
                        style: TextStyle(
                            color: reservations.isEmpty
                                ? Colors.white38
                                : Colors.tealAccent,
                            fontSize: 11,
                            decoration: TextDecoration.underline),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(color: Colors.white12, height: 16),
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
                        final ok = await _gateSubmodeChange(
                          ReservationKinds.strictSubEnabled,
                          {'key': key, 'value': v},
                          S.of(context).reservationStrictToggleLabel(
                              label, v ? s.actionEnabled : s.actionDisabled),
                          selfChange: key == 'submode',
                        );
                        if (!ok || !mounted) return;
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
                            // 完全ブロック → タイマーは制限を緩める向きなのでゲートを通す
                            _strictTypeChip(s.timer, type == 'timer', () async {
                              if (type == 'block') {
                                final ok = await _gateSubmodeChange(
                                  ReservationKinds.strictSubType,
                                  {'key': key, 'value': 'timer'},
                                  '$label — ${s.timer}',
                                  selfChange: key == 'submode',
                                );
                                if (!ok || !mounted) return;
                              }
                              await ss.setStrictSubType(key, 'timer');
                              setState(() {});
                            }),
                            if (type == 'timer') ...[
                              const SizedBox(width: 12),
                              GestureDetector(
                                onTap: () async {
                                  final v = await _showIntSliderDialog(
                                      s.timerMinutes, timer.toDouble(), 1, 30);
                                  if (v == null || !mounted || v == timer) return;
                                  // 待ち時間を短くするのは制限を緩める変更
                                  if (v < timer) {
                                    final ok = await _gateSubmodeChange(
                                      ReservationKinds.strictSubTimer,
                                      {'key': key, 'value': v},
                                      '$label — ${s.minutesShortValue(v)}',
                                      selfChange: key == 'submode',
                                    );
                                    if (!ok || !mounted) return;
                                  }
                                  await ss.setStrictSubTimerMinutes(key, v);
                                  setState(() {});
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
                            onTap: _showFloorMoveLockSelector,
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
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(s.strictLockAddImmediateHint,
                                style: const TextStyle(
                                    color: Colors.white24, fontSize: 10)),
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
        ],
      ),
    );
  }

  /// 「サブモード設定ロック」のゲート。戻り値 true = そのまま変更してよい
  /// （false は予約に回した／ブロック／キャンセル）。
  ///
  /// [selfChange] はサブモード設定ロック自身を変えるとき。完全ブロックでも
  /// 待ち時間か予約でなら通す（でないと二度と解除できなくなる）。
  Future<bool> _gateSubmodeChange(
    String kind,
    Map<String, dynamic> data,
    String label, {
    bool selfChange = false,
  }) async {
    final result = await requestStrictAction(
      context,
      _ss,
      key: 'submode',
      blockedMessage: S.of(context).submodeLocked,
      reservationKind: kind,
      reservationData: data,
      reservationLabel: label,
      treatBlockAsTimer: selfChange,
    );
    if (result == StrictGateResult.reserved && mounted) setState(() {});
    return result == StrictGateResult.allowed;
  }

  String _reservationDelayLabel() {
    final minutes = _ss.strictReservationMinutes;
    final s = S.of(context);
    return minutes >= 60
        ? s.durationHourMinute(minutes ~/ 60, minutes % 60)
        : s.durationMinute(minutes);
  }

  Future<void> _showReservationDelayPicker() async {
    const presets = [15, 30, 60, 120, 360, 720, 1440];
    final picked = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: Text(S.of(ctx).strictReservationMinutes,
            style: const TextStyle(color: Colors.white, fontSize: 14)),
        content: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: presets.map((m) {
            final sel = _ss.strictReservationMinutes == m;
            return GestureDetector(
              onTap: () => Navigator.pop(ctx, m),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: sel ? Colors.tealAccent : Colors.transparent,
                  border: Border.all(color: sel ? Colors.tealAccent : Colors.white24),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  m >= 60
                      ? S.of(ctx).durationHourMinute(m ~/ 60, m % 60)
                      : S.of(ctx).durationMinute(m),
                  style: TextStyle(
                      color: sel ? Colors.black : Colors.white70, fontSize: 12),
                ),
              ),
            );
          }).toList(),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(S.of(ctx).actionCancel,
                  style: const TextStyle(color: Colors.white54))),
        ],
      ),
    );
    if (picked == null || !mounted) return;
    await _ss.setStrictReservationMinutes(picked);
    setState(() {});
  }

  /// フロア移動ロックの対象アプリ編集。追加は即時、対象を減らす
  /// （＝ロックを緩める）変更はタイマー待ちか予約を挟む。
  Future<void> _showFloorMoveLockSelector() async {
    final ss = _ss;
    final before = ss.floorMoveLockedApps.toSet();
    final picked = await _pickLockApps(before);
    if (picked == null || !mounted) return;

    final added = picked.difference(before);
    if (added.isNotEmpty) {
      await ss.addFloorMoveLockedApps(added);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(S.of(context).strictLockAddedCount(added.length))));
      }
    }

    // 空リストは「全アプリ対象」の意味なので、そこから絞るのも緩和にあたる。
    final removedCount =
        before.isEmpty ? picked.length : before.difference(picked).length;
    if (removedCount > 0 && mounted) {
      final result = await requestStrictAction(
        context,
        ss,
        key: 'floorMove',
        blockedMessage: S.of(context).strictLockRemoveLocked,
        reservationKind: ReservationKinds.floorMoveLockSet,
        reservationData: {'apps': picked.toList()},
        reservationLabel: S.of(context).strictLockRemoveLabel(removedCount),
      );
      if (result == StrictGateResult.allowed) {
        await ss.setFloorMoveLockedApps(picked.toList());
      }
    }
    if (mounted) setState(() {});
  }

  /// アプリを選ばせてそのまま保存する版（フロア移動ロック以外の用途）。
  Future<void> _showLockAppSelector(
    String label,
    List<String> currentApps,
    Future<void> Function(List<String>) onSave,
  ) async {
    final picked = await _pickLockApps(currentApps.toSet());
    if (picked != null) await onSave(picked.toList());
    if (mounted) setState(() {});
  }

  /// ロック対象アプリのチェックボックスダイアログ。確定した選択を返す
  /// （キャンセルなら null）。保存は呼び出し側が行う。
  Future<Set<String>?> _pickLockApps(Set<String> currentApps) async {
    final selected = Set<String>.from(currentApps);
    final apps = List<AppConfig>.from(_apps)
      ..sort((a, b) => a.appName.toLowerCase().compareTo(b.appName.toLowerCase()));

    return showDialog<Set<String>>(
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
                onPressed: () => Navigator.pop(ctx, selected),
                child: Text(S.of(ctx).actionSave, style: const TextStyle(color: Colors.white))),
          ],
        ),
      ),
    );
  }

  Widget _strictTypeChip(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? Colors.orangeAccent.withValues(alpha: 0.2) : Colors.transparent,
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
