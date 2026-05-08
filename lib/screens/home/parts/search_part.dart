part of '../home_screen.dart';

extension SearchMethods on _HomeScreenState {
  // ── sort key helper ───────────────────────────────────────────

  int _sortKey(String s) {
    if (s.isEmpty) return 3;
    final c = s.codeUnitAt(0);
    if ((c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A)) return 0; // A-Z
    if (c >= 0x3040 && c <= 0x30FF) return 1; // hiragana/katakana
    if (c >= 0x4E00 && c <= 0x9FFF) return 1; // kanji
    return 2; // symbols/numbers
  }

  // ── alphabet / あいうえお index ────────────────────────────────

  String _indexChar(String name) {
    if (name.isEmpty) return '#';
    final c = name[0];
    final code = c.codeUnitAt(0);

    // Normalize katakana → hiragana equivalent code point
    int hCode = code;
    if (code >= 0x30A1 && code <= 0x30F6) hCode = code - 0x60;

    if (hCode >= 0x3041 && hCode <= 0x304A) return 'あ';
    if (hCode >= 0x304B && hCode <= 0x3053) return 'か';
    if (hCode >= 0x3055 && hCode <= 0x305D) return 'さ';
    if (hCode >= 0x305F && hCode <= 0x3068) return 'た';
    if (hCode >= 0x306A && hCode <= 0x306E) return 'な';
    if (hCode >= 0x306F && hCode <= 0x307B) return 'は';
    if (hCode >= 0x307E && hCode <= 0x3082) return 'ま';
    if (hCode >= 0x3084 && hCode <= 0x3088) return 'や';
    if (hCode >= 0x3089 && hCode <= 0x308D) return 'ら';
    if (hCode >= 0x308F && hCode <= 0x3093) return 'わ';

    if ((code >= 0x41 && code <= 0x5A) || (code >= 0x61 && code <= 0x7A)) {
      return c.toUpperCase();
    }
    return '#';
  }

