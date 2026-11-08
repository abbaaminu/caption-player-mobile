import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../theme/app_theme.dart';
import '../utils/media_format.dart';

/// First-run surface before the user chooses a media file.
class EmptyPlayerView extends StatelessWidget {
  const EmptyPlayerView({
    super.key,
    required this.onChooseMedia,
    this.isLoading = false,
    this.loadingLabel = 'Opening…',
  });

  final VoidCallback onChooseMedia;
  final bool isLoading;
  final String loadingLabel;

  String get _supportedFormats =>
      supportedMediaExtensions.map((ext) => ext.toUpperCase()).join(' · ');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                'assets/app_icon.png',
                width: 92,
                height: 92,
                errorBuilder: (_, _, _) => const Icon(
                  Icons.closed_caption_rounded,
                  size: 84,
                  color: AppTheme.accent,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                AppConfig.appName,
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                AppConfig.tagline,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.white70,
                ),
              ),
              const SizedBox(height: 28),
              ElevatedButton.icon(
                onPressed: isLoading ? null : onChooseMedia,
                icon: isLoading
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.video_library_outlined),
                label: Text(isLoading ? loadingLabel : 'Open media'),
              ),
              const SizedBox(height: 14),
              Text(
                _supportedFormats,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.white38,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
