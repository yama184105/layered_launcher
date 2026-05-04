part of '../home_screen.dart';

extension SelectionMethods on _HomeScreenState {
  // ── selection bar ─────────────────────────────────────────────

  Widget _buildSelectionBar() {
    final s = S.of(context);
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
                      _selBtn(Icons.star_outline, s.addFavorite,
                          empty ? null : _bulkPinToHome,
                          color: Colors.amber),
                      _selBtn(Icons.folder_open, s.selectionAddFolder,
                          empty ? null : _showBulkFolderDialog),
                      _selBtn(Icons.schedule, s.autoMove,
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