  Widget _buildIndexSidebar(List<AppConfig> apps, Map<String, GlobalKey> sectionKeys) {
    if (!widget.settingsService.showAlphabetIndex) return const SizedBox.shrink();
    // No artificial app-count threshold — the sidebar already self-suppresses
    // (returning SizedBox.shrink later) when no sections are present.

    const normalOrder = [
      'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M',
      'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z',
      'あ', 'か', 'さ', 'た', 'な', 'は', 'ま', 'や', 'ら', 'わ',
      '#'
    ];
    final normalSorted = normalOrder.where((c) => sectionKeys.containsKey(c)).toList();
    final hasEmergencyIndex = sectionKeys.containsKey('🚨');
    // Collect emergency sub-indices (keys like '🚨A', '🚨B', etc.)
    final emgSubKeys = <String>[];
    if (hasEmergencyIndex) {
      for (final c in normalOrder) {
        if (sectionKeys.containsKey('🚨$c')) emgSubKeys.add('🚨$c');
      }
    }

    if (normalSorted.isEmpty && !hasEmergencyIndex) return const SizedBox.shrink();

    void scrollTo(String key) {
      // 同じキーへの連続要求はハイライトだけ更新してスクロール再発火を抑える
      if (key == _lastScrolledIndexKey) {
        if (_activeIndexChar != key) {
          setState(() => _activeIndexChar = key);
        }
        return;
      }
      _lastScrolledIndexKey = key;
      final globalKey = sectionKeys[key];
      final ctx = globalKey?.currentContext;
      if (ctx != null) {
        // Duration.zero で即時ジャンプ。ドラッグ追従でアニメ重なりが起きない。
        Scrollable.ensureVisible(
          ctx,
          duration: Duration.zero,
          alignment: 0.0,
        );
      } else if (_scrollController.hasClients) {
        // ctx 未解決（off-screen で未ビルド）の保険：先に近い位置までジャンプして
        // 次フレームでもう一度 ensureVisible を試す。
        final anchorOrder = [
          'A','B','C','D','E','F','G','H','I','J','K','L','M',
          'N','O','P','Q','R','S','T','U','V','W','X','Y','Z',
          'あ','か','さ','た','な','は','ま','や','ら','わ','#',
        ];
        final pos = anchorOrder.indexOf(key.startsWith('🚨') && key.length > 1 ? key.substring(1) : key);
        if (pos >= 0) {
          final maxScroll = _scrollController.position.maxScrollExtent;
          final estimate = maxScroll * (pos / anchorOrder.length);
          _scrollController.jumpTo(estimate.clamp(0.0, maxScroll));
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final ctx2 = sectionKeys[key]?.currentContext;
            if (ctx2 != null) {
              Scrollable.ensureVisible(ctx2, duration: Duration.zero, alignment: 0.0);
            }
          });
        }
      }
      setState(() => _activeIndexChar = key);
    }

    void dismissHighlight() {
      _lastScrolledIndexKey = null;
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) setState(() => _activeIndexChar = null);
      });
    }

    Widget indexItem(String key, {Color? colorOverride}) {
      final isActive = key == _activeIndexChar;
      // Display label: for prefixed keys like '🚨A', show just 'A'
      final display = key.startsWith('🚨') && key.length > 2 ? key.substring(2) : key;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: isActive
            ? Container(
                width: 18, height: 18,
                decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white),
                child: Center(child: Text(display, textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.black, fontSize: 9, fontWeight: FontWeight.w700))),
              )
            : Text(display, textAlign: TextAlign.center,
                style: TextStyle(
                    color: colorOverride ?? Colors.white38,
                    fontSize: 10, fontWeight: FontWeight.w600)),
      );
    }

    // Build a single-section index strip (used for both emergency and normal)
    Widget indexStrip(List<String> items, {Color? itemColor}) {
      return LayoutBuilder(
        builder: (ctx, constraints) {
          final totalH = constraints.maxHeight > 0 ? constraints.maxHeight : items.length * 22.0;
          const double itemH = 22.0;
          final totalItemsH = items.length * itemH;
          final itemsStartY = ((totalH - totalItemsH) / 2).clamp(0.0, double.infinity);

          void handleAt(double localY) {
            final relY = localY - itemsStartY;
            // 範囲外でも端の項目にスナップさせて反応を切らさない
            final clampedRelY = relY.clamp(0.0, totalItemsH - 0.001);
            final idx = (clampedRelY / itemH).floor().clamp(0, items.length - 1);
            scrollTo(items[idx]);
          }

          // Listener で raw pointer event を直接拾う。GestureDetector の
          // ドラッグ方向認識を待たないため、指を置いた瞬間から追従する。
          return Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (e) => handleAt(e.localPosition.dy),
            onPointerMove: (e) => handleAt(e.localPosition.dy),
            onPointerUp: (_) => dismissHighlight(),
            onPointerCancel: (_) => dismissHighlight(),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: items.map((c) => indexItem(c, colorOverride: itemColor)).toList(),
            ),
          );
        },
      );
    }

    // If emergency index is active, split sidebar exactly 50/50 (top=emergency, bottom=normal)
    if (hasEmergencyIndex && normalSorted.isNotEmpty) {
      final emgItems = ['🚨', ...emgSubKeys];
      return SizedBox(
        width: 32,
        child: LayoutBuilder(builder: (ctx, constraints) {
          const divH = 5.0; // divider area height
          final half = (constraints.maxHeight - divH) / 2;
          final itemH = 22.0;
          final maxPerHalf = (half / itemH).floor().clamp(1, 999);
          final emgThinned = _thinIndexItems(emgItems, maxPerHalf);
          final normalThinned = _thinIndexItems(normalSorted, maxPerHalf);
          return Column(children: [
            SizedBox(height: half, child: indexStrip(emgThinned, itemColor: Colors.redAccent)),
            Container(width: 16, height: 1, color: Colors.white12),
            const SizedBox(height: divH - 1),
            SizedBox(height: half, child: indexStrip(normalThinned)),
          ]);
        }),
      );
    }

    // Only emergency, or only normal
    final items = hasEmergencyIndex
        ? ['🚨', ...emgSubKeys]
        : normalSorted;
    return SizedBox(
      width: 32,
      child: indexStrip(items, itemColor: hasEmergencyIndex ? Colors.redAccent : null),
    );
  }

  /// Thins [items] so at most [maxItems] are shown.
  /// Step 2 → skip 1, step 3 → skip 2, etc.
  List<String> _thinIndexItems(List<String> items, int maxItems) {
    if (items.length <= maxItems) return items;
    for (int step = 2; step <= items.length; step++) {
      final thinned = <String>[];
      for (int i = 0; i < items.length; i += step) thinned.add(items[i]);
      if (thinned.length <= maxItems) return thinned;
    }
    return items.isEmpty ? items : [items.first];
  }

  // ── search results ────────────────────────────────────────────

  Widget _buildSearchResults() {
    final q = _searchQuery.toLowerCase();
    final results = _allApps
        .where((a) =>
            _displayName(a).toLowerCase().contains(q) ||
            a.appName.toLowerCase().contains(q))
        .toList()
      ..sort((a, b) => _displayName(a).compareTo(_displayName(b)));

    if (results.isEmpty) {
      return Center(
        child: Text(S.of(context).noMatchingApps,
            style: const TextStyle(color: Colors.white38, fontSize: 14)),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: results.length,
      itemBuilder: (_, i) {
        final app = results[i];
        final folder = _folderOf(app);
        final location =
            folder != null ? '${floorLabel(app.floor)} / $folder' : floorLabel(app.floor);

        return Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Text(_displayName(app),
                    style: const TextStyle(
                        color: Colors.white, fontSize: 15)),
              ),
              Text(location,
                  style: const TextStyle(
                      color: Colors.white38, fontSize: 13)),
            ],
          ),
        );
      },
    );
  }

  // ── search bar ────────────────────────────────────────────────

  Widget _searchBar() {
    final textColor = _fontColor;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
          child: TextField(
            controller: _searchCtrl,
            focusNode: _searchFocusNode,
            style: TextStyle(color: textColor, fontSize: 14),
            decoration: InputDecoration(
              hintText: S.of(context).appSearchHint,
              hintStyle: TextStyle(color: textColor.withOpacity(0.5), fontSize: 13),
              prefixIcon: Icon(Icons.search, color: textColor.withOpacity(0.5), size: 18),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: Icon(Icons.clear, color: textColor.withOpacity(0.5), size: 18),
                      onPressed: _searchCtrl.clear,
                    )
                  : null,
              filled: true,
              fillColor: Colors.transparent,
              contentPadding: const EdgeInsets.symmetric(vertical: 6),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        Divider(height: 1, thickness: 1, color: _fontColor.withOpacity(0.15)),
      ],
    );
  }
}
