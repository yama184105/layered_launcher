import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/app_config.dart';

part 'settings/display_settings_part.dart';
part 'settings/block_settings_part.dart';
part 'settings/gesture_settings_part.dart';
part 'settings/emergency_settings_part.dart';
part 'settings/automove_settings_part.dart';

/// Global app settings stored in a Hive dynamic box.
class SettingsService {
  static const String _boxName = 'global_settings';
  // Unsplash API key — replace with your own key
  static const String unsplashAccessKey = 'YOUR_UNSPLASH_ACCESS_KEY';
  late Box<dynamic> _box;

  /// Hook invoked whenever the per-app notification policy changes
  /// (default mode, OFF set, or explicit-allow set). main.dart wires this
  /// to NativeService.setNotifPolicy so the kotlin notification listener
  /// can resolve any package's effective mode without consulting Flutter.
  Future<void> Function(
    String defaultMode,
    Set<String> offPackages,
    Set<String> allowPackages,
  )? onNotifPolicyChanged;

  /// Hook invoked whenever the batch-groups config changes. main.dart wires
  /// this to NativeService.setBatchGroups so AlarmManager schedules and the
  /// notification listener's app-to-group lookup stay in sync.
  Future<void> Function(List<Map<String, dynamic>> groups)? onBatchGroupsChanged;

  /// Hook invoked whenever quick-launcher config (enabled flag,
  /// prominence, or resolved app list) changes. main.dart wires this to
  /// NativeService.setQuickLauncherConfig so the persistent notification
  /// is updated whenever favorites/floor1/etc. shift.
  Future<void> Function(
    bool enabled,
    bool prominent,
    List<Map<String, String>> apps,
  )? onQuickLauncherChanged;

  Future<void> init() async {
    _box = await Hive.openBox<dynamic>(_boxName);
    await migrateBatchGroupsIfNeeded();
  }

  /// Whether the persistent quick-launcher notification is enabled. When
  /// true, main.dart pushes the resolved app list to NativeService on
  /// boot and on every change.
  bool get quickLauncherEnabled =>
      _box.get('quickLauncherEnabled', defaultValue: false) as bool;
  Future<void> setQuickLauncherEnabled(bool v) async {
    await _box.put('quickLauncherEnabled', v);
  }

  /// When true, the quick-launcher notification uses the DEFAULT
  /// importance channel (heads-up on post, more likely to display in
  /// expanded form). When false, uses LOW (quiet, folded in shade).
  bool get quickLauncherProminent =>
      _box.get('quickLauncherProminent', defaultValue: false) as bool;
  Future<void> setQuickLauncherProminent(bool v) async {
    await _box.put('quickLauncherProminent', v);
  }

  /// Which set of apps populates the quick launcher notification.
  /// 'favorites' = isPinned apps; 'floor1' = floor==1 apps;
  /// 'custom' = user-picked list (see quickLauncherCustomApps).
  /// Defaults to 'favorites'.
  String get quickLauncherSource =>
      _box.get('quickLauncherSource', defaultValue: 'favorites') as String;
  Future<void> setQuickLauncherSource(String v) async {
    await _box.put('quickLauncherSource', v);
  }

  /// Package names manually picked by the user for the quick-launcher
  /// notification. Only consulted when quickLauncherSource == 'custom'.
  /// Order is preserved (pick order = notification row order).
  List<String> get quickLauncherCustomApps {
    final raw = _box.get('quickLauncherCustomApps');
    if (raw is List) return raw.cast<String>();
    return const [];
  }

  Future<void> setQuickLauncherCustomApps(List<String> pkgs) async {
    await _box.put('quickLauncherCustomApps', pkgs);
  }

  /// True after the user finishes the first-launch onboarding (permission
  /// grant flow). main.dart shows OnboardingScreen instead of HomeScreen
  /// while this is false so we can request notification listener, usage
  /// stats, device admin, and exact alarm permissions up front rather than
  /// drip-feeding them via in-app banners.
  bool get hasCompletedOnboarding =>
      _box.get('hasCompletedOnboarding', defaultValue: false) as bool;
  Future<void> setOnboardingCompleted(bool v) async {
    await _box.put('hasCompletedOnboarding', v);
  }

  /// App locale code: 'ja' or 'en'. Null = follow system locale.
  String? get languageCode => _box.get('languageCode') as String?;
  Future<void> setLanguageCode(String? code) async {
    if (code == null) {
      await _box.delete('languageCode');
    } else {
      await _box.put('languageCode', code);
    }
    _localeNotifier.value = code == null ? null : Locale(code);
  }

  /// Reactive notifier for locale changes. main.dart rebuilds MaterialApp on
  /// changes so the language switch takes effect immediately without a restart.
  final ValueNotifier<Locale?> _localeNotifier = ValueNotifier<Locale?>(null);
  ValueNotifier<Locale?> get localeNotifier {
    final saved = languageCode;
    if (saved != null && _localeNotifier.value?.languageCode != saved) {
      _localeNotifier.value = Locale(saved);
    }
    return _localeNotifier;
  }
}
