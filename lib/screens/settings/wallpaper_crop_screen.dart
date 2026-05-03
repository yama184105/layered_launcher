part of 'settings_screen.dart';


// ── Wallpaper Crop Screen ─────────────────────────────────────────────────────

class _WallpaperCropScreen extends StatefulWidget {
  final String imagePath;
  const _WallpaperCropScreen({required this.imagePath});
  @override
  State<_WallpaperCropScreen> createState() => _WallpaperCropScreenState();
}

class _WallpaperCropScreenState extends State<_WallpaperCropScreen> {
  Offset _offset = Offset.zero;
  double _scale = 1.0;
  double _baseScale = 1.0;
  bool _loaded = false;
  double _minScale = 0.5;
  double _cropAspectRatio = 9.0 / 20.0;
  final GlobalKey _cropKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _loadImageSize();
  }

  Future<void> _loadImageSize() async {
    try {
      final data = await File(widget.imagePath).readAsBytes();
      final codec = await ui.instantiateImageCodec(data);
      final frame = await codec.getNextFrame();
      final img = frame.image;
      final imgW = img.width.toDouble();
      final imgH = img.height.toDouble();
      img.dispose();
      if (mounted) {
        final dpr = MediaQuery.of(context).devicePixelRatio;
        final logicalW = imgW / dpr;
        final logicalH = imgH / dpr;
        // Use full screen size (including status bar and nav bar) for aspect ratio
        final screen = MediaQuery.of(context).size;
        final cropW = screen.width;
        final cropH = screen.height;
        final aspect = cropW / cropH;
        // Allow zoom-out to ~20% of fill scale so users can crop a wider area
        final fillScale = math.max(cropW / logicalW, cropH / logicalH);
        final minS = (fillScale * 0.2).clamp(0.05, 1.0);
        setState(() { _minScale = minS; _cropAspectRatio = aspect; _loaded = true; });
      }
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  Future<void> _confirm(BuildContext ctx) async {
    final boundary = _cropKey.currentContext?.findRenderObject()
        as RenderRepaintBoundary?;
    if (boundary == null || !ctx.mounted) return;
    final dpr = MediaQuery.of(ctx).devicePixelRatio;
    final img = await boundary.toImage(pixelRatio: dpr);
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null || !ctx.mounted) return;
    final bytes = byteData.buffer.asUint8List();
    final dir = await getApplicationDocumentsDirectory();
    final outPath = '${dir.path}/wallpaper_${DateTime.now().millisecondsSinceEpoch}.png';
    await File(outPath).writeAsBytes(bytes);
    if (ctx.mounted) Navigator.pop(ctx, outPath);
  }

  @override
  Widget build(BuildContext ctx) {
    if (!_loaded) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(S.of(ctx).wallpaperCropTitle, style: const TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          TextButton(
            onPressed: () => _confirm(ctx),
            child: Text(S.of(ctx).actionConfirmShort, style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: GestureDetector(
        onScaleStart: (d) => _baseScale = _scale,
        onScaleUpdate: (d) {
          setState(() {
            _scale = (_baseScale * d.scale).clamp(_minScale, 4.0);
            _offset += d.focalPointDelta;
          });
        },
        child: Center(
          child: RepaintBoundary(
            key: _cropKey,
            child: AspectRatio(
              aspectRatio: _cropAspectRatio,
              child: ClipRect(
                child: OverflowBox(
                  maxWidth: double.infinity,
                  maxHeight: double.infinity,
                  child: Transform.translate(
                    offset: _offset,
                    child: Transform.scale(
                      scale: _scale,
                      child: Image.file(File(widget.imagePath), fit: BoxFit.cover),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
