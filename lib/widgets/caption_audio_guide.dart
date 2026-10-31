import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Explains that local live captions use the media file's internal audio.
///
/// Shown while captions are on until the viewer dismisses it.
class CaptionAudioGuide extends StatelessWidget {
  const CaptionAudioGuide({super.key, required this.onDismiss});

  /// Called when the viewer closes the notice.
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: 'Live caption audio guidance',
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
        decoration: BoxDecoration(
          color: AppTheme.surfaceRaised,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppTheme.accent.withValues(alpha: 0.14),
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppTheme.accent.withValues(alpha: 0.35),
                ),
              ),
              child: const Icon(
                Icons.subtitles_rounded,
                size: 20,
                color: AppTheme.accent,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Captions use internal audio',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'The media audio is transcribed on this device. No '
                    'microphone access or audible room playback is needed.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.white.withValues(alpha: 0.72),
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      _GuideHint(
                        icon: Icons.audio_file_rounded,
                        label: 'Audio stays on-device',
                      ),
                      _GuideHint(
                        icon: Icons.mic_off_rounded,
                        label: 'No microphone needed',
                      ),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: onDismiss,
              tooltip: 'Dismiss caption guidance',
              visualDensity: VisualDensity.compact,
              iconSize: 18,
              color: Colors.white.withValues(alpha: 0.6),
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

class _GuideHint extends StatelessWidget {
  const _GuideHint({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: AppTheme.accent),
          const SizedBox(width: 5),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Colors.white.withValues(alpha: 0.82),
            ),
          ),
        ],
      ),
    );
  }
}
