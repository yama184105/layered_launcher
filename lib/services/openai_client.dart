import 'dart:convert';
import 'package:http/http.dart' as http;

/// Thin OpenAI Chat Completions client tailored for tool use.
///
/// Why not use a SDK: as of writing, no Dart SDK is officially
/// supported by OpenAI and the third-party ones lag behind tool-use
/// API changes. The chat completions endpoint is stable and the JSON
/// shape is small, so a direct http call is the lowest-friction
/// option for this app.
class OpenAIClient {
  static const _endpoint = 'https://api.openai.com/v1/chat/completions';

  final String apiKey;
  final String model;
  final http.Client _http;

  OpenAIClient({
    required this.apiKey,
    required this.model,
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  /// One round-trip to the chat completions endpoint. Pass [messages]
  /// (system + user + tool messages accumulated so far) and the
  /// [tools] definitions; returns the assistant message including
  /// any `tool_calls`. Caller is responsible for executing the calls
  /// and feeding back as `role: tool` messages for the next round.
  ///
  /// Throws [OpenAIException] on non-2xx responses; surfacing the
  /// raw API error is more useful than a generic message because
  /// most failures are auth/key/quota issues the user must fix.
  Future<OpenAIAssistantMessage> chat({
    required List<Map<String, dynamic>> messages,
    required List<Map<String, dynamic>> tools,
    double? temperature,
  }) async {
    final body = <String, dynamic>{
      'model': model,
      'messages': messages,
      if (tools.isNotEmpty) 'tools': tools,
      if (tools.isNotEmpty) 'tool_choice': 'auto',
      if (temperature != null) 'temperature': temperature,
    };

    final resp = await _http.post(
      Uri.parse(_endpoint),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      },
      body: jsonEncode(body),
    );

    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw OpenAIException(
        statusCode: resp.statusCode,
        body: resp.body,
      );
    }

    final json = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    final choices = json['choices'] as List?;
    if (choices == null || choices.isEmpty) {
      throw OpenAIException(
        statusCode: resp.statusCode,
        body: 'no choices returned',
      );
    }
    final msg = (choices.first as Map)['message'] as Map<String, dynamic>;
    return OpenAIAssistantMessage.fromJson(msg);
  }

  void close() => _http.close();
}

/// The `message` field returned by the chat completions endpoint.
class OpenAIAssistantMessage {
  /// Plain-text reply, may be empty when the model is just calling tools.
  final String? content;

  /// Tool calls the model wants the host to execute. Each has an id
  /// (echoed back in the follow-up `role: tool` message), function
  /// name, and JSON-string arguments.
  final List<OpenAIToolCall> toolCalls;

  OpenAIAssistantMessage({
    required this.content,
    required this.toolCalls,
  });

  factory OpenAIAssistantMessage.fromJson(Map<String, dynamic> json) {
    final raw = (json['tool_calls'] as List?) ?? const [];
    return OpenAIAssistantMessage(
      content: json['content'] as String?,
      toolCalls: raw
          .map((e) => OpenAIToolCall.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  /// Convert back to message shape so we can append to the history.
  Map<String, dynamic> toJson() => {
        'role': 'assistant',
        if (content != null) 'content': content,
        if (toolCalls.isNotEmpty)
          'tool_calls': toolCalls.map((c) => c.toJson()).toList(),
      };
}

class OpenAIToolCall {
  final String id;
  final String name;
  final String argumentsJson;

  OpenAIToolCall({
    required this.id,
    required this.name,
    required this.argumentsJson,
  });

  factory OpenAIToolCall.fromJson(Map<String, dynamic> json) {
    final fn = json['function'] as Map<String, dynamic>;
    return OpenAIToolCall(
      id: json['id'] as String,
      name: fn['name'] as String,
      argumentsJson: fn['arguments'] as String? ?? '{}',
    );
  }

  /// Decoded arguments. Returns an empty map if the model returned
  /// garbage (which Gpt-5-mini sometimes does on tricky schemas).
  Map<String, dynamic> get arguments {
    try {
      return jsonDecode(argumentsJson) as Map<String, dynamic>;
    } catch (_) {
      return const {};
    }
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': 'function',
        'function': {
          'name': name,
          'arguments': argumentsJson,
        },
      };
}

class OpenAIException implements Exception {
  final int statusCode;
  final String body;
  OpenAIException({required this.statusCode, required this.body});

  @override
  String toString() {
    final hint = switch (statusCode) {
      401 => 'APIキーが無効です。設定 > AI コマンドで正しいキーを登録してください。',
      429 => 'レート制限に達しました。しばらく待ってから試してください。',
      500 || 502 || 503 => 'OpenAI サーバーエラーが発生しました。時間をおいて試してください。',
      _ => null,
    };
    return hint != null
        ? 'OpenAI API エラー $statusCode: $hint'
        : 'OpenAI API エラー $statusCode: $body';
  }
}
