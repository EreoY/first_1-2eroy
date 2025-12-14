import 'package:flutter/material.dart';
import 'dart:io';
import 'package:window_manager/window_manager.dart';
import 'package:provider/provider.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'services/theme_service.dart';
import 'services/database_service.dart';
import 'providers/app_global_provider.dart';
import 'models/chat_message.dart';
import 'models/transaction.dart';
import 'ui/home_screen.dart';

import 'ui/splash_screen.dart';

import 'package:intl/date_symbol_data_local.dart'; // Import for locale initialization

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Locales
  await initializeDateFormatting('th_TH', null);
  
  // Initialize Database Service (Handles Hive init and box opening)
  await DatabaseService().init();

  // Initialize Theme Service
  final themeService = ThemeService();
  await themeService.loadSettings();
  
  if (!Platform.isAndroid && !Platform.isIOS) {
    await windowManager.ensureInitialized();
    WindowOptions windowOptions = const WindowOptions(
      size: Size(400, 800),
      center: true,
      backgroundColor: Colors.white,
      skipTaskbar: false,
      title: 'Offline AI Expense Tracker',
    );
    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => themeService),
        ChangeNotifierProvider(create: (_) => AppGlobalProvider()),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: context.watch<ThemeService>(),
      builder: (context, child) {
        final themeService = context.read<ThemeService>();
        const seedColor = Colors.indigo; // Fixed seed color

        return MaterialApp(
          title: 'AI Expense Tracker',
          debugShowCheckedModeBanner: false,
          themeMode: themeService.themeMode,
          theme: ThemeData(
            useMaterial3: true,
            fontFamily: 'Manrope',
            colorScheme: ColorScheme.fromSeed(
              seedColor: seedColor,
              brightness: Brightness.light,
              background: const Color(0xFFF8FAFC), // Alabaster / Slate 50
              surface: Colors.white,
              onSurface: const Color(0xFF0F172A), // Slate 900
              outlineVariant: const Color(0xFFE2E8F0), 
            ),
            scaffoldBackgroundColor: const Color(0xFFF8FAFC),
            cardTheme: const CardThemeData(
              color: Colors.white,
              elevation: 0,
              margin: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            ),
            appBarTheme: const AppBarTheme(
              backgroundColor: Color(0xFFF8FAFC),
              foregroundColor: Color(0xFF0F172A),
              elevation: 0,
              centerTitle: true,
              scrolledUnderElevation: 0,
              surfaceTintColor: Colors.transparent,
            ),
            bottomNavigationBarTheme: const BottomNavigationBarThemeData(
              backgroundColor: Colors.white,
              selectedItemColor: seedColor,
              unselectedItemColor: Colors.grey,
              type: BottomNavigationBarType.fixed,
              elevation: 8,
            ),
            dividerTheme: const DividerThemeData(
              color: Color(0xFFE2E8F0),
              space: 1,
            ),
          ),
          darkTheme: ThemeData(
            useMaterial3: true,
            fontFamily: 'Manrope',
            colorScheme: ColorScheme.fromSeed(
              seedColor: seedColor,
              brightness: Brightness.dark,
              background: const Color(0xFF0F172A), // Midnight Blue / Slate 900
              surface: const Color(0xFF1E293B), // Slate 800
              onSurface: const Color(0xFFF8FAFC), // Slate 50
              outlineVariant: const Color(0xFF334155),
            ),
            scaffoldBackgroundColor: const Color(0xFF0F172A),
            cardTheme: CardThemeData(
              color: const Color(0xFF1E293B),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
                side: const BorderSide(color: Color(0xFF334155), width: 1),
              ),
              shadowColor: Colors.black.withValues(alpha: 0.4),
            ),
            appBarTheme: const AppBarTheme(
              backgroundColor: Color(0xFF0F172A),
              foregroundColor: Colors.white,
              elevation: 0,
              centerTitle: true,
              scrolledUnderElevation: 0,
            ),
            bottomNavigationBarTheme: const BottomNavigationBarThemeData(
              backgroundColor: Color(0xFF0F172A),
              selectedItemColor: Colors.white,
              unselectedItemColor: Colors.grey,
              type: BottomNavigationBarType.fixed,
              elevation: 0,
            ),
            dividerTheme: const DividerThemeData(
              color: Color(0xFF334155),
              space: 1,
            ),
          ),
          home: const SplashScreen(),
        );
      },
    );
  }
}
