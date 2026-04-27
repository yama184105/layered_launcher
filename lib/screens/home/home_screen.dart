import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:android_intent_plus/android_intent.dart';
import 'package:device_apps/device_apps.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import '../../models/app_config.dart';
import '../../services/app_service.dart';
import '../../services/native_service.dart';
import '../../services/settings_service.dart';
import '../settings/settings_screen.dart';
import '../settings/automove_screen.dart';

part 'home_helpers.dart';
part 'home_clock_painter.dart';
part 'parts/home_content_part.dart';
part 'parts/floor_content_part.dart';
part 'parts/dialogs_part.dart';
part 'parts/favorites_part.dart';
part 'parts/search_part.dart';
part 'parts/selection_part.dart';

// ──────────────────────────────────────────────────────────────────────────────

class HomeScreen extends StatefulWidget {
  final AppService appService;
  final SettingsService settingsService;
  const HomeScreen(
      {super.key, required this.appService, required this.settingsService});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  // ── data ──────────────────────────────────────────────────────
  List<AppConfig> _allApps = [];
  bool _loading = true;
  Timer? _ticker;
  Timer? _widgetRefreshTimer;
  Timer? _batchTimer;
  int _lastAutoMoveMinute = -1;
  Duration? _emergencyRemaining;
  DateTime _now = DateTime.now();

  // ── emergency 1F display ────────────────────────────────────
  /// Packages temporarily shown on 1F during emergency mode.
  /// These apps keep their original floor but also appear on 1F.
  final Set<String> _emergency1FApps = {};
  DateTime? _emergencyEndTime;

  // ── native service ────────────────────────────────────────────
  final NativeService _native = NativeService();

  // ── home widget state ─────────────────────────────────────────
  int _batteryLevel = -1;
  int _screenTimeMinutes = -1;
  Map<String, int> _notifCounts = {};
  bool _notifPermAsked = false;
  bool _usagePermGranted = false;

  // ── last-used timestamps (UsageStats lastTimeUsed) ───────────
  /// Cached package -> lastTimeUsed (epoch ms), refreshed every minute.
  Map<String, int> _lastUsedMap = {};
  int _lastUsedFetchMinute = -1;

  // ── floors ────────────────────────────────────────────────────
  static const int _homeFloor = 0;
  int get _minFloor => -(widget.settingsService.undergroundFloors);
  int _currentFloor = _homeFloor;

  // ── charging animation ────────────────────────────────────────
  bool _isCharging = false;
  Timer? _chargingCheckTimer;
  late AnimationController _chargingCtrl;
  late Animation<double> _chargingAnim;

  // ── animation ─────────────────────────────────────────────────
  late AnimationController _ctrl;
  late Animation<double> _stairAnim;
  late Animation<double> _smoothAnim;
  late AnimationController _slideCtrl;
  late Animation<double> _slideAnim;
  late Animation<double> _discreteStairAnim;
  bool _isAnimating = false;
  bool _isSlideAnim = false;
  bool _goingUp = true;
  int _fromFloor = 0;
  List<AppConfig> _fromApps = [];

  // ── search ────────────────────────────────────────────────────
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _searchQuery = '';

  // ── folders ───────────────────────────────────────────────────
  final Set<String> _openFolders = {};

  // ── scroll & index ────────────────────────────────────────────
  final ScrollController _scrollController = ScrollController();

  // ── notifications ─────────────────────────────────────────────
  final FlutterLocalNotificationsPlugin _flnp =
      FlutterLocalNotificationsPlugin();

  // ── mindful delay ─────────────────────────────────────────────
  bool _mindfulActive = false;
  bool _mindfulCancelled = false;
  Timer? _mindfulTimer;

  // ── selection mode ────────────────────────────────────────────
  bool _selectionMode = false;
  bool _selectionInFavorites = false;
  final Set<String> _selectedPackages = {};

  // ── app install watcher ───────────────────────────────────────
  StreamSubscription<ApplicationEvent>? _appChangeSub;
  StreamSubscription<void>? _homePressedSub;

  // ── external app tracking ─────────────────────────────────────
  /// True while an external app (or settings) is in foreground.
  /// When the user presses the Android home button and returns here,
  /// we reset to homeFloor.
  bool _launchedExternalApp = false;
  /// True while we are inside an in-app screen (settings etc.) via Navigator.push.
  bool _isInExternalScreen = false;

