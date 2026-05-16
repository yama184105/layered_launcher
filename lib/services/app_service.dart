import 'dart:math';
import 'package:device_apps/device_apps.dart';
import 'package:hive/hive.dart';
import '../models/app_config.dart';

class AppService {
  static const String _boxName = 'app_configs';
  late Box<AppConfig> _box;

  /// Known system apps that should always be included when installed,
  /// even if they lack a standard launch intent.
  static const _forceIncludeApps = [
    'com.sec.android.app.myfiles',      // Samsung My Files
    'com.samsung.android.app.myfiles',  // Samsung My Files (alt package)
    'com.android.documentsui',           // AOSP Files
    'com.google.android.apps.nbu.files', // Google Files
    'com.mi.android.globalFileexplorer', // Xiaomi File Manager
  ];

  Future<void> init() async {
    _box = await Hive.openBox<AppConfig>(_boxName);
  }

  Box<AppConfig> get box => _box;

  Future<List<AppConfig>> getAllApps({int defaultFloor = 1}) async {
    // 1. Get all apps with launch intent (the normal set)
    final launchable = await DeviceApps.getInstalledApplications(
      includeSystemApps: true,
      onlyAppsWithLaunchIntent: true,
    );
    final seen = <String>{};
    final List<AppConfig> result = [];
    for (final app in launchable) {
      seen.add(app.packageName);
      final existing = _box.get(app.packageName);
      if (existing != null) {
        result.add(existing);
      } else {
        result.add(AppConfig(
          packageName: app.packageName,
          appName: app.appName,
          floor: defaultFloor,
          isEmergency: false,
        ));
      }
    }

    // 2. Get ALL installed apps (including those without launch intent)
    //    to find system apps like Samsung My Files
    final allInstalled = await DeviceApps.getInstalledApplications(
      includeSystemApps: true,
      onlyAppsWithLaunchIntent: false,
    );
    for (final app in allInstalled) {
      if (seen.contains(app.packageName)) continue;
      // Only include if it's in our force-include list
      if (_forceIncludeApps.contains(app.packageName)) {
        seen.add(app.packageName);
        final existing = _box.get(app.packageName);
        if (existing != null) {
          result.add(existing);
        } else {
          result.add(AppConfig(
            packageName: app.packageName,
            appName: app.appName,
            floor: defaultFloor,
            isEmergency: false,
          ));
        }
      }
    }

    // 3. Include any previously saved configs whose apps are still installed
    for (final key in _box.keys) {
      final pkg = key.toString();
      if (seen.contains(pkg)) continue;
      final app = await DeviceApps.getApp(pkg);
      if (app != null) {
        seen.add(pkg);
        result.add(_box.get(pkg)!);
      }
    }

    result.sort((a, b) => a.appName.compareTo(b.appName));
    return result;
  }

  Future<void> saveConfig(AppConfig config) async {
    await _box.put(config.packageName, config);
  }

  Future<void> launchApp(String packageName) async {
    await DeviceApps.openApp(packageName);
  }

  /// Resolves the apps that populate the persistent quick-launcher
  /// notification, given a [source]:
  /// - 'favorites':  isPinned apps (alphabetical)
  /// - 'floor1':     floor==1 apps (alphabetical)
  /// - 'custom':     packages from [customPackages] in their original order
  /// Returns a list of `{packageName, label}` maps.
  Future<List<Map<String, String>>> resolveQuickLauncherApps(
    String source, {
    List<String> customPackages = const [],
  }) async {
    final all = await getAllApps();
    final byPkg = {for (final a in all) a.packageName: a};

    List<AppConfig> selected;
    if (source == 'custom') {
      // Preserve the user-picked order, drop packages that aren't
      // installed anymore.
      selected = [
        for (final pkg in customPackages)
          if (byPkg[pkg] != null) byPkg[pkg]!,
      ];
    } else {
      final filtered = source == 'floor1'
          ? all.where((a) => a.floor == 1)
          : all.where((a) => a.isPinned);
      selected = filtered.toList()
        ..sort((a, b) =>
            a.appName.toLowerCase().compareTo(b.appName.toLowerCase()));
    }

    return selected
        .map((a) => {
              'packageName': a.packageName,
              'label': (a.customName != null && a.customName!.isNotEmpty)
                  ? a.customName!
                  : a.appName,
            })
        .toList();
  }

  /// Randomly assigns floors 1–10 to every non-pinned app.
  Future<Map<String, int>> buildRandomFloorMap() async {
    final installed = await DeviceApps.getInstalledApplications(
      includeSystemApps: true,
      onlyAppsWithLaunchIntent: true,
    );
    final rng = Random();
    final result = <String, int>{};
    for (final app in installed) {
      final cfg = _box.get(app.packageName);
      if (cfg != null && cfg.isPinned) continue;
      result[app.packageName] = rng.nextInt(10) + 1;
    }
    return result;
  }

  /// Applies a floor map directly to the box (used when lock mode is OFF).
  Future<void> applyFloorMap(Map<String, int> floorMap) async {
    final installed = await DeviceApps.getInstalledApplications(
      includeSystemApps: true,
      onlyAppsWithLaunchIntent: true,
    );
    for (final app in installed) {
      final newFloor = floorMap[app.packageName];
      if (newFloor == null) continue;
      final cfg = _box.get(app.packageName) ??
          AppConfig(
              packageName: app.packageName, appName: app.appName, floor: 1);
      cfg.floor = newFloor;
      await _box.put(cfg.packageName, cfg);
    }
  }
}
