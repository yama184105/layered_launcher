part of '../settings_screen.dart';

extension AutoMoveSettingsMethods on _SettingsScreenState {
  List<Widget> _autoMoveSettingRows() {
    final s = S.of(context);
    final autoApps = _ss.allAutoMoveApps;
    String modeName(String mode) {
      switch (mode) {
        case 'schedule': return s.modeSchedule;
        case 'interval': return s.modeIntervalRandom;
        default: return s.notSet;
      }
    }
    return [
      // Collapsible header with view-mode toggle. Tapping the count
      // label toggles expand/collapse; the two badges on the right
      // toggle between per-app and grouped views.
      if (autoApps.isNotEmpty)
        Material(
          color: Colors.transparent,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() =>
                        _autoMoveListExpanded = !_autoMoveListExpanded),
                    child: Row(
                      children: [
                        Text(s.autoMoveAppsCount(autoApps.length),
                            style: const TextStyle(
                                color: Colors.white54, fontSize: 12)),
                        const SizedBox(width: 6),
                        Icon(
                          _autoMoveListExpanded
                              ? Icons.expand_less
                              : Icons.expand_more,
                          color: Colors.white38,
                          size: 18,
                        ),
                      ],
                    ),
                  ),
                ),
                if (_autoMoveListExpanded) ...[
                  _autoMoveViewToggle('アプリ別', !_autoMoveGrouped, () {
                    setState(() => _autoMoveGrouped = false);
                  }),
                  const SizedBox(width: 6),
                  _autoMoveViewToggle('内容別', _autoMoveGrouped, () {
                    setState(() => _autoMoveGrouped = true);
                  }),
                ],
              ],
            ),
          ),
        ),
      if (autoApps.isEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
          child: Text(s.noAutoMoveApps,
              style: const TextStyle(color: Colors.white38, fontSize: 12)),
        ),
      // Expanded list (per-app or grouped depending on toggle).
      if (_autoMoveListExpanded && !_autoMoveGrouped)
        ...autoApps.map((pkg) {
          final name = _apps.firstWhere(
            (a) => a.packageName == pkg,
            orElse: () => AppConfig(packageName: pkg, appName: pkg, floor: 1),
          );
          final displayName = (name.customName?.isNotEmpty == true) ? name.customName! : name.appName;
          final mode = _ss.autoMoveMode(pkg);
          final scheduleSummary = _autoMoveScheduleSummary(pkg, mode);
          return _autoMoveAppRow(
            pkg: pkg,
            displayName: displayName,
            modeLabel: modeName(mode),
            summary: scheduleSummary,
            onTap: () async {
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
            },
          );
        }),
      if (_autoMoveListExpanded && _autoMoveGrouped)
        ..._autoMoveGroupedRows(autoApps, modeName),
      // Floating-style bulk-edit button: appears when something is
      // selected so the user can apply the same change to the whole
      // selection in one go.
      if (_autoMoveSelected.isNotEmpty) _autoMoveSelectionBar(),
      _rowDivider,
      _settingRow(
        s.usageCountRulesScreenTitle,
        () {
          int total = 0;
          for (final a in _apps) {
            total += _ss.usageCountFloorRules(a.packageName).length;
          }
          return total == 0 ? s.notSet : s.usageCountSummaryFmt(total);
        }(),
        () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => _UsageCountRulesScreen(
                appService: _as,
                settingsService: _ss,
              ),
            ),
          );
          setState(() {});
        },
      ),
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
                Expanded(child: Text(S.of(ctx).selectApp, style: const TextStyle(color: Colors.white, fontSize: 14))),
                Text(S.of(ctx).selectionCountSuffix(selected.length), style: const TextStyle(color: Colors.white38, fontSize: 12)),
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
                          ? S.of(ctx).configuredLabel
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
                child: Text(S.of(ctx).actionCancel, style: const TextStyle(color: Colors.white54)),
              ),
              TextButton(
                onPressed: selected.isEmpty ? null : () => Navigator.pop(ctx, selected.toList()),
                child: Text(S.of(ctx).actionConfigure, style: const TextStyle(color: Colors.white)),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Builds an at-a-glance description of [pkg]'s auto-move schedule
  /// as it would apply RIGHT NOW. Two parts:
  ///   - effective floor of the currently-active slot
  ///   - timestamp of the next slot change
  /// e.g. "現在 2F / 次: 20:00 → 4F"
  /// Returns null when the app's mode is 'none' or for interval
  /// mode (which doesn't have intra-day slots).
  String? _autoMoveScheduleSummary(String pkg, String mode) {
    if (mode == 'interval') {
      final days = _ss.autoMoveIntervalDays(pkg);
      final floors = _ss.autoMoveIntervalFloors(pkg);
      if (floors.isEmpty) return null;
      return '${days}日ごとにランダム移動 (候補: ${floors.map((f) => floorLabel(f)).join(", ")})';
    }
    if (mode != 'schedule') return null;
    final raw = _ss.autoMoveSchedule(pkg);
    if (raw.isEmpty) return null;

    final now = DateTime.now();
    final weekday = now.weekday; // 1..7
    final nowMinute = now.hour * 60 + now.minute;

    final dayKey = weekday.toString();
    final dayData = raw[dayKey];
    if (dayData is! Map) return 'スケジュール未設定 (本日)';
    final defaultCfg = (dayData['default'] is Map)
        ? Map<String, dynamic>.from(dayData['default'] as Map)
        : null;
    final slots = (dayData['slots'] as List?) ?? [];

    // Find active slot now
    Map<String, dynamic>? active;
    int? activeEnd;
    int? nextStart;
    Map<String, dynamic>? nextSlot;
    for (final s in slots) {
      if (s is! Map) continue;
      final m = Map<String, dynamic>.from(s);
      final start = (m['startMinute'] as num?)?.toInt() ?? 0;
      final end = (m['endMinute'] as num?)?.toInt() ?? 0;
      if (nowMinute >= start && nowMinute < end) {
        active = m;
        activeEnd = end;
      } else if (start > nowMinute && (nextStart == null || start < nextStart)) {
        nextStart = start;
        nextSlot = m;
      }
    }

    String describeSlot(Map<String, dynamic> cfg) {
      final type = cfg['type'] as String? ?? 'fixed';
      if (type == 'random') {
        final list = (cfg['floors'] as List?)
                ?.map((e) => (e as num).toInt())
                .toList() ??
            const <int>[];
        if (list.isEmpty) return 'ランダム';
        return 'ランダム(${list.map((f) => floorLabel(f)).join(",")})';
      }
      final floor = (cfg['floor'] as num?)?.toInt();
      return floor != null ? floorLabel(floor) : '?';
    }

    final activeDesc = active != null
        ? describeSlot(active)
        : (defaultCfg != null ? describeSlot(defaultCfg) : '未設定');

    String fmtMin(int minute) {
      final h = (minute ~/ 60) % 24;
      final m = minute % 60;
      return '${h.toString().padLeft(2, "0")}:${m.toString().padLeft(2, "0")}';
    }

    final parts = <String>['現在 $activeDesc'];
    if (active != null && activeEnd != null) {
      parts.add('${fmtMin(activeEnd)} まで');
    } else if (nextSlot != null && nextStart != null) {
      parts.add('次: ${fmtMin(nextStart)} → ${describeSlot(nextSlot)}');
    }
    return parts.join(' / ');
  }

  /// Small pill widget used to switch between "アプリ別" / "内容別"
  /// views in the auto-move section header.
  Widget _autoMoveViewToggle(String label, bool selected, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: selected
              ? Colors.tealAccent.withOpacity(0.15)
              : Colors.transparent,
          border: Border.all(
            color: selected ? Colors.tealAccent : Colors.white24,
            width: 1,
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.tealAccent : Colors.white54,
            fontSize: 11,
            fontWeight: selected ? FontWeight.w500 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  /// Build the "by-content" view: apps sharing the exact same
  /// auto-move configuration (mode + schedule JSON + interval
  /// settings) are merged into one row. Tap a row to expand and
  /// see member apps; tap a member to jump into its config screen.
  /// Long-press to enter selection mode for bulk edit.
  ///
  /// Fingerprint = canonical JSON of (mode, schedule, interval)
  /// so any change — including AI-driven tweaks — moves the app
  /// into its own group automatically. Apps with mode=='none'
  /// land in a dedicated "未設定" group so the user can configure
  /// them without a separate "アプリを選択" entry point.
  List<Widget> _autoMoveGroupedRows(
    List<String> autoApps,
    String Function(String) modeName,
  ) {
    // pkgs grouped by fingerprint, in insertion order.
    final groups = <String, List<String>>{};
    // Configured apps (mode != 'none') first.
    for (final pkg in autoApps) {
      final fp = _scheduleFingerprint(pkg);
      groups.putIfAbsent(fp, () => []).add(pkg);
    }
    // Unconfigured (mode == 'none'): collect every installed app
    // not already in autoApps into a single 未設定 group. Same
    // canonical-JSON fingerprint as setting mode='none' explicitly.
    final configured = autoApps.toSet();
    final unconfiguredFp = _canonicalJson({'mode': 'none'});
    for (final a in _apps) {
      if (configured.contains(a.packageName)) continue;
      groups.putIfAbsent(unconfiguredFp, () => []).add(a.packageName);
    }
    // Sort groups by size descending so the biggest cluster (most
    // commonly "the default schedule of 90 apps") shows first.
    final sortedEntries = groups.entries.toList()
      ..sort((a, b) => b.value.length.compareTo(a.value.length));

    final widgets = <Widget>[];
    for (final entry in sortedEntries) {
      final fp = entry.key;
      final members = entry.value;
      final repPkg = members.first;
      final mode = _ss.autoMoveMode(repPkg);
      final summary = _autoMoveScheduleSummary(repPkg, mode);
      final isExpanded = _autoMoveExpandedGroups.contains(fp);
      final selectionMode = _autoMoveSelected.isNotEmpty;
      // A group is "fully selected" when all of its members are in
      // _autoMoveSelected. Used to show ✓ on the group row and to
      // bulk-toggle when tapped in selection mode.
      final fullySelected =
          members.every((m) => _autoMoveSelected.contains(m));
      final partiallySelected =
          !fullySelected && members.any((m) => _autoMoveSelected.contains(m));

      widgets.add(Material(
        color: fullySelected
            ? Colors.tealAccent.withOpacity(0.08)
            : partiallySelected
                ? Colors.tealAccent.withOpacity(0.04)
                : Colors.transparent,
        child: InkWell(
          // Default tap = expand/collapse. In selection mode, tap
          // toggles the whole group. Bulk-edit is via long-press OR
          // the dedicated 編集 button on the right of the row.
          onTap: () {
            if (selectionMode) {
              setState(() {
                if (fullySelected) {
                  _autoMoveSelected.removeAll(members);
                } else {
                  _autoMoveSelected.addAll(members);
                }
              });
            } else {
              setState(() {
                if (isExpanded) {
                  _autoMoveExpandedGroups.remove(fp);
                } else {
                  _autoMoveExpandedGroups.add(fp);
                }
              });
            }
          },
          onLongPress: () {
            setState(() {
              if (fullySelected) {
                _autoMoveSelected.removeAll(members);
              } else {
                _autoMoveSelected.addAll(members);
              }
            });
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                if (selectionMode)
                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: Icon(
                      fullySelected
                          ? Icons.check_box
                          : partiallySelected
                              ? Icons.indeterminate_check_box
                              : Icons.check_box_outline_blank,
                      color: fullySelected || partiallySelected
                          ? Colors.tealAccent
                          : Colors.white38,
                      size: 18,
                    ),
                  ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${members.length} 個のアプリ',
                              style: TextStyle(
                                  color: fullySelected
                                      ? Colors.tealAccent
                                      : Colors.white,
                                  fontSize: 14),
                            ),
                          ),
                          Text(modeName(mode),
                              style: const TextStyle(
                                  color: Colors.white54, fontSize: 12)),
                        ],
                      ),
                      if (summary != null && summary.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(summary,
                              style: const TextStyle(
                                  color: Colors.tealAccent, fontSize: 11)),
                        ),
                    ],
                  ),
                ),
                // Inline "編集" button so the user can jump straight
                // to bulk-edit on a whole group without going through
                // long-press → selection mode → 編集 button.
                if (!selectionMode)
                  GestureDetector(
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => AutoMoveScreen(
                            settingsService: _ss,
                            packageNames: members,
                            allApps: _apps,
                          ),
                        ),
                      );
                      if (mounted) setState(() {});
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        border: Border.all(
                            color: Colors.tealAccent.withOpacity(0.4)),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text('編集',
                          style: TextStyle(
                              color: Colors.tealAccent, fontSize: 11)),
                    ),
                  ),
                const SizedBox(width: 6),
                Icon(
                  isExpanded ? Icons.expand_less : Icons.expand_more,
                  color: Colors.white38,
                  size: 18,
                ),
              ],
            ),
          ),
        ),
      ));

      if (isExpanded) {
        for (final pkg in members) {
          final name = _apps.firstWhere(
            (a) => a.packageName == pkg,
            orElse: () => AppConfig(packageName: pkg, appName: pkg, floor: 1),
          );
          final displayName = (name.customName?.isNotEmpty == true)
              ? name.customName!
              : name.appName;
          final memberSelected = _autoMoveSelected.contains(pkg);
          widgets.add(Material(
            color: memberSelected
                ? Colors.tealAccent.withOpacity(0.08)
                : Colors.white.withOpacity(0.02),
            child: InkWell(
              onTap: () async {
                if (selectionMode) {
                  setState(() {
                    if (memberSelected) {
                      _autoMoveSelected.remove(pkg);
                    } else {
                      _autoMoveSelected.add(pkg);
                    }
                  });
                  return;
                }
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
              },
              onLongPress: () {
                setState(() {
                  if (memberSelected) {
                    _autoMoveSelected.remove(pkg);
                  } else {
                    _autoMoveSelected.add(pkg);
                  }
                });
              },
              child: Padding(
                padding: const EdgeInsets.fromLTRB(40, 8, 16, 8),
                child: Row(
                  children: [
                    if (selectionMode)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Icon(
                          memberSelected
                              ? Icons.check_box
                              : Icons.check_box_outline_blank,
                          color: memberSelected
                              ? Colors.tealAccent
                              : Colors.white38,
                          size: 16,
                        ),
                      ),
                    Expanded(
                      child: Text(displayName,
                          style: TextStyle(
                              color: memberSelected
                                  ? Colors.tealAccent
                                  : Colors.white70,
                              fontSize: 13)),
                    ),
                    if (!selectionMode)
                      const Icon(Icons.chevron_right,
                          color: Colors.white24, size: 14),
                  ],
                ),
              ),
            ),
          ));
        }
      }
    }
    return widgets;
  }

  /// Canonical JSON of an app's full auto-move config. Two apps with
  /// identical fingerprints share the exact same behaviour, so they
  /// can be safely shown as one row in the grouped view.
  /// Includes mode, schedule data, interval days+floors. Apps that
  /// differ in any field (mode swap, slot change, floor list edit,
  /// etc.) end up in different groups.
  String _scheduleFingerprint(String pkg) {
    final mode = _ss.autoMoveMode(pkg);
    final payload = <String, dynamic>{
      'mode': mode,
      if (mode == 'schedule') 'schedule': _ss.autoMoveSchedule(pkg),
      if (mode == 'interval') ...{
        'intervalDays': _ss.autoMoveIntervalDays(pkg),
        'intervalFloors': _ss.autoMoveIntervalFloors(pkg),
      },
    };
    return _canonicalJson(payload);
  }

  /// JSON-encode [value] with map keys sorted alphabetically so the
  /// output is deterministic regardless of insertion order. Needed
  /// because the schedule JSON is built incrementally over time and
  /// two semantically-equal schedules might serialize in different
  /// orders otherwise.
  String _canonicalJson(Object? value) {
    if (value is Map) {
      final keys = value.keys.map((k) => k.toString()).toList()..sort();
      final buf = StringBuffer('{');
      for (var i = 0; i < keys.length; i++) {
        if (i > 0) buf.write(',');
        buf.write(jsonEncode(keys[i]));
        buf.write(':');
        buf.write(_canonicalJson(value[keys[i]]));
      }
      buf.write('}');
      return buf.toString();
    }
    if (value is List) {
      final buf = StringBuffer('[');
      for (var i = 0; i < value.length; i++) {
        if (i > 0) buf.write(',');
        buf.write(_canonicalJson(value[i]));
      }
      buf.write(']');
      return buf.toString();
    }
    return jsonEncode(value);
  }

  /// Two-line app row used in the auto-move section: title + mode
  /// label on the first line, schedule summary on the second.
  Widget _autoMoveAppRow({
    required String pkg,
    required String displayName,
    required String modeLabel,
    required String? summary,
    required VoidCallback onTap,
  }) {
    final selected = _autoMoveSelected.contains(pkg);
    final selectionMode = _autoMoveSelected.isNotEmpty;
    return Material(
      color: selected
          ? Colors.tealAccent.withOpacity(0.08)
          : Colors.transparent,
      child: InkWell(
        onTap: () {
          // In selection mode, taps toggle membership instead of
          // jumping to the detail screen — same UX as the photo
          // gallery / file manager idiom.
          if (selectionMode) {
            setState(() {
              if (selected) {
                _autoMoveSelected.remove(pkg);
              } else {
                _autoMoveSelected.add(pkg);
              }
            });
          } else {
            onTap();
          }
        },
        onLongPress: () {
          setState(() {
            if (selected) {
              _autoMoveSelected.remove(pkg);
            } else {
              _autoMoveSelected.add(pkg);
            }
          });
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              if (selectionMode)
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Icon(
                    selected
                        ? Icons.check_box
                        : Icons.check_box_outline_blank,
                    color:
                        selected ? Colors.tealAccent : Colors.white38,
                    size: 18,
                  ),
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(displayName,
                              style: TextStyle(
                                  color: selected
                                      ? Colors.tealAccent
                                      : Colors.white,
                                  fontSize: 14)),
                        ),
                        Text(modeLabel,
                            style: const TextStyle(
                                color: Colors.white54, fontSize: 12)),
                      ],
                    ),
                    if (summary != null && summary.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(summary,
                            style: const TextStyle(
                                color: Colors.tealAccent, fontSize: 11)),
                      ),
                  ],
                ),
              ),
              if (!selectionMode)
                const Icon(Icons.chevron_right,
                    color: Colors.white24, size: 16),
            ],
          ),
        ),
      ),
    );
  }

  /// Action bar shown when one or more apps are selected. Provides
  /// the bulk-edit entry point + a quick deselect. Rendered inline
  /// in the settings list (not a true floating action bar) so it
  /// sits right under the relevant app rows.
  Widget _autoMoveSelectionBar() {
    final n = _autoMoveSelected.length;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.tealAccent.withOpacity(0.1),
        border: Border.all(color: Colors.tealAccent.withOpacity(0.4)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '$n 件選択中',
              style: const TextStyle(
                color: Colors.tealAccent,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          TextButton(
            onPressed: () => setState(() => _autoMoveSelected.clear()),
            child: const Text('解除',
                style: TextStyle(color: Colors.white54, fontSize: 12)),
          ),
          const SizedBox(width: 4),
          TextButton(
            style: TextButton.styleFrom(
              backgroundColor: Colors.tealAccent.withOpacity(0.2),
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            ),
            onPressed: () async {
              final selected = _autoMoveSelected.toList();
              setState(() => _autoMoveSelected.clear());
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
              if (mounted) setState(() {});
            },
            child: const Text('編集',
                style: TextStyle(
                    color: Colors.tealAccent, fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

// ── Usage-count floor rules screen ───────────────────────────────────────────
// Lists all apps; per-app rules `{threshold, floor}` change the app's floor
// once today's launch count crosses the threshold. Counts reset at midnight.

class _UsageCountRulesScreen extends StatefulWidget {
  final AppService appService;
  final SettingsService settingsService;
  const _UsageCountRulesScreen({
    required this.appService,
    required this.settingsService,
  });
  @override
  State<_UsageCountRulesScreen> createState() => _UsageCountRulesScreenState();
}

class _UsageCountRulesScreenState extends State<_UsageCountRulesScreen> {
  List<AppConfig> _apps = [];
  bool _loading = true;

  SettingsService get _ss => widget.settingsService;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final apps = await widget.appService.getAllApps();
    if (!mounted) return;
    setState(() {
      _apps = apps;
      _loading = false;
    });
  }

  String _displayName(AppConfig app) =>
      (app.customName?.isNotEmpty == true) ? app.customName! : app.appName;

  Future<void> _addOrEditRule(
    String pkg, {
    Map<String, int>? existing,
    int? editIndex,
  }) async {
    final s = S.of(context);
    final rules = _ss.usageCountFloorRules(pkg);
    int threshold = existing?['threshold'] ?? 5;
    int floor = existing?['floor'] ?? 2;
    final threshCtrl =
        TextEditingController(text: threshold.toString());

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInner) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          title: Text(existing == null ? s.ruleAdd : s.ruleEdit,
              style: const TextStyle(color: Colors.white, fontSize: 14)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(s.launchThresholdLabel,
                  style: const TextStyle(color: Colors.white54, fontSize: 12)),
              const SizedBox(height: 4),
              TextField(
                controller: threshCtrl,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.07),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: BorderSide.none,
                  ),
                  suffixText: s.thresholdSuffix,
                  suffixStyle:
                      const TextStyle(color: Colors.white38, fontSize: 12),
                ),
                onChanged: (v) =>
                    threshold = int.tryParse(v) ?? threshold,
              ),
              const SizedBox(height: 12),
              Text(s.targetFloorLabel,
                  style: const TextStyle(color: Colors.white54, fontSize: 12)),
              const SizedBox(height: 4),
              StatefulBuilder(
                builder: (_, setWrap) {
                  Widget chip(int f) {
                    final sel = floor == f;
                    return GestureDetector(
                      onTap: () => setWrap(() => floor = f),
                      child: Container(
                        width: 44,
                        height: 30,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: sel ? Colors.white : Colors.transparent,
                          border: Border.all(
                              color: sel ? Colors.white : Colors.white38),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(floorLabel(f),
                            style: TextStyle(
                                color: sel ? Colors.black : Colors.white54,
                                fontSize: 11)),
                      ),
                    );
                  }

                  return Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (int i = _ss.undergroundFloors; i >= 1; i--) chip(-i),
                      for (int i = 1; i <= _ss.maxFloors; i++) chip(i),
                    ],
                  );
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(s.actionCancel,
                  style: const TextStyle(color: Colors.white54)),
            ),
            TextButton(
              onPressed: () {
                threshold = int.tryParse(threshCtrl.text) ?? threshold;
                Navigator.pop(ctx, true);
              },
              child: Text(s.actionSave,
                  style: const TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;

    final updated = [...rules];
    final newRule = {'threshold': threshold, 'floor': floor};
    if (editIndex != null) {
      updated[editIndex] = newRule;
    } else {
      updated.add(newRule);
    }
    updated.sort((a, b) => a['threshold']!.compareTo(b['threshold']!));
    await _ss.setUsageCountFloorRules(pkg, updated);
    setState(() {});
  }

  Future<void> _deleteRule(String pkg, int index) async {
    final rules = [..._ss.usageCountFloorRules(pkg)];
    rules.removeAt(index);
    await _ss.setUsageCountFloorRules(pkg, rules);
    setState(() {});
  }

  Future<String?> _pickAppDialog() async {
    final sorted = List<AppConfig>.from(_apps)
      ..sort((a, b) => _displayName(a)
          .toLowerCase()
          .compareTo(_displayName(b).toLowerCase()));
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: Text(S.of(ctx).selectApp,
            style: const TextStyle(color: Colors.white, fontSize: 14)),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: ListView.builder(
            itemCount: sorted.length,
            itemBuilder: (_, i) {
              final app = sorted[i];
              final hasRules =
                  _ss.usageCountFloorRules(app.packageName).isNotEmpty;
              return ListTile(
                dense: true,
                title: Text(_displayName(app),
                    style: const TextStyle(
                        color: Colors.white, fontSize: 13)),
                trailing: hasRules
                    ? const Icon(Icons.check,
                        color: Colors.tealAccent, size: 16)
                    : null,
                onTap: () => Navigator.pop(ctx, app.packageName),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(S.of(ctx).actionCancel,
                style: const TextStyle(color: Colors.white54)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final appsWithRules = _apps
        .where((a) => _ss.usageCountFloorRules(a.packageName).isNotEmpty)
        .toList()
      ..sort((a, b) => _displayName(a)
          .toLowerCase()
          .compareTo(_displayName(b).toLowerCase()));

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(s.usageCountRulesScreenTitle,
            style: const TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Text(s.usageCountRulesHelp,
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 12)),
                ),
                const Divider(color: Colors.white12, height: 1),
                if (appsWithRules.isEmpty)
                  Padding(
                    padding:
                        const EdgeInsets.fromLTRB(16, 24, 16, 8),
                    child: Text(s.usageCountNoApps,
                        style: const TextStyle(
                            color: Colors.white38, fontSize: 13)),
                  ),
                for (final app in appsWithRules)
                  _appRulesBlock(context, app),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white70,
                      side: const BorderSide(color: Colors.white24),
                    ),
                    icon: const Icon(Icons.add, size: 16),
                    label: Text(s.usageCountAddAppButton,
                        style: const TextStyle(fontSize: 13)),
                    onPressed: () async {
                      final pkg = await _pickAppDialog();
                      if (pkg == null || !mounted) return;
                      await _addOrEditRule(pkg);
                    },
                  ),
                ),
              ],
            ),
    );
  }

  Widget _appRulesBlock(BuildContext context, AppConfig app) {
    final s = S.of(context);
    final pkg = app.packageName;
    final rules = _ss.usageCountFloorRules(pkg);
    final todayCount = _ss.dailyLaunchCount(pkg);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(_displayName(app),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w500)),
              ),
              TextButton.icon(
                onPressed: () => _addOrEditRule(pkg),
                style: TextButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                icon: const Icon(Icons.add,
                    color: Colors.tealAccent, size: 16),
                label: Text(s.actionAdd,
                    style: const TextStyle(
                        color: Colors.tealAccent, fontSize: 12)),
              ),
            ],
          ),
          Text(s.todayLaunchCount(todayCount),
              style:
                  const TextStyle(color: Colors.white38, fontSize: 11)),
          const SizedBox(height: 4),
          ...rules.asMap().entries.map((e) {
            final i = e.key;
            final rule = e.value;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      s.thresholdRule(
                          rule['threshold']!, floorLabel(rule['floor']!)),
                      style: const TextStyle(
                          color: Colors.white60, fontSize: 12),
                    ),
                  ),
                  GestureDetector(
                    onTap: () =>
                        _addOrEditRule(pkg, existing: rule, editIndex: i),
                    child: const Icon(Icons.edit,
                        color: Colors.white38, size: 16),
                  ),
                  const SizedBox(width: 12),
                  GestureDetector(
                    onTap: () => _deleteRule(pkg, i),
                    child: const Icon(Icons.delete,
                        color: Colors.redAccent, size: 16),
                  ),
                ],
              ),
            );
          }),
          const Divider(color: Colors.white12, height: 16),
        ],
      ),
    );
  }
}
