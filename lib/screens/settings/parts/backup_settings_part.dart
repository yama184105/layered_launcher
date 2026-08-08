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
            const SizedBox(height: 4),
            Text(s.backupIncludesHint,
                style: const TextStyle(color: Colors.white38, fontSize: 11)),
            const SizedBox(height: 8),
            TextField(
              controller: emailCtrl,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                hintText: s.emailHint,
                hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.07),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _sendBackupEmail(emailCtrl.text.trim()),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: const BorderSide(color: Colors.white24),
                  ),
                  icon: const Icon(Icons.backup, size: 16),
                  label: Text(s.sendBackup, style: const TextStyle(fontSize: 12)),
                ),
                OutlinedButton.icon(
                  onPressed: _copyBackupToClipboard,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: const BorderSide(color: Colors.white24),
                  ),
                  icon: const Icon(Icons.copy_all, size: 16),
                  label: Text(s.backupCopy, style: const TextStyle(fontSize: 12)),
                ),
                OutlinedButton.icon(
                  onPressed: _showRestoreDialog,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.tealAccent,
                    side: const BorderSide(color: Colors.white24),
                  ),
                  icon: const Icon(Icons.restore, size: 16),
                  label: Text(s.restoreFromBackup,
                      style: const TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Future<void> _sendBackupEmail(String email) async {
    final json = _ss.buildBackupJson(_as.box);
    await _native.sendEmail(
      to: email,
      subject: S.of(context).backupSubject,
      body: S.of(context).backupBodyPrefix(json),
    );
  }

  Future<void> _copyBackupToClipboard() async {
    final json = _ss.buildBackupJson(_as.box);
    await Clipboard.setData(ClipboardData(text: json));
    if (mounted) _showSnack(S.of(context).backupCopied);
  }

  /// 貼り付けたバックアップJSONから復元する。復元は全設定を上書きできる
  /// ＝ストリクトの制限を丸ごと外せてしまうので、サブモード設定ロックの
  /// ゲートを通す。
  Future<void> _showRestoreDialog() async {
    final ctrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: Text(S.of(ctx).restoreFromBackup,
            style: const TextStyle(color: Colors.white, fontSize: 14)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(S.of(ctx).restoreInstructions,
                style: const TextStyle(color: Colors.white54, fontSize: 11)),
            const SizedBox(height: 8),
            TextField(
              controller: ctrl,
              maxLines: 6,
              style: const TextStyle(color: Colors.white, fontSize: 11),
              decoration: InputDecoration(
                hintText: '{"version":1,...}',
                hintStyle:
                    const TextStyle(color: Colors.white24, fontSize: 11),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.07),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              style: TextButton.styleFrom(
                  foregroundColor: Colors.tealAccent,
                  padding: EdgeInsets.zero),
              icon: const Icon(Icons.paste, size: 16),
              label: Text(S.of(ctx).backupPaste,
                  style: const TextStyle(fontSize: 12)),
              onPressed: () async {
                final data = await Clipboard.getData(Clipboard.kTextPlain);
                if (data?.text != null) ctrl.text = data!.text!;
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(S.of(ctx).actionCancel,
                style: const TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(S.of(ctx).actionConfirm,
                style: const TextStyle(color: Colors.tealAccent)),
          ),
        ],
      ),
    );
    final raw = ctrl.text;
    WidgetsBinding.instance.addPostFrameCallback((_) => ctrl.dispose());
    if (confirmed != true || raw.trim().isEmpty || !mounted) return;

    final gate = await requestStrictAction(
      context,
      _ss,
      key: 'submode',
      blockedMessage: S.of(context).submodeLocked,
      treatBlockAsTimer: true,
    );
    if (gate != StrictGateResult.allowed || !mounted) return;

    try {
      final count = await _ss.restoreBackupJson(raw, _as.box);
      if (mounted) {
        _showSnack(S.of(context).restoreDone(count));
        await _load();
        setState(() {});
      }
    } on FormatException {
      if (mounted) _showSnack(S.of(context).restoreFailed);
    }
  }
}
