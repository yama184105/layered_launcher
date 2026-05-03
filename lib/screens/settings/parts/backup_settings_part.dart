part of '../settings_screen.dart';

extension BackupSettingsMethods on _SettingsScreenState {
  // ── Backup & Restore section ───────────────────────────────────
  Widget _buildBackupRestoreSection() {
    final emailCtrl = TextEditingController();
    return StatefulBuilder(
      builder: (context, setInner) {
        final s = S.of(context);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.backupRestoreTitle,
                style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            TextField(
              controller: emailCtrl,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                hintText: s.emailHint,
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
                        subject: s.backupSubject,
                        body: s.backupBodyPrefix(jsonStr),
                      );
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white70,
                      side: const BorderSide(color: Colors.white24),
                    ),
                    icon: const Icon(Icons.backup, size: 16),
                    label: Text(s.sendBackup, style: const TextStyle(fontSize: 12)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(s.restoreInstructions)),
                      );
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white70,
                      side: const BorderSide(color: Colors.white24),
                    ),
                    icon: const Icon(Icons.restore, size: 16),
                    label: Text(s.restoreFromBackup, style: const TextStyle(fontSize: 12)),
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
