import 'package:flutter/material.dart';

import '../config/app_config.dart';

/// Replaces Flutter's red error screen in release builds while keeping useful
/// diagnostics available during development.
class AppErrorFallback extends StatelessWidget {
  const AppErrorFallback({super.key, this.details});

  final FlutterErrorDetails? details;

  @override
  Widget build(BuildContext context) {
    final diagnostic = details?.exceptionAsString();

    return Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: const Color(0xFF0C0D10),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.error_outline,
                  color: Color(0xFFFFC247),
                  size: 40,
                ),
                const SizedBox(height: 16),
                const Text(
                  AppConfig.appName,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Something went wrong while drawing this screen. '
                  'Restart the app and try again.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
                if (diagnostic != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    diagnostic,
                    textAlign: TextAlign.center,
                    maxLines: 6,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 11,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
