import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/app_config.dart';
import 'firebase_options.dart';
import 'screens/auth_gate.dart';
import 'theme/app_theme.dart';
import 'theme/theme_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await dotenv.load(fileName: '.env');
  } catch (_) {
    // The app can still open and show setup instructions.
  }

  unawaited(_initializeFirebase());

  if (AppConfig.supabaseConfigured) {
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      anonKey: AppConfig.supabaseAnonKey,
    );
  }

  await ThemeController.instance.load();
  runApp(const ProjectBluePillApp());
}

Future<void> _initializeFirebase() async {
  if (!kIsWeb) return;

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    ).timeout(const Duration(seconds: 5));
  } catch (_) {
    // Firebase features are optional; Supabase remains the app auth/data source.
  }
}

class ProjectBluePillApp extends StatelessWidget {
  const ProjectBluePillApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<BluePillThemeChoice>(
      valueListenable: ThemeController.instance,
      builder: (context, themeChoice, _) {
        return MaterialApp(
          title: 'Project BluePill',
          debugShowCheckedModeBanner: false,
          themeAnimationDuration: const Duration(milliseconds: 450),
          themeAnimationCurve: Easing.emphasizedDecelerate,
          theme: themeChoice == BluePillThemeChoice.light
              ? AppTheme.blueWhite()
              : AppTheme.blueBlack(),
          home: const AuthGate(),
        );
      },
    );
  }
}
