part of '../home_screen.dart';

extension SelectionMethods on _HomeScreenState {
  // ── selection bar ─────────────────────────────────────────────

  Widget _buildSelectionBar() {
    final empty = _selectedPackages.isEmpty;
    return Container(
      color: Colors.black.withOpacity(0.92),
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
                  '${_selectedPackages.length}個選択中',
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => setState(() {
                    _selectionMode = false;
                    _selectionInFavorites = false;
                    _selectedPackages.clear();
                  }),
                  child: const Text('キャンセル',
                      style: TextStyle(color: Colors.white54, fontSize: 13)),
                ),
              ],
            ),
            // Row 2: action buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: _selectionInFavorites
                  ? [
                      _selBtn(Icons.star_border, 'お気に入り解除',
                          empty ? null : _bulkUnpinFromHome,
                          color: Colors.amber),
                    ]
                  : [
                      _selBtn(Icons.stairs, 'フロア移動',
                          empty ? null : _showBulkMoveDialog),
                      _selBtn(Icons.star_outline, 'お気に入り追加',
                          empty ? null : _bulkPinToHome,
                          color: Colors.amber),
                      _selBtn(Icons.folder_open, 'フォルダ追加',
                          empty ? null : _showBulkFolderDialog),
                      _selBtn(Icons.schedule, '自動移動',
                          empty ? null : _showBulkAutoMoveScreen),
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
