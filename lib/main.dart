import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'config/app_config.dart';
import 'screens/player_screen.dart';
import 'theme/app_theme.dart';
import 'widgets/app_error_fallback.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (kReleaseMode) {
    ErrorWidget.builder = (details) => AppErrorFallback(details: details);
  }
  runApp(const LiveCaptionPlayerApp());
}

class LiveCaptionPlayerApp extends StatelessWidget {
  const LiveCaptionPlayerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: const PlayerScreen(),
    );
  }
}
