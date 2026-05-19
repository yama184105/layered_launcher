import 'dart:convert';

import '../models/app_config.dart';
import 'app_service.dart';

/// Tool definitions exposed to OpenAI for the AI command bar, plus
/// the dispatcher that maps a tool name + JSON args to an actual
/// Dart side effect on [AppService].
///
/// Scope (Phase 1): the floor-domain tools only. Notification and
/// block tools land in later phases.
///
///   search_app           — find package(s) by display name
///   get_app_state        — read floor/temp override of one app
///   set_floor            — permanent move (writes app.floor)
///   set_temporary_floor  — time-bounded override ("今日だけ", "1週間")
class AiTools {
  final AppService appService;
  AiTools(this.appService);

  /// JSON schema list for the `tools` field of the OpenAI request.
  /// Descriptions are in Japanese so the model sees the same
  /// vocabulary the user is using and picks the right tool more
  /// reliably than with translated English descriptions.
  static List<Map<String, dynamic>> get definitions => [
        {
          'type': 'function',
          'function': {
            'name': 'search_app',
            'description':
                'インストールされているアプリの中から、表示名 (e.g. "LINE", "Chrome") に一致するものを検索し、'
                'packageName のリストを返す。アプリを操作する前に必ず呼び、対象を一意に特定すること。',
            'parameters': {
              'type': 'object',
              'properties': {
                'query': {
                  'type': 'string',
                  'description': '部分一致でマッチさせたいアプリ名',
                },
              },
              'required': ['query'],
            },
          },
        },
        {
          'type': 'function',
          'function': {
            'name': 'get_app_state',
            'description':
                'アプリの現在の階層と、一時オーバーライドがあればその有効期限を返す。'
                'set_temporary_floor を提案する前に呼んで衝突を判断する。',
            'parameters': {
              'type': 'object',
              'properties': {
                'package': {
                  'type': 'string',
                  'description': 'packageName',
                },
              },
              'required': ['package'],
            },
          },
        },
        {
          'type': 'function',
          'function': {
            'name': 'set_floor',
            'description':
                'アプリの階層を恒久的に変更する。'
                '一時オーバーライドが有効中の場合は、その下に隠れている「平常時の階層」を更新するだけで'
                '見た目の表示階層は変わらない (オーバーライド期限切れ後に効く)。',
            'parameters': {
              'type': 'object',
              'properties': {
                'package': {'type': 'string'},
                'floor': {
                  'type': 'integer',
                  'description': '1〜10 が地上階、-1〜-10 が地下階。0 はホーム。',
                },
              },
              'required': ['package', 'floor'],
            },
          },
        },
        {
          'type': 'function',
          'function': {
            'name': 'set_temporary_floor',
            'description':
                '指定期間だけアプリの階層を一時的に変更し、期限が来たら自動的に元の階層に戻す。'
                '「今日だけ 1F」「来週月曜まで 1F」「3 日間だけ」のような期間限定の指示に使う。'
                '既に有効中のオーバーライドがあれば置き換える。'
                'expiresAt は ISO 8601 形式 (例: "2026-05-18T23:59:59")。',
            'parameters': {
              'type': 'object',
              'properties': {
                'package': {'type': 'string'},
                'floor': {'type': 'integer'},
                'expiresAt': {
                  'type': 'string',
                  'description': 'ISO 8601 形式の有効期限 (現地時刻基準で OK)',
                },
              },
              'required': ['package', 'floor', 'expiresAt'],
            },
          },
        },
        {
          'type': 'function',
          'function': {
            'name': 'clear_temporary_floor',
            'description': '一時オーバーライドを即時取り消し、元の階層に戻す。',
            'parameters': {
              'type': 'object',
              'properties': {
                'package': {'type': 'string'},
              },
              'required': ['package'],
            },
          },
        },
      ];

