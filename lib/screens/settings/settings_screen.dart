import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../../l10n/s.dart';
import '../../models/app_config.dart';
import '../../services/app_service.dart';
import '../../services/native_service.dart';
import '../../services/settings_service.dart';
import '../home/home_screen.dart'
    show floorLabel, showStrictTimerDialog, formatLastUsedRelative;
import 'automove_screen.dart';
import '../ai_command/ai_command_screen.dart';
import '../ai_command/ai_settings_screen.dart';

part 'app_block_screen.dart';
part 'batch_groups_screen.dart';
part 'wallpaper_crop_screen.dart';
part 'parts/home_settings_part.dart';
part 'parts/floor_settings_part.dart';
part 'parts/appearance_settings_part.dart';
part 'parts/app_management_part.dart';
part 'parts/automove_settings_part.dart';
part 'parts/gesture_settings_part.dart';
part 'parts/screentime_settings_part.dart';
part 'parts/security_settings_part.dart';
part 'parts/backup_settings_part.dart';

// ── Shared color picker ───────────────────────────────────────────────────────
List<(Color, String)> _sharedColorSwatchesFor(BuildContext context) {
  final s = S.of(context);
  return <(Color, String)>[
    (Colors.black, s.swatchBlack),
    (Colors.white, s.swatchWhite),
    (Colors.transparent, s.swatchTransparent),
    (const Color(0xFF212121), s.swatchGray900),
    (const Color(0xFF616161), s.swatchGray600),
    (const Color(0xFFBDBDBD), s.swatchGray400),
    (const Color(0xFF0D47A1), s.swatchBlue900),
    (const Color(0xFF1565C0), s.swatchBlue700),
    (const Color(0xFF2196F3), s.swatchBlue),
    (const Color(0xFF1A237E), s.swatchIndigo900),
    (const Color(0xFF3F51B5), s.swatchIndigo),
    (const Color(0xFFB71C1C), s.swatchRed900),
    (const Color(0xFFF44336), s.swatchRed),
    (const Color(0xFF1B5E20), s.swatchGreen900),
    (const Color(0xFF4CAF50), s.swatchGreen),
    (const Color(0xFFE65100), s.swatchOrange900),
    (const Color(0xFFFF9800), s.swatchOrange),
  ];
}

