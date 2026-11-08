import 'dart:ui' show DartPluginRegistrant;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'config/app_config.dart';
import 'screens/home_shell.dart';
import 'system_caption/system_caption_worker.dart';
import 'theme/app_theme.dart';
import 'widgets/app_error_fallback.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (kReleaseMode) {
    ErrorWidget.builder = (details) => AppErrorFallback(details: details);
  }
  runApp(const LiveCaptionPlayerApp());
}

/// Entry point of the headless Flutter engine hosted by the Android
/// `SystemCaptionService`. It has no UI: it loads the on-device Whisper model
/// and turns captured system audio into caption text.
///
/// Referenced by name from Kotlin, so it must stay top level in this file and
/// keep the entry-point annotation (release builds tree-shake it otherwise).
@pragma('vm:entry-point')
Future<void> systemCaptionMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  await SystemCaptionWorker().run();
}

class LiveCaptionPlayerApp extends StatelessWidget {
  const LiveCaptionPlayerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: const HomeShell(),
    );
  }
}
