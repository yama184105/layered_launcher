import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
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

  Future<void> init() async {
    _box = await Hive.openBox<dynamic>(_boxName);
  }
}
