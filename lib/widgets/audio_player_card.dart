import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/media_format.dart';

/// Large, readable presentation for audio-only media.
class AudioPlayerCard extends StatelessWidget {
  const AudioPlayerCard({
    super.key,
    required this.title,
    required this.isPlaying,
    this.duration,
  });

  final String title;
  final bool isPlaying;
  final Duration? duration;

  static const _barHeights = <double>[10, 18, 27, 15, 32, 20, 12];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 440),
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppTheme.surfaceRaised, AppTheme.surface],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 112,
            height: 112,
            decoration: BoxDecoration(
              color: AppTheme.accent.withValues(alpha: 0.12),
              shape: BoxShape.circle,
              border: Border.all(
                color: AppTheme.accent.withValues(alpha: 0.35),
                width: 1.5,
              ),
            ),
            child: const Icon(
              Icons.graphic_eq_rounded,
              color: AppTheme.accent,
              size: 62,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            isPlaying ? 'NOW PLAYING' : 'PAUSED',
            style: theme.textTheme.labelSmall?.copyWith(
              color: Colors.white54,
              letterSpacing: 2,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (duration != null && duration! > Duration.zero) ...[
            const SizedBox(height: 6),
            Text(
              formatPlaybackDuration(duration!),
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.white54),
            ),
          ],
          const SizedBox(height: 26),
          SizedBox(
            height: 34,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: List.generate(25, (index) {
                final height = _barHeights[index % _barHeights.length];
                return Container(
                  width: 4,
                  height: height,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.accent.withValues(
                      alpha: isPlaying ? 0.9 : 0.4,
                    ),
                    borderRadius: BorderRadius.circular(4),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}
