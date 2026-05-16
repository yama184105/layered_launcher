import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'l10n/generated/app_localizations.dart';
import 'models/app_config.dart';
import 'services/app_service.dart';
import 'services/native_service.dart';
import 'services/settings_service.dart';
import 'screens/home/home_screen.dart';
import 'screens/onboarding/onboarding_screen.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Hive.initFlutter();
  Hive.registerAdapter(AppConfigAdapter());

  const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
  const initSettings = InitializationSettings(android: androidSettings);
  await flutterLocalNotificationsPlugin.initialize(initSettings);

  final appService = AppService();
  await appService.init();

  final settingsService = SettingsService();
  await settingsService.init();

  // Wire SettingsService → native notification listener so the policy
  // (default mode + OFF set + allow set) and batch groups stay in sync
  // after every change. Push the current state once on startup too in
  // case anything changed since last launch.
  final nativeService = NativeService();
  settingsService.onNotifPolicyChanged = (def, off, allow) =>
      nativeService.setNotifPolicy(
        defaultMode: def,
        offPackages: off,
        allowPackages: allow,
      );
  settingsService.onBatchGroupsChanged =
      (groups) => nativeService.setBatchGroups(groups);
  await nativeService.setNotifPolicy(
    defaultMode: settingsService.defaultNotifMode,
    offPackages: settingsService.notifOffApps,
    allowPackages: settingsService.notifAllowApps,
  );
  await nativeService.setBatchGroups(settingsService.batchGroups);

  // Persistent quick-launcher notification. The hook resolves the app
  // list inline so the settings UI can just flip the toggle / change
  // source without knowing about AppService.
  settingsService.onQuickLauncherChanged =
      (enabled, prominent, showDividers, apps) =>
          nativeService.setQuickLauncherConfig(
            enabled: enabled,
            prominent: prominent,
            showDividers: showDividers,
            apps: apps,
          );
  final quickLauncherApps = await appService.resolveQuickLauncherApps(
    settingsService.quickLauncherSource,
    customPackages: settingsService.quickLauncherCustomApps,
  );
  await nativeService.setQuickLauncherConfig(
    enabled: settingsService.quickLauncherEnabled,
    prominent: settingsService.quickLauncherProminent,
    showDividers: settingsService.quickLauncherShowDividers,
    apps: quickLauncherApps,
  );

  runApp(LayeredLauncherApp(
    appService: appService,
    settingsService: settingsService,
  ));
}

class LayeredLauncherApp extends StatelessWidget {
  final AppService appService;
  final SettingsService settingsService;

  const LayeredLauncherApp({
    super.key,
    required this.appService,
    required this.settingsService,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Locale?>(
      valueListenable: settingsService.localeNotifier,
      builder: (context, locale, _) => MaterialApp(
        title: 'LayeredLauncher',
        debugShowCheckedModeBanner: false,
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: Colors.black,
          colorScheme: const ColorScheme.dark(
            primary: Colors.white,
            surface: Colors.black,
          ),
        ),
        home: settingsService.hasCompletedOnboarding
            ? HomeScreen(
                appService: appService,
                settingsService: settingsService,
              )
            : OnboardingScreen(
                appService: appService,
                settingsService: settingsService,
              ),
      ),
    );
  }
}
