import 'package:flutter/material.dart';
import '../../services/app_service.dart';
import '../../services/native_service.dart';
import '../../services/settings_service.dart';
import '../home/home_screen.dart';

/// First-launch screen that requests every system-level permission Layered
/// Launcher needs in one place. Without this the user gets nagged piecemeal
/// (notification access banner on home, usage-stats prompt when opening
/// screen time, device-admin prompt when binding the lock-screen gesture,
/// etc.) which Haruki specifically asked to consolidate.
class OnboardingScreen extends StatefulWidget {
  final AppService appService;
  final SettingsService settingsService;

  const OnboardingScreen({
    super.key,
    required this.appService,
    required this.settingsService,
  });

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with WidgetsBindingObserver {
  final _native = NativeService();

  bool _notifGranted = false;
  bool _usageGranted = false;
  bool _adminGranted = false;
  bool _exactAlarmGranted = true;
  bool _postNotifGranted = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshAll();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshAll();
    }
  }

  Future<void> _refreshAll() async {
    final notif = await _native.isNotificationServiceEnabled();
    final usage = await _native.isUsageStatsPermissionGranted();
    final admin = await _native.isDeviceAdminEnabled();
    final alarm = await _native.canScheduleExactAlarms();
    final postNotif = await _native.isPostNotificationsGranted();
    if (!mounted) return;
    setState(() {
      _notifGranted = notif;
      _usageGranted = usage;
      _adminGranted = admin;
      _exactAlarmGranted = alarm;
      _postNotifGranted = postNotif;
    });
  }

  Future<void> _finish() async {
    await widget.settingsService.setOnboardingCompleted(true);
    // Re-push the quick-launcher notification so it lands in the
    // shade even if POST_NOTIFICATIONS was granted during onboarding
    // (the initial boot-time post would have silently failed).
    final ss = widget.settingsService;
    if (ss.onQuickLauncherChanged != null) {
      final apps = await widget.appService.resolveQuickLauncherApps(
        ss.quickLauncherSource,
        customPackages: ss.quickLauncherCustomApps,
      );
      await ss.onQuickLauncherChanged!.call(
        ss.quickLauncherEnabled,
        ss.quickLauncherProminent,
        ss.quickLauncherShowDividers,
        apps,
      );
    }
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => HomeScreen(
        appService: widget.appService,
        settingsService: widget.settingsService,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final allRequired = _notifGranted && _usageGranted;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              const Text(
                'Layered Launcher へようこそ',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'すべての機能を使うには以下の権限が必要です。\n'
                '一度に許可しておくと、後で個別に求められません。',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 24),
              Expanded(
                child: ListView(
                  children: [
                    _section('必須'),
                    _permissionTile(
                      title: '通知へのアクセス',
                      subtitle: '通知のブロック・バッチ処理・履歴に必要',
                      granted: _notifGranted,
                      onGrant: _native.openNotificationAccessSettings,
                    ),
                    _permissionTile(
                      title: '使用状況へのアクセス',
                      subtitle: 'スクリーンタイム計測・最近使ったアプリ表示に必要',
                      granted: _usageGranted,
                      onGrant: _native.openUsageStatsSettings,
                    ),
                    const SizedBox(height: 8),
                    _section('推奨'),
                    _permissionTile(
                      title: '通知の表示',
                      subtitle: 'クイック起動などの通知を表示するために必要 (Android 13+)',
                      granted: _postNotifGranted,
                      onGrant: () async {
                        // Try the runtime prompt first. If the user
                        // previously denied it with "don't ask again"
                        // the dialog won't reappear, so also expose
                        // the system settings shortcut as a fallback.
                        await _native.requestPostNotifications();
                        await Future.delayed(const Duration(milliseconds: 300));
                        await _refreshAll();
                        if (!_postNotifGranted && mounted) {
                          await _native.openAppDetailSettings();
                        }
                      },
                    ),
                    _permissionTile(
                      title: 'デバイス管理者',
                      subtitle: '画面ロックジェスチャ（下スワイプ等）に必要',
                      granted: _adminGranted,
                      onGrant: _native.openDeviceAdminSettings,
                    ),
                    _permissionTile(
                      title: '正確なアラーム',
                      subtitle: 'バッチ通知のスケジュール配信に必要 (Android 12+)',
                      granted: _exactAlarmGranted,
                      onGrant: _native.openExactAlarmSettings,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              if (!allRequired)
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text(
                    '※ 必須権限を許可していない場合、関連機能は無効になります。',
                    style: TextStyle(color: Colors.orangeAccent, fontSize: 11),
                  ),
                ),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  style: TextButton.styleFrom(
                    backgroundColor: allRequired
                        ? Colors.tealAccent.withOpacity(0.15)
                        : Colors.white.withOpacity(0.05),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  onPressed: _finish,
                  child: Text(
                    allRequired ? '完了して開始' : 'スキップして開始',
                    style: TextStyle(
                      color: allRequired ? Colors.tealAccent : Colors.white70,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
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

  Widget _section(String label) => Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 8),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white54,
            fontSize: 11,
            letterSpacing: 1.2,
          ),
        ),
      );

  Widget _permissionTile({
    required String title,
    required String subtitle,
    required bool granted,
    required Future<void> Function() onGrant,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: granted
                  ? Colors.tealAccent.withOpacity(0.15)
                  : Colors.white.withOpacity(0.05),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(
              granted ? Icons.check : Icons.lock_open,
              size: 16,
              color: granted ? Colors.tealAccent : Colors.white54,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          if (!granted)
            TextButton(
              onPressed: () async {
                await onGrant();
              },
              child: const Text(
                '許可する',
                style: TextStyle(color: Colors.tealAccent, fontSize: 12),
              ),
            )
          else
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                '許可済み',
                style: TextStyle(color: Colors.tealAccent, fontSize: 11),
              ),
            ),
        ],
      ),
    );
  }
}
