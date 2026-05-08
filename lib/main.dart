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

  // Wire SettingsService → native notification listener so OFF-mode apps
  // get their notifications dismissed in real-time, and sync the current
  // list once on startup (in case it changed since last launch).
  final nativeService = NativeService();
  settingsService.onOffPackagesChanged =
      (offPackages) => nativeService.setOffPackages(offPackages);
  await nativeService.setOffPackages(settingsService.notifOffApps);

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
        home: HomeScreen(
          appService: appService,
          settingsService: settingsService,
        ),
      ),
    );
  }
}
