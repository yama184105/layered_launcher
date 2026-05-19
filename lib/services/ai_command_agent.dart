import 'ai_tools.dart';
import 'openai_client.dart';

/// Runs the chat → tool_use → tool_result loop. Stateful: keeps
/// the full message history across calls to [run] so the AI
/// remembers prior turns ("Chrome の位置は？" → "一階に移動させて"
/// stays grounded in Chrome). Stops a single round when the model
/// emits a final assistant message with no further tool calls, or
/// when [maxRounds] is hit (safety net so a misbehaving model
/// can't spin forever).
class AiCommandAgent {
  final OpenAIClient client;
  final AiTools tools;
  final int maxRounds;

  /// Full conversation history. system prompt is the first entry;
  /// every user message + assistant reply + tool_call/tool_result
  /// pair is appended. Passed to OpenAI on every round so the
  /// model has the prior context.
  final List<Map<String, dynamic>> _messages = [];

  AiCommandAgent({
    required this.client,
    required this.tools,
    this.maxRounds = 8,
  }) {
    _messages.add({
      'role': 'system',
      'content': _systemPrompt(),
    });
  }

  /// Number of user turns recorded so far. UI uses this to detect
  /// fresh agents vs continuing ones.
  int get userTurnCount =>
      _messages.where((m) => m['role'] == 'user').length;

  /// Wipes conversation history back to just the system prompt.
  /// Useful when the user wants to start a new topic without
  /// dragging in unrelated prior context.
  void resetHistory() {
    _messages
      ..clear()
      ..add({
        'role': 'system',
        'content': _systemPrompt(),
      });
  }

  /// Runs one full turn for [userMessage]. Returns the transcript
  /// of THIS turn's tool calls and final reply for the UI to render.
  /// Earlier turns stay in [_messages] so the model sees them.
  Future<AiCommandResult> run(String userMessage) async {
    _messages.add({
      'role': 'user',
      'content': userMessage,
    });

    final transcript = <AiTranscriptEntry>[];

    for (var round = 0; round < maxRounds; round++) {
      final asst = await client.chat(
        messages: _messages,
        tools: AiTools.definitions,
      );

      if (asst.content != null && asst.content!.isNotEmpty) {
        transcript.add(AiTranscriptEntry.assistant(asst.content!));
      }

      // Always append the assistant reply (with any tool_calls) to
      // the history so subsequent rounds and turns can reference it.
      _messages.add(asst.toJson());

      if (asst.toolCalls.isEmpty) {
        // Model finished this turn.
        return AiCommandResult(
          finalMessage: asst.content ?? '',
          transcript: transcript,
        );
      }

      for (final call in asst.toolCalls) {
        final result = await tools.dispatch(call.name, call.arguments);
        transcript.add(AiTranscriptEntry.toolCall(
          name: call.name,
          arguments: call.arguments,
          result: result,
        ));
        _messages.add({
          'role': 'tool',
          'tool_call_id': call.id,
          'content': encodeToolResult(result),
        });
      }
    }

    return AiCommandResult(
      finalMessage: '(処理が ${maxRounds} 回繰り返されたため打ち切りました)',
      transcript: transcript,
    );
  }

  String _systemPrompt() {
    final now = DateTime.now();
    final today = '${now.year}-${_pad(now.month)}-${_pad(now.day)}';
    final time = '${_pad(now.hour)}:${_pad(now.minute)}';
    return '''
あなたは Layered Launcher (Android ホームランチャー) のコマンド代行アシスタント。
ユーザーの自然言語の指示を解釈し、提供されたツールを使って設定を変更する。

【動作指針】
- ユーザーの命令はほぼ常にアプリ配置や通知の調整。曖昧でなければ即実行する。
- アプリを操作する前に必ず search_app で package を解決すること。表示名から推測しない。
- search_app の結果が複数あって特定できないときは、ユーザーに聞き返す。
- 「今日だけ」「明日まで」「N 日間」のような期間指示は set_temporary_floor を使う。
- 「ずっと」「常に」「永続」「デフォルト」は set_floor を使う。
- 操作完了後は、何をしたかを 1〜2 文の日本語で簡潔に報告する。
- エラーが返ってきたら、ユーザーに分かる言葉で原因を説明する。

【日時の解釈】
- 「今日」= ${today} 中。expiresAt は ${today}T23:59:59。
- 「明日まで」= 翌日の 23:59:59。
- 「N 日間」= 現在から N×24 時間後。
- 「来週月曜まで」= 次の月曜の 23:59:59。
- 現在日時: ${today} ${time}

【階層の規約】
- 0F = ホーム画面 (時計画面)
- 1F〜10F = 通常の地上階
- -1F〜-10F = 地下階 (アクセスしにくい場所)
- 数字が大きいほど (地上) または小さいほど (地下) アクセスしにくい設計。

【出力スタイル】
- ツール呼び出しが完了したら、最後の assistant メッセージで結果を 1〜2 文で報告する。
- 余計な確認や挨拶はしない。
''';
  }

  String _pad(int n) => n.toString().padLeft(2, '0');
}

class AiCommandResult {
  final String finalMessage;
  final List<AiTranscriptEntry> transcript;

  AiCommandResult({required this.finalMessage, required this.transcript});
}

class AiTranscriptEntry {
  final String kind; // 'assistant' | 'tool'
  final String? text;
  final String? toolName;
  final Map<String, dynamic>? toolArguments;
  final Map<String, dynamic>? toolResult;

  AiTranscriptEntry._({
    required this.kind,
    this.text,
    this.toolName,
    this.toolArguments,
    this.toolResult,
  });

  factory AiTranscriptEntry.assistant(String text) =>
      AiTranscriptEntry._(kind: 'assistant', text: text);

  factory AiTranscriptEntry.toolCall({
    required String name,
    required Map<String, dynamic> arguments,
    required Map<String, dynamic> result,
  }) =>
      AiTranscriptEntry._(
        kind: 'tool',
        toolName: name,
        toolArguments: arguments,
        toolResult: result,
      );
}