Future<Color?> _showSharedColorPicker(BuildContext context, {Color? current, SettingsService? ss}) async {
  Color? selected = current;
  final swatches = _sharedColorSwatchesFor(context);
  return showDialog<Color>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setInner) {
        final customColors = ss?.customColors ?? [];
        return AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          title: Text(S.of(ctx).selectColor, style: const TextStyle(color: Colors.white, fontSize: 14)),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 4, mainAxisSpacing: 8, crossAxisSpacing: 8, childAspectRatio: 0.85,
                    ),
                    itemCount: swatches.length,
                    itemBuilder: (_, i) {
                      final c = swatches[i].$1;
                      final label = swatches[i].$2;
                      final isSel = selected == c ||
                          (selected != null && c != Colors.transparent && selected!.value == c.value);
                      final isTransparent = c == Colors.transparent;
                      return GestureDetector(
                        onTap: () => setInner(() => selected = c),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 36, height: 36,
                              decoration: BoxDecoration(
                                color: isTransparent ? null : c,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: isSel ? Colors.white : Colors.white24,
                                  width: isSel ? 2.5 : 1,
                                ),
                              ),
                              child: isTransparent
                                  ? Center(child: Text(S.of(ctx).swatchTransparentMark, style: const TextStyle(color: Colors.white38, fontSize: 10)))
                                  : null,
                            ),
                            const SizedBox(height: 3),
                            Text(label, textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.white38, fontSize: 7)),
                          ],
                        ),
                      );
                    },
                  ),
                  if (customColors.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(S.of(ctx).customSection, style: const TextStyle(color: Colors.white38, fontSize: 11)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: customColors.map((c) {
                        final isSel = selected != null && selected!.value == c.value;
                        return GestureDetector(
                          onTap: () => setInner(() => selected = c),
                          onLongPress: () async {
                            await ss?.removeCustomColor(c);
                            setInner(() {});
                          },
                          child: Container(
                            width: 36, height: 36,
                            decoration: BoxDecoration(
                              color: c,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isSel ? Colors.white : Colors.white24,
                                width: isSel ? 2.5 : 1,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                  const SizedBox(height: 8),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white54,
                      padding: EdgeInsets.zero,
                    ),
                    icon: const Icon(Icons.colorize, size: 16),
                    label: Text(S.of(ctx).addCustomColor, style: const TextStyle(fontSize: 12)),
                    onPressed: () async {
                      Color pickerColor = selected ?? Colors.white;
                      final result = await showDialog<Color>(
                        context: ctx,
                        builder: (ctx2) => AlertDialog(
                          backgroundColor: const Color(0xFF1A1A1A),
                          title: Text(S.of(ctx2).customColor, style: const TextStyle(color: Colors.white, fontSize: 14)),
                          content: SingleChildScrollView(
                            child: ColorPicker(
                              pickerColor: pickerColor,
                              onColorChanged: (c) => pickerColor = c,
                              colorPickerWidth: 280,
                              pickerAreaHeightPercent: 0.7,
                              enableAlpha: false,
                              displayThumbColor: true,
                              labelTypes: const [],
                              paletteType: PaletteType.hsv,
                            ),
                          ),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx2), child: Text(S.of(ctx2).actionCancel, style: const TextStyle(color: Colors.white54))),
                            TextButton(onPressed: () => Navigator.pop(ctx2, pickerColor), child: Text(S.of(ctx2).actionAdd, style: const TextStyle(color: Colors.white))),
                          ],
                        ),
                      );
                      if (result != null) {
                        await ss?.addCustomColor(result);
                        setInner(() { selected = result; });
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(S.of(ctx).actionCancel, style: const TextStyle(color: Colors.white54)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, selected),
              child: Text(S.of(ctx).actionConfirm, style: const TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    ),
  );
}


// ── Hourglass countdown widget ────────────────────────────────────────────────

class _Hourglass extends StatefulWidget {
  final Duration remaining;
  final String message;
  const _Hourglass({required this.remaining, required this.message});

  @override
  State<_Hourglass> createState() => _HourglassState();
}

class _HourglassState extends State<_Hourglass>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _rot;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 2))
      ..repeat(reverse: true);
    _rot = Tween<double>(begin: -0.06, end: 0.06).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.remaining;
    final mins = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final secs = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.amber.withOpacity(0.08),
        border: Border.all(color: Colors.amber.withOpacity(0.5)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          RotationTransition(
            turns: _rot,
            child: const Icon(Icons.hourglass_empty,
                color: Colors.amber, size: 28),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.message,
                  style:
                      const TextStyle(color: Colors.amber, fontSize: 12)),
              const SizedBox(height: 2),
              Text(
                '${S.of(context).remainingTime}  $mins:$secs',
                style: const TextStyle(
                  color: Colors.amber,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}


// ── Settings Screen ───────────────────────────────────────────────────────────

class SettingsScreen extends StatefulWidget {
  final AppService appService;
  final SettingsService settingsService;

  const SettingsScreen(
      {super.key,
      required this.appService,
      required this.settingsService});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  List<AppConfig> _apps = [];
  bool _loading = true;
  Timer? _timer;

  // Accordion state - single open section (null = all collapsed)
  String? _openSection;

  // Animation sub-section accordion ('type' | 'speed' | 'pair' | null)
  String? _openAnimSubSection;

  // Generic expandable-row state (independent toggles, keyed by string).
  final Map<String, bool> _expandedRows = {};

  // Custom animation speed input
  final TextEditingController _customSpeedCtrl = TextEditingController();

  // Auto-move app list expanded
  bool _autoMoveListExpanded = false;
  /// View mode for the auto-move section. true = group apps by
  /// schedule contents (1 row per unique schedule); false = list
  /// every app individually. Defaults to grouped because most users
  /// have ~10 unique schedules across ~100 apps.
  bool _autoMoveGrouped = true;
  /// Which group fingerprints are currently expanded in the
  /// grouped view. Local UI state only; not persisted.
  final Set<String> _autoMoveExpandedGroups = {};
  /// Packages selected for bulk edit (multi-select mode). When
  /// non-empty, a bulk-edit action bar appears at the bottom of
  /// the auto-move section. Cleared on edit-complete or cancel.
  final Set<String> _autoMoveSelected = {};

  SettingsService get _ss => widget.settingsService;
  AppService get _as => widget.appService;
  final NativeService _native = NativeService();

  // ── lifecycle ─────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    // Defer the app-list fetch until after the first frame so the settings
    // page paints immediately instead of stalling on getInstalledApplications().
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _customSpeedCtrl.dispose();
    super.dispose();
  }

  // ── helpers ───────────────────────────────────────────────────

  Future<void> _load() async {
    final apps = await _as.getAllApps();
    if (!mounted) return;
    setState(() {
      _apps = apps;
      _loading = false;
    });
  }

  void _tick() {
    if (!mounted) return;
    if (!_ss.isLockCooldownActive && _ss.hasPendingFloorChanges) {
      _ss.applyPendingFloorChanges(_as.box).then((_) {
        if (mounted) _load();
      });
    }
    if (!_ss.isEmergencyLimitCooldownActive &&
        _ss.pendingEmergencyLimit != null) {
      _ss.applyPendingEmergencyLimit();
    }
    if (!_ss.isAnimCooldownActive && _ss.pendingAnimationType != null) {
      _ss.applyPendingAnimationChange();
    }
    setState(() {});
  }

  String _displayName(AppConfig app) =>
      (app.customName?.isNotEmpty == true) ? app.customName! : app.appName;

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  // ── shortcut app picker ───────────────────────────────────────

  Future<String?> _pickShortcutApp(String currentPackage) async {
    final sorted = List<AppConfig>.from(_apps)
      ..sort((a, b) => a.appName.compareTo(b.appName));
    String query = '';
    return showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInner) {
          final filtered = query.isEmpty
              ? sorted
              : sorted.where((a) => a.appName.toLowerCase().contains(query.toLowerCase())).toList();
          return AlertDialog(
            backgroundColor: const Color(0xFF1A1A1A),
            title: Text(S.of(ctx).selectApp, style: const TextStyle(color: Colors.white)),
            content: SizedBox(
              width: double.maxFinite,
              height: 400,
              child: Column(
                children: [
                  TextField(
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: S.of(ctx).searchHint,
                      hintStyle: const TextStyle(color: Colors.white38),
                      prefixIcon: const Icon(Icons.search, color: Colors.white38),
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (v) => setInner(() => query = v),
                  ),
                  const SizedBox(height: 8),
                  // System default option
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(S.of(ctx).defaultLabel, style: const TextStyle(color: Colors.white)),
                    subtitle: Text(S.of(ctx).useSystemDefault, style: const TextStyle(color: Colors.white38, fontSize: 11)),
                    selected: currentPackage.isEmpty,
                    selectedColor: Colors.tealAccent,
                    onTap: () => Navigator.pop(ctx, ''),
                  ),
                  const Divider(color: Colors.white12),
                  Expanded(
                    child: ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (_, i) {
                        final app = filtered[i];
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(app.appName, style: const TextStyle(color: Colors.white, fontSize: 13)),
                          selected: app.packageName == currentPackage,
                          selectedColor: Colors.tealAccent,
                          onTap: () => Navigator.pop(ctx, app.packageName),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(S.of(ctx).actionCancel, style: const TextStyle(color: Colors.white54)),
              ),
            ],
          );
        },
      ),
    );
  }

  // ── random assignment ─────────────────────────────────────────


  // ── Accordion helpers ──────────────────────────────────────────

  Widget _accordionSection(String key, String title, List<Widget> children) {
    final isOpen = _openSection == key;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          // 開いている章はヘッダ自体にも背景色を付けて、内容ブロックと
          // 視覚的に連続して見えるようにする。
          color: isOpen
              ? Colors.white.withOpacity(0.04)
              : Colors.transparent,
          child: InkWell(
            onTap: () => setState(() {
              _openSection = isOpen ? null : key;
            }),
            child: Container(
              decoration: BoxDecoration(
                border: Border(
                  // 開いている章は左端にティールのバーを出す。
                  left: BorderSide(
                    color: isOpen ? Colors.tealAccent : Colors.transparent,
                    width: 3,
                  ),
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(title,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w500)),
                  Icon(
                    isOpen ? Icons.expand_less : Icons.expand_more,
                    color: Colors.white70,
                    size: 22,
                  ),
                ],
              ),
            ),
          ),
        ),
        if (isOpen)
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.04),
              border: const Border(
                left: BorderSide(color: Colors.tealAccent, width: 3),
              ),
            ),
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        // 章間の区切り線。開いている章の直後はやや強めにして、
        // 「内容の終わり / 次章の始まり」を分かりやすくする。
        Divider(
          color: isOpen ? Colors.white38 : Colors.white12,
          height: 1,
          thickness: isOpen ? 1 : 0.5,
        ),
      ],
    );
  }


  // ── Common color grid picker ───────────────────────────────────
  // Returns the selected Color, or null if cancelled.
  Future<Color?> _showCommonColorPicker(Color? current) =>
      _showSharedColorPicker(context, current: current, ss: _ss);

  Future<String?> _pickAndCropWallpaper(BuildContext context, {File? file}) async {
    String imagePath;
    if (file != null) {
      imagePath = file.path;
    } else {
      final picker = ImagePicker();
      final xfile = await picker.pickImage(source: ImageSource.gallery);
      if (xfile == null || !context.mounted) return null;
      imagePath = xfile.path;
    }
    if (!context.mounted) return null;
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => _WallpaperCropScreen(imagePath: imagePath)),
    );
    return result;
  }


  // ── NEW: Minimalist-style tap-row helpers ──────────────────────────────────────

  Widget _settingRow(String title, String value, VoidCallback onTap, {bool enabled = true}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TextStyle(color: enabled ? Colors.white : Colors.white38, fontSize: 14)),
                    if (value.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(value, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                      ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: enabled ? Colors.white24 : Colors.white12, size: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget get _rowDivider => const Divider(height: 1, color: Colors.white12, indent: 16, endIndent: 16);

  /// Tap-to-expand row used to group related settings under a single label.
  /// [key] uniquely identifies the row's open/closed state across rebuilds.
  /// [summary] is shown right-aligned next to the title (e.g. "3つ有効").
  Widget _expandableRow({
    required String key,
    required String title,
    required String summary,
    required List<Widget> children,
  }) {
    final open = _expandedRows[key] ?? false;
    // Same visual idiom as the top-level accordion sections, scaled down so
    // a sub-group of related rows reads as one block:
    //   * tinted background on both header + content
    //   * a thin teal indicator down the left edge that runs through the
    //     whole open block
    //   * a slightly stronger divider after the open block so the next
    //     sibling row clearly sits outside it
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: open ? Colors.white.withOpacity(0.05) : Colors.transparent,
          child: InkWell(
            onTap: () => setState(() => _expandedRows[key] = !open),
            child: Container(
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(
                    color:
                        open ? Colors.tealAccent : Colors.transparent,
                    width: 2,
                  ),
                ),
              ),
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Expanded(
                    child: Text(title,
                        style: const TextStyle(color: Colors.white, fontSize: 14)),
                  ),
                  if (summary.isNotEmpty)
                    Flexible(
                      child: Text(
                        summary,
                        textAlign: TextAlign.right,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                    ),
                  const SizedBox(width: 6),
                  Icon(open ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                      color: Colors.white38, size: 18),
                ],
              ),
            ),
          ),
        ),
        if (open)
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              border: const Border(
                left: BorderSide(color: Colors.tealAccent, width: 2),
              ),
            ),
            padding: const EdgeInsets.only(bottom: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        // Stronger divider directly after an open block so the next sibling
        // row is clearly outside it. Closed rows keep the very subtle
        // baseline divider that's painted by their parent accordion.
        if (open)
          const Divider(
              color: Colors.white24, height: 1, thickness: 0.6),
      ],
    );
  }

  Future<bool?> _showBoolDialog(String title, bool current) {
    bool selected = current;
    return showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          title: Text(title, style: const TextStyle(color: Colors.white, fontSize: 14)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RadioListTile<bool>(
                title: Text(S.of(ctx).actionEnabled, style: const TextStyle(color: Colors.white, fontSize: 13)),
                value: true, groupValue: selected, activeColor: Colors.white,
                onChanged: (v) { set(() => selected = v!); Navigator.pop(ctx, v); },
              ),
              RadioListTile<bool>(
                title: Text(S.of(ctx).actionDisabled, style: const TextStyle(color: Colors.white, fontSize: 13)),
                value: false, groupValue: selected, activeColor: Colors.white,
                onChanged: (v) { set(() => selected = v!); Navigator.pop(ctx, v); },
              ),
            ],
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(S.of(ctx).actionCancel, style: const TextStyle(color: Colors.white54)))],
        ),
      ),
    );
  }

  Future<T?> _showOptionsDialog<T>(String title, List<(T, String)> options, T current) {
    T selected = current;
    return showDialog<T>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          title: Text(title, style: const TextStyle(color: Colors.white, fontSize: 14)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: options.map((opt) => RadioListTile<T>(
                title: Text(opt.$2, style: const TextStyle(color: Colors.white, fontSize: 13)),
                value: opt.$1, groupValue: selected, activeColor: Colors.white,
                onChanged: (v) { set(() => selected = v as T); Navigator.pop(ctx, v); },
              )).toList(),
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(S.of(ctx).actionCancel, style: const TextStyle(color: Colors.white54)))],
        ),
      ),
    );
  }


  // ── Language section ──────────────────────────────────────────
  // Uses a sentinel 'system' string so we can distinguish "follow system locale"
  // from a Cancel (which the shared options dialog reports as null).
  Widget _buildLanguageSection() {
    final s = S.of(context);
    final current = _ss.languageCode ?? 'system';
    String currentLabel;
    switch (current) {
      case 'ja':
        currentLabel = s.languageJapanese;
        break;
      case 'en':
        currentLabel = s.languageEnglish;
        break;
      default:
        currentLabel = '${s.useSystemDefault} (${Localizations.localeOf(context).languageCode})';
    }
    return _settingRow(
      s.languageSettingTitle,
      currentLabel,
      () async {
        final picked = await _showOptionsDialog<String>(
          s.languageSettingTitle,
          [
            ('system', s.useSystemDefault),
            ('ja', s.languageJapanese),
            ('en', s.languageEnglish),
          ],
          current,
        );
        if (picked == null) return;
        await _ss.setLanguageCode(picked == 'system' ? null : picked);
      },
    );
  }

  // ── build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final wallpaper = _ss.settingsWallpaper;
    final bgColor = _ss.settingsBackground ?? Colors.black;
    // Render settings immediately; the app list (_apps) loads in the background
    // and only the rows that depend on it (e.g. shortcut picker) will be empty
    // for the first frame or two — nothing we need a full-screen spinner for.
    final s = S.of(context);
    final listContent = ListView(
      children: [
        _accordionSection('home', s.sectionHome, _homeSettingRows()),
        _accordionSection('kaiso', s.sectionFloors, _kaisoSettingRows()),
        _accordionSection('gaikkan', s.sectionAppearance, _gaikkanSettingRows()),
        _accordionSection('appmgmt', s.sectionAppManagement, _appMgmtSettingRows()),
        _accordionSection('automove', s.sectionAutoMove, _autoMoveSettingRows()),
        _accordionSection('screentime', s.sectionScreenTime,
            _screenTimeSettingRows()),
        _accordionSection('lock', s.sectionLockSecurity, [_buildLockModeSection()]),
        _accordionSection('backup', s.sectionBackupRestore, [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: _buildBackupRestoreSection(),
          ),
        ]),
        _accordionSection('language', s.languageSection, [_buildLanguageSection()]),
        _accordionSection('ai', 'AI コマンド', [
          _settingRow('AI コマンド', '自然言語でアプリ配置を変更', () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => AiCommandScreen(
                  appService: _as,
                  settingsService: _ss,
                ),
              ),
            );
          }),
          _rowDivider,
          _settingRow('API キー / モデル設定',
              _ss.openaiApiKey == null || _ss.openaiApiKey!.isEmpty
                  ? '未設定'
                  : '${_ss.openaiModel} (キー設定済み)',
              () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => AiSettingsScreen(settingsService: _ss),
              ),
            );
            if (mounted) setState(() {});
          }),
        ]),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
          child: OutlinedButton.icon(
            onPressed: () => _native.openDeviceSettings(),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white70,
              side: const BorderSide(color: Colors.white24),
            ),
            icon: const Icon(Icons.settings, size: 18),
            label:
                Text(s.openDeviceSettings, style: const TextStyle(fontSize: 13)),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );

    return Scaffold(
      backgroundColor: wallpaper != null ? Colors.transparent : bgColor,
      appBar: AppBar(
        backgroundColor: Colors.black.withOpacity(0.7),
        title: Text(s.settingsTitle, style: const TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: Colors.black.withOpacity(0.2)),
        ),
      ),
      extendBodyBehindAppBar: wallpaper != null,
      body: wallpaper != null && wallpaper.isNotEmpty
          ? Stack(
              fit: StackFit.expand,
              children: [
                Image.file(
                  File(wallpaper),
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => ColoredBox(color: bgColor),
                ),
                ColoredBox(color: Colors.black.withOpacity(_ss.settingsOverlayOpacity)),
                listContent,
              ],
            )
          : listContent,
    );
  }


  Future<void> _showOverlayOpacitySlider(
      String title, double initialValue, Future<void> Function(double) onSave) async {
    double opacity = initialValue;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInner) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          title: Text(title, style: const TextStyle(color: Colors.white, fontSize: 14)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${(opacity * 100).round()}%', style: const TextStyle(color: Colors.white70, fontSize: 13)),
              Slider(
                value: opacity, min: 0, max: 1, divisions: 20,
                activeColor: Colors.white, inactiveColor: Colors.white24,
                onChanged: (v) => setInner(() => opacity = v),
              ),
              Text(S.of(ctx).opacityScaleHint, style: const TextStyle(color: Colors.white38, fontSize: 11)),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(S.of(ctx).actionCancel, style: const TextStyle(color: Colors.white54))),
            TextButton(
              onPressed: () async {
                await onSave(opacity);
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: Text(S.of(ctx).actionApply, style: const TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showHomeBackgroundDialog() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: Text(S.of(ctx).homeBackground, style: const TextStyle(color: Colors.white, fontSize: 14)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.palette, color: Colors.white54),
              title: Text(S.of(ctx).selectColor, style: const TextStyle(color: Colors.white, fontSize: 13)),
              onTap: () => Navigator.pop(ctx, 'color'),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.image, color: Colors.white54),
              title: Text(S.of(ctx).selectWallpaper, style: const TextStyle(color: Colors.white, fontSize: 13)),
              onTap: () => Navigator.pop(ctx, 'wallpaper'),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.auto_awesome, color: Colors.white54),
              title: Text(S.of(ctx).defaultWallpaper, style: const TextStyle(color: Colors.white, fontSize: 13)),
              onTap: () => Navigator.pop(ctx, 'default_wallpaper'),
            ),
            if (_ss.homeWallpaper != null) ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.opacity, color: Colors.white54),
                title: Text(S.of(ctx).changeWallpaperOpacity, style: const TextStyle(color: Colors.white, fontSize: 13)),
                onTap: () => Navigator.pop(ctx, 'opacity'),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.delete, color: Colors.redAccent),
                title: Text(S.of(ctx).deleteWallpaper, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
                onTap: () => Navigator.pop(ctx, 'delete_wallpaper'),
              ),
            ],
          ],
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(S.of(ctx).actionCancel, style: const TextStyle(color: Colors.white54)))],
      ),
    );
    if (!mounted) return;
    if (choice == 'color') {
      final c = await _showCommonColorPicker(_ss.homeBackground ?? Colors.black);
      if (!mounted) return;
      if (c != null) { await _ss.setHomeBackground(c); if (mounted) setState(() {}); }
    } else if (choice == 'wallpaper') {
      final path = await _pickAndCropWallpaper(context);
      if (!mounted) return;
      if (path != null) {
        await _ss.setHomeBackground(null);
        await _ss.setHomeWallpaper(path);
        if (mounted) setState(() {});
      }
    } else if (choice == 'default_wallpaper') {
      await _showDefaultWallpaperPicker(context, (path) async {
        await _ss.setHomeBackground(null);
        await _ss.setHomeWallpaper(path);
        if (mounted) setState(() {});
      });
    } else if (choice == 'opacity') {
      await _showOverlayOpacitySlider(
        S.of(context).wallpaperOpacityHome,
        _ss.homeOverlayOpacity,
        (v) => _ss.setHomeOverlayOpacity(v),
      );
      if (mounted) setState(() {});
    } else if (choice == 'delete_wallpaper') {
      await _ss.setHomeWallpaper(null);
      if (mounted) setState(() {});
    }
  }

  Future<void> _showSettingsBgDialog() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: Text(S.of(ctx).settingsBackground, style: const TextStyle(color: Colors.white, fontSize: 14)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.palette, color: Colors.white54),
              title: Text(S.of(ctx).selectColor, style: const TextStyle(color: Colors.white, fontSize: 13)),
              onTap: () => Navigator.pop(ctx, 'color'),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.image, color: Colors.white54),
              title: Text(S.of(ctx).selectWallpaper, style: const TextStyle(color: Colors.white, fontSize: 13)),
              onTap: () => Navigator.pop(ctx, 'wallpaper'),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.auto_awesome, color: Colors.white54),
              title: Text(S.of(ctx).defaultWallpaper, style: const TextStyle(color: Colors.white, fontSize: 13)),
              onTap: () => Navigator.pop(ctx, 'default_wallpaper'),
            ),
            if (_ss.settingsWallpaper != null) ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.opacity, color: Colors.white54),
                title: Text(S.of(ctx).changeWallpaperOpacity, style: const TextStyle(color: Colors.white, fontSize: 13)),
                onTap: () => Navigator.pop(ctx, 'opacity'),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.delete, color: Colors.redAccent),
                title: Text(S.of(ctx).deleteWallpaper, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
                onTap: () => Navigator.pop(ctx, 'delete_wallpaper'),
              ),
            ],
          ],
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(S.of(ctx).actionCancel, style: const TextStyle(color: Colors.white54)))],
      ),
    );
    if (choice == 'color') {
      final c = await _showCommonColorPicker(_ss.settingsBackground ?? Colors.black);
      if (c != null) { await _ss.setSettingsBackground(c); setState(() {}); }
    } else if (choice == 'wallpaper') {
      final path = await _pickAndCropWallpaper(context);
      if (path != null) {
        await _ss.setSettingsBackground(null);
        await _ss.setSettingsWallpaper(path);
        setState(() {});
      }
    } else if (choice == 'default_wallpaper') {
      await _showDefaultWallpaperPicker(context, (path) async {
        await _ss.setSettingsBackground(null);
        await _ss.setSettingsWallpaper(path);
        setState(() {});
      });
    } else if (choice == 'opacity') {
      await _showOverlayOpacitySlider(
        S.of(context).wallpaperOpacitySettings,
        _ss.settingsOverlayOpacity,
        (v) => _ss.setSettingsOverlayOpacity(v),
      );
      setState(() {});
    } else if (choice == 'delete_wallpaper') {
      await _ss.setSettingsWallpaper(null); setState(() {});
    }
  }

  // ── Default Wallpaper Generator (Feature 5) ──────────────────────────────

  Future<File> _generateWallpaper(String preset, Size size) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final w = size.width, h = size.height;
    switch (preset) {
      case 'black_gradient':
        final paint = Paint()..shader = const LinearGradient(
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
          colors: [Color(0xFF000000), Color(0xFF1A1A1A)],
        ).createShader(Rect.fromLTWH(0, 0, w, h));
        canvas.drawRect(Rect.fromLTWH(0, 0, w, h), paint);
        break;
      case 'night_sky':
        canvas.drawRect(Rect.fromLTWH(0, 0, w, h), Paint()..color = const Color(0xFF020818));
        final random = math.Random(42);
        final starPaint = Paint()..color = Colors.white;
        for (int i = 0; i < 150; i++) {
          final r = random.nextDouble() * 1.5 + 0.5;
          canvas.drawCircle(Offset(random.nextDouble() * w, random.nextDouble() * h * 0.8), r, starPaint);
        }
        break;
      case 'dark_forest':
        final paint = Paint()..shader = const LinearGradient(
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
          colors: [Color(0xFF050F08), Color(0xFF0A2010)],
        ).createShader(Rect.fromLTWH(0, 0, w, h));
        canvas.drawRect(Rect.fromLTWH(0, 0, w, h), paint);
        break;
      case 'geometric':
        canvas.drawRect(Rect.fromLTWH(0, 0, w, h), Paint()..color = const Color(0xFF0D0D0D));
        final linePaint = Paint()..color = Colors.white.withOpacity(0.06)..strokeWidth = 1;
        for (double x = 0; x < w; x += 40) canvas.drawLine(Offset(x, 0), Offset(x, h), linePaint);
        for (double y = 0; y < h; y += 40) canvas.drawLine(Offset(0, y), Offset(w, y), linePaint);
        break;
      case 'mountain':
        final paint = Paint()..shader = const LinearGradient(
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
          colors: [Color(0xFF050510), Color(0xFF101030)],
        ).createShader(Rect.fromLTWH(0, 0, w, h));
        canvas.drawRect(Rect.fromLTWH(0, 0, w, h), paint);
        final mtn = Path()
          ..moveTo(0, h * 0.7)
          ..lineTo(w * 0.2, h * 0.4)
          ..lineTo(w * 0.4, h * 0.55)
          ..lineTo(w * 0.6, h * 0.35)
          ..lineTo(w * 0.8, h * 0.5)
          ..lineTo(w, h * 0.45)
          ..lineTo(w, h)
          ..lineTo(0, h)
          ..close();
        canvas.drawPath(mtn, Paint()..color = const Color(0xFF1A1A2E));
        break;
      case 'navy_glow':
        final paint = Paint()..shader = const RadialGradient(
          center: Alignment.center,
          colors: [Color(0xFF0A2050), Color(0xFF000510)],
        ).createShader(Rect.fromLTWH(0, 0, w, h));
        canvas.drawRect(Rect.fromLTWH(0, 0, w, h), paint);
        break;
    }
    final pic = recorder.endRecording();
    final img = await pic.toImage(w.round(), h.round());
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/wallpaper_$preset.png');
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    return file;
  }

  Future<void> _showDefaultWallpaperPicker(BuildContext ctx, Future<void> Function(String path) onSelected) async {
    final s = S.of(ctx);
    final presets = [
      ('black_gradient', s.presetBlackGradient),
      ('night_sky', s.presetNightSky),
      ('dark_forest', s.presetDarkForest),
      ('geometric', s.presetGeometric),
      ('mountain', s.presetMountain),
      ('navy_glow', s.presetNavyGlow),
    ];
    final chosen = await showDialog<String>(
      context: ctx,
      builder: (dCtx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: Text(S.of(dCtx).defaultWallpaper, style: const TextStyle(color: Colors.white, fontSize: 14)),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Online gallery button
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.cloud_download, color: Colors.tealAccent),
                title: Text(S.of(dCtx).onlineWallpaperGallery, style: const TextStyle(color: Colors.tealAccent, fontSize: 13)),
                onTap: () => Navigator.pop(dCtx, '_online'),
              ),
              const Divider(color: Colors.white12),
              // Built-in presets
              Flexible(
                child: GridView.builder(
                  shrinkWrap: true,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2, mainAxisSpacing: 8, crossAxisSpacing: 8, childAspectRatio: 0.75,
                  ),
                  itemCount: presets.length,
                  itemBuilder: (_, i) {
                    return GestureDetector(
                      onTap: () => Navigator.pop(dCtx, presets[i].$1),
                      child: Column(
                        children: [
                          Expanded(
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: Colors.white24),
                                gradient: _presetGradient(presets[i].$1),
                              ),
                              child: const SizedBox.expand(),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(presets[i].$2, style: const TextStyle(color: Colors.white70, fontSize: 10)),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(dCtx), child: Text(S.of(dCtx).actionCancel, style: const TextStyle(color: Colors.white54)))],
      ),
    );
    if (chosen == null || !mounted) return;
    if (chosen == '_online') {
      final path = await Navigator.push<String>(
        context,
        MaterialPageRoute(builder: (_) => const _UnsplashGalleryScreen()),
      );
      if (path != null && mounted) {
        final croppedPath = await _pickAndCropWallpaper(context, file: File(path));
        if (croppedPath != null) await onSelected(croppedPath);
      }
      return;
    }
    final size = MediaQuery.of(context).size;
    final file = await _generateWallpaper(chosen, Size(size.width * 2, size.height * 2));
    final croppedPath = await _pickAndCropWallpaper(context, file: file);
    if (croppedPath != null) await onSelected(croppedPath);
  }

  Gradient _presetGradient(String preset) {
    switch (preset) {
      case 'black_gradient':
        return const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [Color(0xFF000000), Color(0xFF1A1A1A)]);
      case 'night_sky':
        return const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [Color(0xFF020818), Color(0xFF050A20)]);
      case 'dark_forest':
        return const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [Color(0xFF050F08), Color(0xFF0A2010)]);
      case 'geometric':
        return const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [Color(0xFF0D0D0D), Color(0xFF1A1A1A)]);
      case 'mountain':
        return const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [Color(0xFF050510), Color(0xFF101030)]);
      case 'navy_glow':
        return const RadialGradient(center: Alignment.center,
            colors: [Color(0xFF0A2050), Color(0xFF000510)]);
      default:
        return const LinearGradient(colors: [Colors.black, Color(0xFF1A1A1A)]);
    }
  }


}

