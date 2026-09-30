import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'data/app_store.dart';
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
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, required this.store});
  final AppStore store;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Bá Khí Game Hub',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      fontFamily: 'Nunito', // If they added google_fonts, they can use it or we just fall back.
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFFFF9800),
        primary: const Color(0xFFFF9800),
        secondary: const Color(0xFF00BCD4),
        surface: const Color(0xFFFFF8E1), // Warm background
      ),
      scaffoldBackgroundColor: const Color(0xFFFFF8E1),
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          fontWeight: FontWeight.w900,
          color: Color(0xFFFF5722),
        ),
        headlineMedium: TextStyle(
          fontWeight: FontWeight.w900,
          color: Color(0xFFFF5722),
        ),
        titleLarge: TextStyle(
          fontWeight: FontWeight.w900,
          color: Color(0xFF607D8B),
        ),
        bodyLarge: TextStyle(fontWeight: FontWeight.w600, fontSize: 18),
        bodyMedium: TextStyle(fontWeight: FontWeight.w500, fontSize: 16),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          elevation: 6,
          shadowColor: const Color(0xFFFF5722),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFFE0E0E0), width: 1.5),
        ),
        margin: const EdgeInsets.only(bottom: 16),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFE0E0E0), width: 1.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFE0E0E0), width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFFF9800), width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Colors.redAccent, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 16,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        elevation: 10,
        titleTextStyle: const TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w900,
          color: Color(0xFFFF5722),
        ),
      ),
    ),
    home: AuthGate(store: store),
  );
}
