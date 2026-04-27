part of '../settings_screen.dart';

extension BackupSettingsMethods on _SettingsScreenState {
  // ── Backup & Restore section ───────────────────────────────────
  Widget _buildBackupRestoreSection() {
    final emailCtrl = TextEditingController();
    return StatefulBuilder(
      builder: (context, setInner) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('バックアップ・復元',
                style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            TextField(
              controller: emailCtrl,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                hintText: 'メールアドレスを入力...',
                hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                filled: true,
                fillColor: Colors.white.withOpacity(0.07),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final email = emailCtrl.text.trim();
                      // Build backup JSON from settings box
                      final settingsData = <String, dynamic>{};
                      final box = _ss.exportAllSettings();
                      settingsData['settings'] = box;
                      final jsonStr = settingsData.toString();
                      await _native.sendEmail(
                        to: email,
                        subject: 'Layered Launcher バックアップ',
                        body: 'バックアップデータ:\n\n$jsonStr',
                      );
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white70,
                      side: const BorderSide(color: Colors.white24),
                    ),
                    icon: const Icon(Icons.backup, size: 16),
                    label: const Text('バックアップを送信', style: TextStyle(fontSize: 12)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('復元するには、バックアップメールを開いてデータをコピーしてください')),
                      );
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white70,
                      side: const BorderSide(color: Colors.white24),
                    ),
                    icon: const Icon(Icons.restore, size: 16),
                    label: const Text('バックアップから復元', style: TextStyle(fontSize: 12)),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

}
