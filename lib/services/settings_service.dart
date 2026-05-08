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

  /// Hook invoked whenever the OFF-mode package set changes. main.dart wires
  /// this to NativeService.setOffPackages so the kotlin notification listener
  /// can stay in sync without SettingsService having to depend on
  /// NativeService directly.
  Future<void> Function(Set<String> offPackages)? onOffPackagesChanged;

  Future<void> init() async {
    _box = await Hive.openBox<dynamic>(_boxName);
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
