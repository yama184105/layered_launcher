import 'dart:math';
import 'package:hive/hive.dart';
import '../models/app_config.dart';
import 'native_service.dart';

class AppService {
  static const String _boxName = 'app_configs';
  late Box<AppConfig> _box;

  /// Known system apps that should always be included when installed,
  /// even if they lack a standard launch intent.
  static const _forceIncludeApps = [
    'com.sec.android.app.myfiles', // Samsung My Files
    'com.samsung.android.app.myfiles', // Samsung My Files (alt package)
    'com.android.documentsui', // AOSP Files
    'com.google.android.apps.nbu.files', // Google Files
    'com.mi.android.globalFileexplorer', // Xiaomi File Manager
  ];

  final NativeService _native = NativeService();

  Future<void> init() async {
    _box = await Hive.openBox<AppConfig>(_boxName);
  }

  Box<AppConfig> get box => _box;

  /// ネイティブから返るアプリ情報 {packageName, appName, systemApp} のラベル。
  String _appLabel(Map<String, dynamic> app) {
    final name = (app['appName'] as String? ?? '').trim();
    final pkg = app['packageName'] as String? ?? '';
    return name.isNotEmpty ? name : pkg;
  }

  String _configLabel(AppConfig app) {
    final custom = app.customName?.trim();
    if (custom?.isNotEmpty == true) return custom!;
    final name = app.appName.trim();
    return name.isNotEmpty ? name : app.packageName;
  }

  Future<List<AppConfig>> getAllApps({int defaultFloor = 1}) async {
    final seen = <String>{};
    final List<AppConfig> result = [];

    /// 保存済み設定があればそれを、無ければ既定フロアで新規に作る。
    Future<void> add(Map<String, dynamic> app) async {
      final pkg = app['packageName'] as String? ?? '';
      if (pkg.isEmpty || !seen.add(pkg)) return;
      final existing = _box.get(pkg);
      if (existing != null) {
        if (existing.appName.trim().isEmpty) {
          existing.appName = _appLabel(app);
          await existing.save();
        }
        result.add(existing);
      } else {
        result.add(
          AppConfig(
            packageName: pkg,
            appName: _appLabel(app),
            floor: defaultFloor,
            isEmergency: false,
          ),
        );
      }
    }

    // 1. ランチャーから起動できるアプリ（通常の一覧）
    for (final app in await _native.getInstalledApps()) {
      await add(app);
    }

    // 2. 起動インテントを持たないシステムアプリのうち、明示的に拾うもの
    //    （Galaxy の「マイファイル」など）
    final allInstalled =
        await _native.getInstalledApps(onlyWithLaunchIntent: false);
    final installedPkgs = {
      for (final app in allInstalled) app['packageName'] as String? ?? '',
    };
    for (final app in allInstalled) {
      if (_forceIncludeApps.contains(app['packageName'])) await add(app);
    }

    // 3. 保存済み設定のうち、まだ端末に入っているもの
    for (final key in _box.keys) {
      final pkg = key.toString();
      if (seen.contains(pkg) || !installedPkgs.contains(pkg)) continue;
      seen.add(pkg);
      result.add(_box.get(pkg)!);
    }

    result.sort((a, b) => _configLabel(a).compareTo(_configLabel(b)));
    return result;
  }

  Future<void> saveConfig(AppConfig config) async {
    await _box.put(config.packageName, config);
  }

  Future<void> launchApp(String packageName) async {
    await _native.launchApp(packageName);
  }

  // ── Temporary floor override ────────────────────────────────────────
  // The "今日だけ 1F に" pattern. Saves the original floor in
  // permanentFloor and writes the temporary value to floor; once
  // temporaryFloorExpiry passes, the home screen's _tick restores
  // floor from permanentFloor. UI code reads `app.floor` unchanged.

  /// Apply a temporary floor change to [app] that auto-reverts at
  /// [expiry]. If a temporary override is already active, replaces
  /// it (preserving the underlying permanent floor).
  Future<void> setTemporaryFloor(
    AppConfig app, {
    required int floor,
    required DateTime expiry,
  }) async {
    // Only capture the original floor once; subsequent calls keep
    // the same "original" anchor.
    if (app.permanentFloor == null) {
      app.permanentFloor = app.floor;
    }
    app.floor = floor;
    app.temporaryFloorExpiry = expiry;
    await saveConfig(app);
  }

  /// Cancel any active temporary override on [app], restoring its
  /// original floor immediately. No-op if no override was active.
  Future<void> clearTemporaryFloor(AppConfig app) async {
    if (app.permanentFloor == null) return;
    app.floor = app.permanentFloor!;
    app.permanentFloor = null;
    app.temporaryFloorExpiry = null;
    await saveConfig(app);
  }

  /// Update the underlying permanent floor for an app. If a temporary
  /// override is currently active, [app.floor] stays at the override
  /// value but the new permanent will take effect once it expires.
  Future<void> setPermanentFloor(AppConfig app, int floor) async {
    if (app.permanentFloor != null) {
      // Temp override active — just update the saved baseline.
      app.permanentFloor = floor;
    } else {
      app.floor = floor;
    }
    await saveConfig(app);
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
        ..sort(
          (a, b) => a.appName.toLowerCase().compareTo(b.appName.toLowerCase()),
        );
    }

    return selected
        .map(
          (a) => {
            'packageName': a.packageName,
            'label': (a.customName != null && a.customName!.isNotEmpty)
                ? a.customName!
                : a.appName,
          },
        )
        .toList();
  }

  /// Randomly assigns floors 1–10 to every non-pinned app.
  Future<Map<String, int>> buildRandomFloorMap({List<int>? floors}) async {
    final choices = (floors == null || floors.isEmpty)
        ? List<int>.generate(10, (i) => i + 1)
        : floors;
    final installed = await _native.getInstalledApps();
    final rng = Random();
    final result = <String, int>{};
    for (final app in installed) {
      final pkg = app['packageName'] as String? ?? '';
      if (pkg.isEmpty) continue;
      final cfg = _box.get(pkg);
      if (cfg != null && cfg.isPinned) continue;
      result[pkg] = choices[rng.nextInt(choices.length)];
    }
    return result;
  }

  /// Applies a floor map directly to the box.
  Future<void> applyFloorMap(Map<String, int> floorMap) async {
    final installed = await _native.getInstalledApps();
    for (final app in installed) {
      final pkg = app['packageName'] as String? ?? '';
      final newFloor = floorMap[pkg];
      if (pkg.isEmpty || newFloor == null) continue;
      final cfg = _box.get(pkg) ??
          AppConfig(packageName: pkg, appName: _appLabel(app), floor: 1);
      cfg.floor = newFloor;
      await _box.put(cfg.packageName, cfg);
    }
  }
}