// ── Unsplash Online Wallpaper Gallery ────────────────────────────────────────

class _UnsplashGalleryScreen extends StatefulWidget {
  const _UnsplashGalleryScreen();
  @override
  State<_UnsplashGalleryScreen> createState() => _UnsplashGalleryScreenState();
}

class _UnsplashGalleryScreenState extends State<_UnsplashGalleryScreen> {
  static const _categories = [
    ('abstract', 'Abstract'),
    ('nature', 'Nature'),
    ('dark', 'Dark'),
    ('gradient', 'Gradient'),
    ('minimal', 'Minimal'),
    ('city', 'City'),
    ('space', 'Space'),
    ('texture', 'Texture'),
    ('ocean', 'Ocean'),
    ('mountain', 'Mountain'),
  ];

  String? _selectedCategory;
  List<Map<String, dynamic>> _photos = [];
  bool _loading = false;
  String? _error;

  Future<void> _loadPhotos(String query) async {
    setState(() { _loading = true; _error = null; _photos = []; });
    try {
      final key = SettingsService.unsplashAccessKey;
      final url = Uri.parse(
          'https://api.unsplash.com/search/photos?query=$query+wallpaper&per_page=24&orientation=portrait');
      final resp = await http.get(url, headers: {'Authorization': 'Client-ID $key'})
          .timeout(const Duration(seconds: 12));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final results = (data['results'] as List?) ?? [];
        setState(() {
          _photos = results.map((e) => e as Map<String, dynamic>).toList();
          _loading = false;
        });
      } else {
        setState(() { _error = '${S.of(context).apiError} (${resp.statusCode})'; _loading = false; });
      }
    } catch (e) {
      setState(() { _error = '${S.of(context).communicationError}: $e'; _loading = false; });
    }
  }

  Future<void> _downloadAndReturn(Map<String, dynamic> photo) async {
    try {
      setState(() => _loading = true);
      final urls = photo['urls'] as Map<String, dynamic>? ?? {};
      final fullUrl = urls['full'] as String? ?? urls['regular'] as String? ?? '';
      if (fullUrl.isEmpty) {
        setState(() { _error = S.of(context).urlNotFound; _loading = false; });
        return;
      }
      final resp = await http.get(Uri.parse(fullUrl))
          .timeout(const Duration(seconds: 30));
      if (resp.statusCode == 200) {
        final dir = await getApplicationDocumentsDirectory();
        final path = '${dir.path}/unsplash_${DateTime.now().millisecondsSinceEpoch}.jpg';
        await File(path).writeAsBytes(resp.bodyBytes);
        if (mounted) Navigator.pop(context, path);
      } else {
        setState(() { _error = '${S.of(context).downloadError} (${resp.statusCode})'; _loading = false; });
      }
    } catch (e) {
      setState(() { _error = '${S.of(context).downloadError}: $e'; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0D0D),
        foregroundColor: Colors.white,
        title: Text(_selectedCategory != null
            ? _categories.firstWhere((c) => c.$1 == _selectedCategory).$2
            : S.of(context).onlineWallpaperGallery,
            style: const TextStyle(color: Colors.white, fontSize: 16)),
        leading: _selectedCategory != null
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() { _selectedCategory = null; _photos = []; }),
              )
            : null,
      ),
      body: _selectedCategory == null
          ? _buildCategoryGrid()
          : _buildPhotoGrid(),
    );
  }

  Widget _buildCategoryGrid() {
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2, mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 1.4,
      ),
      itemCount: _categories.length,
      itemBuilder: (_, i) {
        final cat = _categories[i];
        return GestureDetector(
          onTap: () {
            setState(() => _selectedCategory = cat.$1);
            _loadPhotos(cat.$1);
          },
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white12),
            ),
            child: Center(
              child: Text(cat.$2,
                  style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500)),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPhotoGrid() {
    if (_loading && _photos.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }
    if (_error != null) {
      return Center(child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
      ));
    }
    if (_photos.isEmpty) {
      return Center(child: Text(S.of(context).noPhotosFound, style: const TextStyle(color: Colors.white54)));
    }
    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2, mainAxisSpacing: 6, crossAxisSpacing: 6, childAspectRatio: 0.6,
      ),
      itemCount: _photos.length,
      itemBuilder: (_, i) {
        final photo = _photos[i];
        final urls = photo['urls'] as Map<String, dynamic>? ?? {};
        final thumb = urls['small'] as String? ?? '';
        return GestureDetector(
          onTap: _loading ? null : () => _downloadAndReturn(photo),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: thumb.isNotEmpty
                ? Image.network(thumb, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(color: Colors.white12))
                : Container(color: Colors.white12),
          ),
        );
      },
    );
  }
}
