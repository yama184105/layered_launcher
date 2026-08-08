part of '../settings_service.dart';

/// バックアップ／復元。
///
/// 旧実装は全設定を `toString()` で文字列化して送っていたため、Map や List
/// （スケジュール・ルール類）が復元不能な文字列になっていた。さらにアプリの
/// フロア配置（AppConfig box）が含まれておらず、復元処理も存在しなかった。
///
/// ここでは JSON として往復できる形に直し、設定 box とアプリ配置の両方を
/// 含める。DateTime は `{'__dt': epochMs}` に包んで型を保つ。
const int kBackupFormatVersion = 1;

extension BackupSettings on SettingsService {
  // ── JSON 変換 ─────────────────────────────────────────────────────────────

  Object? _toJsonSafe(Object? value) {
    if (value == null || value is num || value is bool || value is String) {
      return value;
    }
    if (value is DateTime) return {'__dt': value.millisecondsSinceEpoch};
    if (value is List) return value.map(_toJsonSafe).toList();
    if (value is Map) {
      return value.map((k, v) => MapEntry(k.toString(), _toJsonSafe(v)));
    }
    // Hive に入りうる残りの型は素性が分からないので文字列化して捨て値にする
    return value.toString();
  }

  Object? _fromJsonSafe(Object? value) {
    if (value is Map) {
      if (value.length == 1 && value['__dt'] is num) {
        return DateTime.fromMillisecondsSinceEpoch((value['__dt'] as num).toInt());
      }
      return value.map((k, v) => MapEntry(k.toString(), _fromJsonSafe(v)));
    }
    if (value is List) return value.map(_fromJsonSafe).toList();
    return value;
  }

  // ── エクスポート ──────────────────────────────────────────────────────────

  /// 設定 box とアプリ配置をまとめたバックアップ。[jsonEncode] にそのまま
  /// 渡せる形で返す。
  Map<String, dynamic> buildBackup(Box<AppConfig> appBox) {
    final settings = <String, dynamic>{};
    for (final key in _box.keys) {
      settings[key.toString()] = _toJsonSafe(_box.get(key));
    }
    final apps = <Map<String, dynamic>>[
      for (final a in appBox.values)
        {
          'packageName': a.packageName,
          'appName': a.appName,
          'floor': a.floor,
          'isEmergency': a.isEmergency,
          'emergencyUntil': a.emergencyUntil?.millisecondsSinceEpoch,
          'isPinned': a.isPinned,
          'customName': a.customName,
          'folderName': a.folderName,
          'mindfulDelay': a.mindfulDelay,
          'folderPinned': a.folderPinned,
          'folderPosition': a.folderPosition,
          'permanentFloor': a.permanentFloor,
          'temporaryFloorExpiry': a.temporaryFloorExpiry?.millisecondsSinceEpoch,
        },
    ];
    return {
      'version': kBackupFormatVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'settings': settings,
      'apps': apps,
    };
  }

  String buildBackupJson(Box<AppConfig> appBox) =>
      jsonEncode(buildBackup(appBox));

  // ── 復元 ──────────────────────────────────────────────────────────────────

  /// [raw]（バックアップJSON文字列）を取り込む。戻り値は復元したアプリ数。
  /// 形式が違う場合は [FormatException] を投げる。
  Future<int> restoreBackupJson(String raw, Box<AppConfig> appBox) async {
    final decoded = jsonDecode(raw.trim());
    if (decoded is! Map) throw const FormatException('not a backup object');
    final version = (decoded['version'] as num?)?.toInt();
    if (version == null || version > kBackupFormatVersion) {
      throw const FormatException('unsupported backup version');
    }

    final settings = decoded['settings'];
    if (settings is Map) {
      for (final entry in settings.entries) {
        await _box.put(entry.key.toString(), _fromJsonSafe(entry.value));
      }
    }

    int restored = 0;
    final apps = decoded['apps'];
    if (apps is List) {
      for (final raw in apps.whereType<Map>()) {
        final pkg = raw['packageName']?.toString();
        if (pkg == null || pkg.isEmpty) continue;
        DateTime? dt(Object? v) => v is num
            ? DateTime.fromMillisecondsSinceEpoch(v.toInt())
            : null;
        // 端末に入っていないアプリぶんも書いておく。あとでインストール
        // されたときにフロアがそのまま復元される。
        final existing = appBox.get(pkg);
        final cfg = existing ??
            AppConfig(
              packageName: pkg,
              appName: raw['appName']?.toString() ?? pkg,
            );
        cfg.appName = raw['appName']?.toString() ?? cfg.appName;
        cfg.floor = (raw['floor'] as num?)?.toInt() ?? cfg.floor;
        cfg.isEmergency = raw['isEmergency'] as bool? ?? false;
        cfg.emergencyUntil = dt(raw['emergencyUntil']);
        cfg.isPinned = raw['isPinned'] as bool? ?? false;
        cfg.customName = raw['customName']?.toString();
        cfg.folderName = raw['folderName']?.toString();
        cfg.mindfulDelay = raw['mindfulDelay'] as bool? ?? false;
        cfg.folderPinned = raw['folderPinned'] as bool? ?? false;
        cfg.folderPosition =
            raw['folderPosition']?.toString() ?? 'alphabetical';
        cfg.permanentFloor = (raw['permanentFloor'] as num?)?.toInt();
        cfg.temporaryFloorExpiry = dt(raw['temporaryFloorExpiry']);
        await appBox.put(pkg, cfg);
        restored++;
      }
    }
    return restored;
  }
}
