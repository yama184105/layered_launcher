part of 'home_screen.dart';

// ── Floor label ────────────────────────────────────────────────────────────────

String floorLabel(int floor) {
  if (floor == 0) return 'HOME';
  if (floor < 0) return 'B${-floor}F';
  return '${floor}F';
}

/// Formats a UsageStats lastTimeUsed timestamp as a short relative label
/// like "3m ago" / "2h ago" / "5d ago". Returns null when the timestamp is
/// missing/invalid or older than ~30 days.
String? formatLastUsedRelative(BuildContext context, int? lastUsedMs, {DateTime? now}) {
  if (lastUsedMs == null || lastUsedMs <= 0) return null;
  final reference = now ?? DateTime.now();
  final diff = reference.millisecondsSinceEpoch - lastUsedMs;
  if (diff < 0) return null;
  const minute = 60 * 1000;
  const hour = 60 * minute;
  const day = 24 * hour;
  final s = S.of(context);
  if (diff < minute) return s.relTimeJustNow;
  if (diff < hour) return s.relTimeMinutesAgo(diff ~/ minute);
  if (diff < day) return s.relTimeHoursAgo(diff ~/ hour);
  if (diff < 30 * day) return s.relTimeDaysAgo(diff ~/ day);
  return null;
}

/// Shows a countdown timer dialog for strict mode.
/// Returns true if the user waited for the timer and confirmed.
Future<bool> showStrictTimerDialog(BuildContext context, {int seconds = 10}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _StrictTimerDialog(seconds: seconds),
  );
  return result == true;
}

class _StrictTimerDialog extends StatefulWidget {
  final int seconds;
  const _StrictTimerDialog({required this.seconds});
  @override
  State<_StrictTimerDialog> createState() => _StrictTimerDialogState();
}

class _StrictTimerDialogState extends State<_StrictTimerDialog> {
  late int _remaining;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _remaining = widget.seconds;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _remaining--;
        if (_remaining <= 0) _timer?.cancel();
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final done = _remaining <= 0;
    return AlertDialog(
      backgroundColor: const Color(0xFF1A1A1A),
      title: Text(s.strictModeTimerTitle,
          style: const TextStyle(color: Colors.orangeAccent, fontSize: 15)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(s.strictTimerWaitMessage,
              style: const TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(height: 20),
          Text(
            done ? s.strictTimerCanConfirm : '$_remaining',
            style: TextStyle(
              color: done ? Colors.tealAccent : Colors.orangeAccent,
              fontSize: done ? 16 : 48,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          if (!done)
            const LinearProgressIndicator(color: Colors.orangeAccent, backgroundColor: Colors.white12),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(s.actionCancel, style: const TextStyle(color: Colors.white54)),
        ),
        TextButton(
          onPressed: done ? () => Navigator.pop(context, true) : null,
          child: Text(s.actionConfirmShort,
              style: TextStyle(
                  color: done ? Colors.tealAccent : Colors.white24,
                  fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}

// ── Stair curve ────────────────────────────────────────────────────────────────
class _StairCurve extends Curve {
  const _StairCurve({this.steps = 4});
  final int steps;

  @override
  double transformInternal(double t) {
    if (t >= 1.0) return 1.0;
    final seg = 1.0 / steps;
    final step = (t / seg).floor().clamp(0, steps - 1);
    final localT = (t % seg) / seg;
    final moveT = (localT / 0.5).clamp(0.0, 1.0);
    return ((step + Curves.easeOutCubic.transform(moveT)) / steps)
        .clamp(0.0, 1.0);
  }
}

class _DiscreteStairCurve extends Curve {
  const _DiscreteStairCurve({this.steps = 6});
  final int steps;

  @override
  double transformInternal(double t) {
    if (t >= 1.0) return 1.0;
    final seg = 1.0 / steps;
    final step = (t / seg).floor().clamp(0, steps - 1);
    final localT = (t % seg) / seg;
    // Move in first 35% of each step, hold for remaining 65%
    final moveT = (localT / 0.35).clamp(0.0, 1.0);
    return ((step + Curves.easeOutCubic.transform(moveT)) / steps)
        .clamp(0.0, 1.0);
  }
}

// ── Floor theme helpers ────────────────────────────────────────────────────────

Color _floorBg(int floor) {
  if (floor <= 1) return const Color(0xFF000000);
  if (floor == 2) return const Color(0xFF111111);
  if (floor == 3) return const Color(0xFF0D0D0D);
  // floor 4+: start at 0x0B = 11, decrease by 2 per floor above 4
  final base = 0x0B - (floor - 4) * 2;
  final v = base.clamp(0, 0xFF);
  return Color.fromARGB(255, v, v, v);
}

Color _floorText(int floor) {
  if (floor <= 1) return Colors.white;
  if (floor == 2) return const Color(0xFFE8E8E8);
  if (floor == 3) return const Color(0xFFC8C8C8);
  // floor 4+: start at 0xC8 = 200, decrease by 20 per floor above 4
  final base = 0xC8 - (floor - 4) * 20;
  final v = base.clamp(80, 0xFF);
  return Color.fromARGB(255, v, v, v);
}

// ── Favorite item discriminated union ──────────────────────────────────────────

class _FavItem {
  final AppConfig? app;
  final String? folderName;
  const _FavItem.app(AppConfig a) : app = a, folderName = null;
  const _FavItem.folder(String name) : app = null, folderName = name;
  bool get isFolder => folderName != null;
}

