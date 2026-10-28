import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'data/app_store.dart';
import 'data/chat_notifier.dart';
import 'ui/app_theme.dart';
import 'ui/app_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  var url = const String.fromEnvironment('SUPABASE_URL');
  var key = const String.fromEnvironment('SUPABASE_ANON_KEY');
  SupabaseClient? client;
  String? startupError;
  if (url.isEmpty || key.isEmpty) {
    try {
      final localConfig = Map<String, dynamic>.from(
        jsonDecode(await rootBundle.loadString('config/supabase.json')),
      );
      url = localConfig['SUPABASE_URL']?.toString().trim() ?? '';
      key = localConfig['SUPABASE_ANON_KEY']?.toString().trim() ?? '';
    } catch (_) {
      // A distributable build may intentionally omit the local config file.
    }
  }
  if (url.isNotEmpty && key.isNotEmpty) {
    try {
      await Supabase.initialize(url: url, publishableKey: key);
      client = Supabase.instance.client;
    } catch (_) {
      startupError =
          'Chưa khởi tạo được dịch vụ online. Các game vẫn hoạt động trên máy.';
    }
  } else {
    startupError =
        'Chưa tìm thấy cấu hình Supabase. Hãy kiểm tra config/supabase.json.';
  }
  final store = AppStore(
    await SharedPreferences.getInstance(),
    client: client,
    startupError: startupError,
  );
  runApp(MyApp(store: store));
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
