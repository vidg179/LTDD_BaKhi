import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/app_store.dart';
import 'data/chat_notifier.dart';
import 'ui/app_theme.dart';
import 'ui/app_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  final preferences = await SharedPreferences.getInstance();
  // The group's own backend; see backend/ (BaKhi_API).
  final api = ApiClient(preferences);
  final store = AppStore(preferences, api: api);
  runApp(MyApp(store: store));
  // A phone that slept may have lost the realtime connection silently.
  AppLifecycleListener(onResume: api.reconnect);
  store.syncResults();
  // Notifications are a convenience: a failure must not stop the app.
  unawaited(ChatNotifier(store).start().catchError((Object _) {}));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, required this.store});
  final AppStore store;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Bá Khí Game Hub',
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light,
    // Deliberately light-only: game boards, stickers and tiles use fixed
    // colours chosen for a light background. A dark theme would need those
    // moved into the colour scheme first.
    themeMode: ThemeMode.light,
    home: AuthGate(store: store),
  );
}
