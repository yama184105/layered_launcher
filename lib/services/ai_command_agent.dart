import 'ai_tools.dart';
import 'openai_client.dart';

/// Runs the chat → tool_use → tool_result loop for a single user
/// command. Stops when the model emits a final assistant message
/// with no further tool calls, or when [maxRounds] is hit (safety
/// net so a misbehaving model can't spin forever).
class AiCommandAgent {
  final OpenAIClient client;
  final AiTools tools;
  final int maxRounds;

  AiCommandAgent({
    required this.client,
    required this.tools,
    this.maxRounds = 8,
  });

  /// Runs one full conversation for [userMessage]. Returns the
  /// transcript including each round's tool calls and results so
  /// the UI can render an audit trail of what the AI did.
  Future<AiCommandResult> run(String userMessage) async {
    final messages = <Map<String, dynamic>>[
      {
        'role': 'system',
        'content': _systemPrompt(),
      },
      {
        'role': 'user',
        'content': userMessage,
      },
    ];

    final transcript = <AiTranscriptEntry>[];

    for (var round = 0; round < maxRounds; round++) {
      final asst = await client.chat(
        messages: messages,
        tools: AiTools.definitions,
      );

      if (asst.content != null && asst.content!.isNotEmpty) {
        transcript.add(AiTranscriptEntry.assistant(asst.content!));
      }

      if (asst.toolCalls.isEmpty) {
        // Model finished — final text reply is in asst.content.
        return AiCommandResult(
          finalMessage: asst.content ?? '',
          transcript: transcript,
        );
      }

      // Append the assistant's tool_call message so the next round
      // can refer back to it. Required by OpenAI's contract.
      messages.add(asst.toJson());

      for (final call in asst.toolCalls) {
        final result = await tools.dispatch(call.name, call.arguments);
        transcript.add(AiTranscriptEntry.toolCall(
          name: call.name,
          arguments: call.arguments,
          result: result,
        ));
        messages.add({
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