  /// Execute a tool call and return a JSON-serializable result the
  /// model can consume in the next round. Returns `{"error": "..."}`
  /// shapes rather than throwing so the model can recover by trying
  /// a different tool or asking the user.
  Future<Map<String, dynamic>> dispatch(
    String name,
    Map<String, dynamic> args,
  ) async {
    try {
      switch (name) {
        case 'search_app':
          return await _searchApp(args);
        case 'get_app_state':
          return await _getAppState(args);
        case 'set_floor':
          return await _setFloor(args);
        case 'set_temporary_floor':
          return await _setTemporaryFloor(args);
        case 'clear_temporary_floor':
          return await _clearTemporaryFloor(args);
        default:
          return {'error': 'unknown tool: $name'};
      }
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> _searchApp(Map<String, dynamic> args) async {
    final q = (args['query'] as String? ?? '').toLowerCase().trim();
    if (q.isEmpty) return {'matches': []};
    final all = await appService.getAllApps();
    final matches = all
        .where((a) {
          final name = (a.customName?.isNotEmpty == true)
              ? a.customName!
              : a.appName;
          return name.toLowerCase().contains(q) ||
              a.appName.toLowerCase().contains(q) ||
              a.packageName.toLowerCase().contains(q);
        })
        .map((a) => {
              'package': a.packageName,
              'name': (a.customName?.isNotEmpty == true)
                  ? a.customName!
                  : a.appName,
              'floor': a.floor,
            })
        .take(10)
        .toList();
    return {'matches': matches};
  }

  Future<Map<String, dynamic>> _getAppState(Map<String, dynamic> args) async {
    final pkg = args['package'] as String?;
    if (pkg == null) return {'error': 'package required'};
    final app = appService.box.get(pkg);
    if (app == null) return {'error': 'app not found: $pkg'};
    return {
      'package': app.packageName,
      'name': (app.customName?.isNotEmpty == true)
          ? app.customName!
          : app.appName,
      'floor': app.floor,
      'permanentFloor': app.permanentFloor,
      'temporaryFloorExpiry': app.temporaryFloorExpiry?.toIso8601String(),
      'isPinned': app.isPinned,
      'folderName': app.folderName,
    };
  }

  Future<Map<String, dynamic>> _setFloor(Map<String, dynamic> args) async {
    final pkg = args['package'] as String?;
    final floor = args['floor'] as int?;
    if (pkg == null || floor == null) return {'error': 'package, floor required'};
    final app = appService.box.get(pkg);
    if (app == null) return {'error': 'app not found: $pkg'};
    await appService.setPermanentFloor(app, floor);
    return {
      'success': true,
      'package': pkg,
      'floor': app.floor,
      'permanentFloor': app.permanentFloor,
      'note': app.permanentFloor != null
          ? '一時オーバーライド中のため、新しい階層は期限切れ後に有効化されます'
          : null,
    };
  }

  Future<Map<String, dynamic>> _setTemporaryFloor(
    Map<String, dynamic> args,
  ) async {
    final pkg = args['package'] as String?;
    final floor = args['floor'] as int?;
    final expRaw = args['expiresAt'] as String?;
    if (pkg == null || floor == null || expRaw == null) {
      return {'error': 'package, floor, expiresAt required'};
    }
    DateTime? expiry;
    try {
      expiry = DateTime.parse(expRaw);
    } catch (_) {
      return {'error': 'invalid expiresAt (must be ISO 8601): $expRaw'};
    }
    if (expiry.isBefore(DateTime.now())) {
      return {'error': 'expiresAt is in the past: $expRaw'};
    }
    final app = appService.box.get(pkg);
    if (app == null) return {'error': 'app not found: $pkg'};
    await appService.setTemporaryFloor(app, floor: floor, expiry: expiry);
    return {
      'success': true,
      'package': pkg,
      'floor': app.floor,
      'expiresAt': app.temporaryFloorExpiry!.toIso8601String(),
      'restoredFloorAfterExpiry': app.permanentFloor,
    };
  }

  Future<Map<String, dynamic>> _clearTemporaryFloor(
    Map<String, dynamic> args,
  ) async {
    final pkg = args['package'] as String?;
    if (pkg == null) return {'error': 'package required'};
    final app = appService.box.get(pkg);
    if (app == null) return {'error': 'app not found: $pkg'};
    await appService.clearTemporaryFloor(app);
    return {
      'success': true,
      'package': pkg,
      'floor': app.floor,
    };
  }
}

/// Returns the JSON string for a tool result message (role: tool).
String encodeToolResult(Object? result) => jsonEncode(result);
