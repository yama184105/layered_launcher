part of '../home_screen.dart';

extension SelectionMethods on _HomeScreenState {
  // ── selection bar ─────────────────────────────────────────────

  Widget _buildSelectionBar() {
    final s = S.of(context);
    final empty = _selectedPackages.isEmpty;
    return Container(
      color: Colors.black.withValues(alpha: 0.92),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Row 1: count + cancel
            Row(
              children: [
                Text(
                  s.selectedCount(_selectedPackages.length),
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => setState(() {
                    _selectionMode = false;
                    _selectionInFavorites = false;
                    _selectedPackages.clear();
                  }),
                  child: Text(s.actionCancel,
                      style: const TextStyle(color: Colors.white54, fontSize: 13)),
                ),
              ],
            ),
            // Row 2: action buttons. Wrap so that 4 buttons (or longer
            // English labels) flow to a second line on narrow screens
            // instead of overflowing — was causing a yellow-stripe error
            // bar on Galaxy with the JA labels.
            Wrap(
              alignment: WrapAlignment.spaceEvenly,
              spacing: 4,
              runSpacing: 0,
              children: _selectionInFavorites
                  ? [
                      _selBtn(Icons.star_border, s.removeFavorite,
                          empty ? null : _bulkUnpinFromHome,
                          color: Colors.amber),
                    ]
                  : [
                      _selBtn(Icons.stairs, s.selectionFloorMove,
                          empty ? null : _showBulkMoveDialog),
                      // モード設定（ノーマル/スケジュール/使用回数/使用時間/
                      // 解除）をまとめて適用する
                      _selBtn(Icons.layers, s.selectionMode,
                          empty ? null : _showBulkModePicker),
                      _selBtn(Icons.timelapse, s.selectionTemp,
                          empty ? null : _showBulkTempMove,
                          color: Colors.orangeAccent),
                      _selBtn(Icons.star_outline, s.addFavorite,
                          empty ? null : _bulkPinToHome,
                          color: Colors.amber),
                      _selBtn(Icons.folder_open, s.selectionAddFolder,
                          empty ? null : _showBulkFolderDialog),
                    ],
            ),
          ],
        ),
      ),
    );
  }

  // ── folder selection bar ──────────────────────────────────────
  // フォルダの複数選択でできること: お気に入り / フォルダの位置 / 削除

  Widget _buildFolderSelectionBar() {
    final s = S.of(context);
    final empty = _selectedFolders.isEmpty;
    final allPinned = !empty &&
        _selectedFolders.every(
          (k) => widget.settingsService.pinnedFolderNames
              .contains(_folderNameOfKey(k)),
        );
    return Container(
      color: Colors.black.withValues(alpha: 0.92),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text(
                  s.selectedFoldersCount(_selectedFolders.length),
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => setState(() {
                    _folderSelectionMode = false;
                    _selectedFolders.clear();
                  }),
                  child: Text(s.actionCancel,
                      style:
                          const TextStyle(color: Colors.white54, fontSize: 13)),
                ),
              ],
            ),
            Wrap(
              alignment: WrapAlignment.spaceEvenly,
              spacing: 4,
              runSpacing: 0,
              children: [
                _selBtn(
                  allPinned ? Icons.star_border : Icons.star_outline,
                  allPinned ? s.removeFavorite : s.addFavorite,
                  empty ? null : _bulkToggleFolderFavorite,
                  color: Colors.amber,
                ),
                _selBtn(Icons.swap_vert, s.folderPosition,
                    empty ? null : _showBulkFolderPositionDialog),
                _selBtn(Icons.delete_outline, s.actionDelete,
                    empty ? null : _bulkDeleteFolders,
                    color: Colors.redAccent),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _selBtn(IconData icon, String label, VoidCallback? onTap,
      {Color color = Colors.white70}) {
    return TextButton.icon(
      style: TextButton.styleFrom(
        foregroundColor: onTap == null ? Colors.white24 : color,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      ),
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label, style: const TextStyle(fontSize: 11)),
    );
  }
}
