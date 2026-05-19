import 'package:flutter/material.dart';

import '../../services/ai_command_agent.dart';
import '../../services/ai_tools.dart';
import '../../services/app_service.dart';
import '../../services/openai_client.dart';
import '../../services/settings_service.dart';

/// Conversational entry point for AI-driven launcher commands.
/// Free-text input → OpenAI tool-use loop → transcript with the
/// tool calls and final reply rendered for audit.
///
/// Phase 1 scope: floor-domain commands only (move, temporary
/// override). Notification / block tools land later.
class AiCommandScreen extends StatefulWidget {
  final AppService appService;
  final SettingsService settingsService;

  const AiCommandScreen({
    super.key,
    required this.appService,
    required this.settingsService,
  });

  @override
  State<AiCommandScreen> createState() => _AiCommandScreenState();
}

class _AiCommandScreenState extends State<AiCommandScreen> {
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  final List<_ConversationItem> _items = [];
  bool _busy = false;

  /// Persistent agent + client for this screen instance so the
  /// OpenAI conversation history (prior user turns, tool results)
  /// is preserved across submissions. Without this, follow-up
  /// commands like "一階に移動させて" lose the context from the
  /// prior "Chrome の位置は？" turn.
  OpenAIClient? _client;
  AiCommandAgent? _agent;
  String? _agentApiKey;
  String? _agentModel;

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    _client?.close();
    super.dispose();
  }

  /// Lazily creates the OpenAI client + agent. Rebuilds if the
  /// API key or model changed since last use (so the user can
  /// switch models mid-session without restarting the screen).
  void _ensureAgent() {
    final apiKey = widget.settingsService.openaiApiKey;
    final model = widget.settingsService.openaiModel;
    if (_agent != null &&
        _agentApiKey == apiKey &&
        _agentModel == model) {
      return;
    }
    _client?.close();
    _client = OpenAIClient(apiKey: apiKey!, model: model);
    _agent = AiCommandAgent(
      client: _client!,
      tools: AiTools(widget.appService),
    );
    _agentApiKey = apiKey;
    _agentModel = model;
  }

  void _resetConversation() {
    _agent?.resetHistory();
    setState(() => _items.clear());
  }

  Future<void> _submit() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty || _busy) return;

    final apiKey = widget.settingsService.openaiApiKey;
    if (apiKey == null || apiKey.isEmpty) {
      _showApiKeyMissing();
      return;
    }

    setState(() {
      _items.add(_ConversationItem.user(text));
      _busy = true;
    });
    _inputCtrl.clear();
    _scrollToEnd();

    _ensureAgent();

    try {
      final result = await _agent!.run(text);
      if (!mounted) return;
      setState(() {
        for (final entry in result.transcript) {
          if (entry.kind == 'tool') {
            _items.add(_ConversationItem.tool(
              name: entry.toolName!,
              arguments: entry.toolArguments!,
              result: entry.toolResult!,
            ));
          }
        }
        if (result.finalMessage.isNotEmpty) {
          _items.add(_ConversationItem.assistant(result.finalMessage));
        }
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _items.add(_ConversationItem.error(e.toString()));
        _busy = false;
      });
    } finally {
      _scrollToEnd();
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollCtrl.hasClients) return;
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  void _showApiKeyMissing() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('OpenAI API キーが未設定です。設定 > AI コマンド から登録してください。'),
        duration: Duration(seconds: 4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('AI コマンド', style: TextStyle(fontSize: 16)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, size: 18),
            tooltip: '会話をリセット',
            onPressed: _items.isEmpty ? null : _resetConversation,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _items.isEmpty
                ? _buildHint()
                : ListView.builder(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    itemCount: _items.length,
                    itemBuilder: (_, i) => _buildBubble(_items[i]),
                  ),
          ),
          if (_busy)
            const LinearProgressIndicator(
              color: Colors.tealAccent,
              backgroundColor: Colors.white12,
              minHeight: 2,
            ),
          _buildInputBar(),
        ],
      ),
    );
  }

  Widget _buildHint() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.auto_awesome, color: Colors.white24, size: 48),
            const SizedBox(height: 16),
            const Text(
              '自然言語でランチャーを操作',
              style: TextStyle(color: Colors.white70, fontSize: 16),
            ),
            const SizedBox(height: 16),
            ..._examples.map(
              (e) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  '・$e',
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static const _examples = [
    'LINE を 1F に移動',
    '今日だけ Chrome を 5F に',
    '1 週間 YouTube を 8F に置いといて',
    'Gmail と Slack を 2F に',
  ];

  Widget _buildBubble(_ConversationItem item) {
    switch (item.kind) {
      case 'user':
        return Align(
          alignment: Alignment.centerRight,
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            constraints: const BoxConstraints(maxWidth: 320),
            decoration: BoxDecoration(
              color: Colors.tealAccent.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              item.text!,
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
          ),
        );
      case 'assistant':
        return Padding(
          padding: const EdgeInsets.only(bottom: 8, right: 32),
          child: Text(
            item.text!,
            style: const TextStyle(color: Colors.white, fontSize: 14),
          ),
        );
      case 'tool':
        return Padding(
          padding: const EdgeInsets.only(bottom: 8, left: 8, right: 32),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.04),
              border: Border.all(color: Colors.white12),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '🛠 ${item.toolName}',
                  style: const TextStyle(
                      color: Colors.tealAccent, fontSize: 11),
                ),
                const SizedBox(height: 2),
                Text(
                  _previewMap(item.toolArguments!),
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
                if (item.toolResult!.containsKey('error'))
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      '❌ ${item.toolResult!['error']}',
                      style: const TextStyle(
                          color: Colors.redAccent, fontSize: 11),
                    ),
                  )
                else if (item.toolResult!['success'] == true)
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Text(
                      '✓ 完了',
                      style: TextStyle(
                          color: Colors.tealAccent, fontSize: 11),
                    ),
                  ),
              ],
            ),
          ),
        );
      case 'error':
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.redAccent.withOpacity(0.1),
              border: Border.all(color: Colors.redAccent.withOpacity(0.3)),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              item.text!,
              style:
                  const TextStyle(color: Colors.redAccent, fontSize: 12),
            ),
          ),
        );
    }
    return const SizedBox.shrink();
  }

  String _previewMap(Map<String, dynamic> m) {
    final parts = <String>[];
    m.forEach((k, v) => parts.add('$k: $v'));
    return parts.join(', ');
  }

  Widget _buildInputBar() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _inputCtrl,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                enabled: !_busy,
                onSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  hintText: '例: 今日だけ LINE を 1F に',
                  hintStyle:
                      const TextStyle(color: Colors.white38, fontSize: 13),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.06),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.send, color: Colors.tealAccent),
              onPressed: _busy ? null : _submit,
            ),
          ],
        ),
      ),
    );
  }
}

class _ConversationItem {
  final String kind; // user / assistant / tool / error
  final String? text;
  final String? toolName;
  final Map<String, dynamic>? toolArguments;
  final Map<String, dynamic>? toolResult;

  _ConversationItem._({
    required this.kind,
    this.text,
    this.toolName,
    this.toolArguments,
    this.toolResult,
  });

  factory _ConversationItem.user(String text) =>
      _ConversationItem._(kind: 'user', text: text);
  factory _ConversationItem.assistant(String text) =>
      _ConversationItem._(kind: 'assistant', text: text);
  factory _ConversationItem.error(String text) =>
      _ConversationItem._(kind: 'error', text: text);
  factory _ConversationItem.tool({
    required String name,
    required Map<String, dynamic> arguments,
    required Map<String, dynamic> result,
  }) =>
      _ConversationItem._(
        kind: 'tool',
        toolName: name,
        toolArguments: arguments,
        toolResult: result,
      );
}