  // ── reorder mode ──────────────────────────────────────────────
  bool _reorderMode = false;
  List<AppConfig> _cachedFavorites = [];

  // ── folder reorder mode ───────────────────────────────────────
  String? _reorderingFolderKey;
  List<AppConfig> _reorderingFolderApps = [];

  // ── page controller (home ↔ 1F) ──────────────────────────────
  late PageController _pageCtrl;

  // ── alphabet index highlight ──────────────────────────────────
  String? _activeIndexChar;

  int get _maxFloor => widget.settingsService.maxFloors;


  // ── lifecycle ─────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ctrl =
        AnimationController(vsync: this, duration: const Duration(seconds: 3));
    _stairAnim =
        CurvedAnimation(parent: _ctrl, curve: const _StairCurve(steps: 4));
    _smoothAnim =
        CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
    _slideCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 300));
    _slideAnim =
        CurvedAnimation(parent: _slideCtrl, curve: Curves.easeInOut);
    _discreteStairAnim =
        CurvedAnimation(parent: _ctrl, curve: const _DiscreteStairCurve(steps: 6));
    _chargingCtrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 30))
      ..repeat();
    _chargingAnim = CurvedAnimation(parent: _chargingCtrl, curve: Curves.linear);
    _pageCtrl = PageController(initialPage: _currentFloor == 1 ? 1 : 0);
    _searchCtrl
        .addListener(() => setState(() => _searchQuery = _searchCtrl.text));
    _loadApps();
    _appChangeSub = DeviceApps.listenToAppsChanges().listen((event) {
      if (event.event == ApplicationEventType.installed) {
        widget.settingsService.recordAppInstallDate(event.packageName);
      }
      _loadApps();
    }, onError: (_) {});
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    _initNotifications();
    _loadHomeWidgets();
    _widgetRefreshTimer = Timer.periodic(
        const Duration(minutes: 5), (_) => _loadHomeWidgets());
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkNotifPerm());
    _startBatchTimer();
    _startChargingTimer();
    _homePressedSub = _native.onHomePressed.listen((_) {
      if (!mounted || _isAnimating) return;
      if (_currentFloor != _homeFloor) {
        setState(() => _currentFloor = _homeFloor);
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _pageCtrl.hasClients) {
          _pageCtrl.jumpToPage(0);
        }
      });
    });
    _processAutoMoves();
  }

  Future<void> _processAutoMoves() async {
    final ss = widget.settingsService;
    final apps = ss.allAutoMoveApps;
    if (apps.isEmpty) return;
    final now = DateTime.now();
    final rng = Random();
    bool changed = false;

    for (final pkg in apps) {
      final mode = ss.autoMoveMode(pkg);
      final app = _allApps.cast<AppConfig?>().firstWhere(
        (a) => a?.packageName == pkg,
        orElse: () => null,
      );
      if (app == null) continue;

      if (mode == 'interval') {
        // Mode B: interval random
        final intervalDays = ss.autoMoveIntervalDays(pkg);
        final floors = ss.autoMoveIntervalFloors(pkg);
        if (floors.isEmpty) continue;
        final lastMs = ss.autoMoveLastMovedMs(pkg);
        final intervalMs = intervalDays * 24 * 60 * 60 * 1000;

        bool shouldMove = false;
        if (lastMs == null) {
          shouldMove = true;
        } else if (intervalDays == 0) {
          // 0 days = every check (once per minute cycle, but effectively once per day)
          final lastDate = DateTime.fromMillisecondsSinceEpoch(lastMs);
          if (now.day != lastDate.day || now.month != lastDate.month || now.year != lastDate.year) {
            shouldMove = true;
          }
        } else if (now.millisecondsSinceEpoch - lastMs >= intervalMs) {
          shouldMove = true;
        }

        if (shouldMove) {
          final newFloor = floors[rng.nextInt(floors.length)];
          app.floor = newFloor;
          await widget.appService.saveConfig(app);
          await ss.setAutoMoveLastMovedMs(pkg, now.millisecondsSinceEpoch);
          changed = true;
        }
      } else if (mode == 'schedule') {
        // Mode A: schedule
        final schedule = ss.autoMoveSchedule(pkg);
        final wdKey = now.weekday.toString();
        final dayData = schedule[wdKey];
        if (dayData == null) continue;
        final slots = (dayData['slots'] as List?) ?? [];
        final nowMin = now.hour * 60 + now.minute;

        // Find the active slot for the current time
        Map<String, dynamic>? activeSlot;
        int activeStart = 0;
        int activeEnd = 1440;
        String activeKey = '';
        for (final slotRaw in slots) {
          final slot = Map<String, dynamic>.from(slotRaw as Map);
          final startMin = (slot['startMinute'] as num?)?.toInt() ?? 0;
          final endMin = (slot['endMinute'] as num?)?.toInt() ?? 1440;
          if (nowMin < startMin || nowMin >= endMin) continue;
          activeSlot = slot;
          activeStart = startMin;
          activeEnd = endMin;
          activeKey = '${wdKey}_${startMin}_$endMin';
          break;
        }
        // Fallback to default if no slot matches
        if (activeSlot == null) {
          final defaultData = dayData['default'];
          if (defaultData is! Map) continue;
          activeSlot = Map<String, dynamic>.from(defaultData);
          activeStart = 0;
          activeEnd = 1440;
          activeKey = '${wdKey}_default';
        }

        final slotKey = activeKey;
        final lastSlot = ss.autoMoveLastSlotKey(pkg);
        final type = (activeSlot['type'] as String?) ?? 'fixed';

        if (type == 'fixed') {
          final targetFloor = (activeSlot['floor'] as num?)?.toInt() ?? 1;
          if (app.floor != targetFloor || lastSlot != slotKey) {
            app.floor = targetFloor;
            await widget.appService.saveConfig(app);
            await ss.setAutoMoveLastSlotKey(pkg, slotKey);
            changed = true;
          }
        } else {
          // random
          final floors = (activeSlot['floors'] as List?)?.map((e) => (e as num).toInt()).toList() ?? [1];
          if (floors.isEmpty) continue;
          final shuffleMode = (activeSlot['shuffleMode'] as String?) ?? 'once';

          if (lastSlot != slotKey) {
            app.floor = floors[rng.nextInt(floors.length)];
            await widget.appService.saveConfig(app);
            await ss.setAutoMoveLastSlotKey(pkg, slotKey);
            await ss.setAutoMoveLastShuffleMs(pkg, now.millisecondsSinceEpoch);
            await ss.setAutoMoveShuffleCount(pkg, 1);
            changed = true;
          } else if (shuffleMode == 'repeat') {
            final repeatDays = (activeSlot['repeatDays'] as num?)?.toInt() ?? 0;
            final repeatHours = (activeSlot['repeatHours'] as num?)?.toInt() ?? 1;
            final repeatMins = (activeSlot['repeatMinutes'] as num?)?.toInt() ?? 0;
            final intervalMs = ((repeatDays * 24 * 60 + repeatHours * 60 + repeatMins) * 60 * 1000);
            if (intervalMs <= 0) continue;
            final lastShuffle = ss.autoMoveLastShuffleMs(pkg) ?? 0;
            if (now.millisecondsSinceEpoch - lastShuffle >= intervalMs) {
              app.floor = floors[rng.nextInt(floors.length)];
              await widget.appService.saveConfig(app);
              await ss.setAutoMoveLastShuffleMs(pkg, now.millisecondsSinceEpoch);
              changed = true;
            }
          } else if (shuffleMode == 'count') {
            final maxCount = (activeSlot['shuffleCount'] as num?)?.toInt() ?? 3;
            final currentCount = ss.autoMoveShuffleCount(pkg);
            if (currentCount < maxCount) {
              final slotDuration = activeEnd - activeStart;
              final intervalMin = slotDuration ~/ maxCount;
              if (intervalMin > 0) {
                final elapsed = nowMin - activeStart;
                final expectedCount = (elapsed ~/ intervalMin) + 1;
                if (expectedCount > currentCount) {
                  app.floor = floors[rng.nextInt(floors.length)];
                  await widget.appService.saveConfig(app);
                  await ss.setAutoMoveShuffleCount(pkg, expectedCount.clamp(0, maxCount));
                  await ss.setAutoMoveLastShuffleMs(pkg, now.millisecondsSinceEpoch);
                  changed = true;
                }
              }
            }
          }
        }
      }
    }

    if (changed && mounted) {
      _loadApps();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ctrl.dispose();
    _slideCtrl.dispose();
    _chargingCtrl.dispose();
    _mindfulTimer?.cancel();
    _ticker?.cancel();
    _widgetRefreshTimer?.cancel();
    _batchTimer?.cancel();
    _chargingCheckTimer?.cancel();
    _appChangeSub?.cancel();
    _homePressedSub?.cancel();
    _pageCtrl.dispose();
    _searchCtrl.dispose();
    _searchFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    // When keyboard closes (bottom inset = 0), unfocus the search field
    // Use a short delay so the focus system settles first
    Future.delayed(const Duration(milliseconds: 100), () {
      if (!mounted) return;
      final bottom = MediaQuery.of(context).viewInsets.bottom;
      if (bottom == 0 && _searchFocusNode.hasFocus) {
        _searchFocusNode.unfocus();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      if (_mindfulActive) {
        _mindfulCancelled = true;
        _mindfulTimer?.cancel();
        _mindfulTimer = null;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && Navigator.of(context).canPop()) {
            Navigator.of(context).maybePop();
          }
        });
      }
      // Mark that we left for an external app (includes home button from settings)
      _launchedExternalApp = true;
    }
    if (state == AppLifecycleState.resumed) {
      _loadHomeWidgets();
      _loadApps();
      // If we returned from an external app (home button pressed), go to HOME
      if (_launchedExternalApp && !_isInExternalScreen) {
        _launchedExternalApp = false;
        if (!_isAnimating) {
          if (_currentFloor != _homeFloor) {
            setState(() {
              _currentFloor = _homeFloor;
            });
          }
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _pageCtrl.hasClients) {
              _pageCtrl.jumpToPage(0);
            }
          });
        }
      }
      _launchedExternalApp = false;
    }
  }

  // ── build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final screenH = MediaQuery.of(context).size.height;

    return PopScope(
      canPop: _currentFloor == _homeFloor && !_selectionMode && !_reorderMode,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          if (_selectionMode) {
            setState(() {
              _selectionMode = false;
              _selectionInFavorites = false;
              _selectedPackages.clear();
            });
          } else if (_reorderMode) {
            setState(() => _reorderMode = false);
          } else if (_currentFloor > _homeFloor && !_isAnimating) {
            _goHome();
          }
        }
      },
      child: Scaffold(
        extendBody: true,
        backgroundColor: widget.settingsService.homeBackground ?? Colors.black,
        body: SafeArea(
          top: false,
          bottom: false,
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(color: Colors.white))
              : Stack(
                  children: [
                    Column(
                      children: [
                        // Emergency banner with stop button
                        if (_emergencyRemaining != null || (_emergencyEndTime != null && _emergencyEndTime!.isAfter(DateTime.now())))
                          Builder(builder: (ctx) {
                            final remaining = _emergencyEndTime != null && _emergencyEndTime!.isAfter(DateTime.now())
                                ? _emergencyEndTime!.difference(DateTime.now())
                                : _emergencyRemaining;
                            return Container(
                              width: double.infinity,
                              color: const Color(0xFF7B0000),
                              padding: EdgeInsets.fromLTRB(
                                  16,
                                  MediaQuery.of(context).padding.top + 6,
                                  8,
                                  6),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '緊急モード  残り ${remaining != null ? _fmt(remaining) : ""}  (${_emergency1FApps.length}アプリ)',
                                      style: const TextStyle(
                                          color: Colors.white, fontSize: 13),
                                    ),
                                  ),
                                  GestureDetector(
                                    onTap: () => _showEmergencyAddDialog(),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      margin: const EdgeInsets.only(right: 6),
                                      decoration: BoxDecoration(
                                        border: Border.all(color: Colors.white54),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Text('追加',
                                          style: TextStyle(color: Colors.white, fontSize: 11)),
                                    ),
                                  ),
                                  GestureDetector(
                                    onTap: () => _stopEmergencyMode(),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        border: Border.all(color: Colors.white54),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Text('停止',
                                          style: TextStyle(color: Colors.white, fontSize: 11)),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                        // Main content (search bar is embedded in floor content for all floors)
                        Expanded(
                          child: ((_currentFloor == _homeFloor || _currentFloor == 1) && !_isAnimating)
                              ? _buildHomeAnd1F()
                              : _buildFloorWithNav(screenH),
                        ),
                      ],
                    ),
                    if (_selectionMode)
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: _buildSelectionBar(),
                      ),
                    if (_activeIndexChar != null)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: Center(
                            child: Container(
                              width: 80,
                              height: 80,
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.9),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Center(
                                child: Text(
                                  _activeIndexChar!,
                                  style: const TextStyle(
                                    color: Colors.black,
                                    fontSize: 44,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}
