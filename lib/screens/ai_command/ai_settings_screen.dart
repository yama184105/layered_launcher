import 'package:flutter/material.dart';

import '../../services/settings_service.dart';

/// Tiny settings page where the user stashes their OpenAI API key
/// and picks which chat model to drive the AI command bar. Keeping
/// this separate from the main settings tree so we can iterate on
/// the AI surface without touching the existing settings screen.
class AiSettingsScreen extends StatefulWidget {
  final SettingsService settingsService;

  const AiSettingsScreen({super.key, required this.settingsService});

  @override
  State<AiSettingsScreen> createState() => _AiSettingsScreenState();
}

class _AiSettingsScreenState extends State<AiSettingsScreen> {
  late final TextEditingController _keyCtrl;
  late String _model;
  bool _obscured = true;

  @override
  void initState() {
    super.initState();
    _keyCtrl =
        TextEditingController(text: widget.settingsService.openaiApiKey ?? '');
    _model = widget.settingsService.openaiModel;
  }

  @override
  void dispose() {
    _keyCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await widget.settingsService.setOpenaiApiKey(_keyCtrl.text.trim());
    await widget.settingsService.setOpenaiModel(_model);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('保存しました'), duration: Duration(seconds: 2)),
    );
  }

  static const _models = [
    ('gpt-5-mini', 'GPT-5 mini (推奨・コスパ良)'),
    ('gpt-5', 'GPT-5 (最高精度・高い)'),
    ('gpt-5-nano', 'GPT-5 nano (最安・性能控え目)'),
    ('gpt-4o-mini', 'GPT-4o mini (定番・安定)'),
    ('gpt-4.1-mini', 'GPT-4.1 mini'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('AI コマンド設定', style: TextStyle(fontSize: 16)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'OpenAI API キー',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _keyCtrl,
              obscureText: _obscured,
              style: const TextStyle(
                  color: Colors.white, fontSize: 13, fontFamily: 'monospace'),
              decoration: InputDecoration(
                hintText: 'sk-...',
                hintStyle:
                    const TextStyle(color: Colors.white24, fontSize: 13),
                filled: true,
                fillColor: Colors.white.withOpacity(0.06),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide.none,
                ),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscured ? Icons.visibility : Icons.visibility_off,
                    color: Colors.white38,
                    size: 18,
                  ),
                  onPressed: () => setState(() => _obscured = !_obscured),
                ),
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'https://platform.openai.com/api-keys で発行',
              style: TextStyle(color: Colors.white38, fontSize: 11),
            ),
            const SizedBox(height: 24),
            const Text(
              'モデル',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 6),
            ..._models.map((entry) {
              final id = entry.$1;
              final label = entry.$2;
              final selected = id == _model;
              return InkWell(
                onTap: () => setState(() => _model = id),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Icon(
                        selected
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        color:
                            selected ? Colors.tealAccent : Colors.white38,
                        size: 18,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          label,
                          style: TextStyle(
                            color: selected ? Colors.tealAccent : Colors.white,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                style: TextButton.styleFrom(
                  backgroundColor: Colors.tealAccent.withOpacity(0.15),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                onPressed: _save,
                child: const Text(
                  '保存',
                  style: TextStyle(
                      color: Colors.tealAccent,
                      fontSize: 14,
                      fontWeight: FontWeight.w500),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              '※ API キーは端末内 (Hive) にのみ保存されます。\n'
              'OpenAI への通信は直接行われ、Layered Launcher のサーバーは経由しません。',
              style: TextStyle(color: Colors.white38, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}
