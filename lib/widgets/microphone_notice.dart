import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Explains how microphone-based live captions differ from built-in captions.
class MicrophoneNotice extends StatelessWidget {
  const MicrophoneNotice({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.mic_none_rounded, size: 20, color: AppTheme.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Live captions listen through your device microphone. They do '
              'not read the media file’s built-in audio track, so keep playback '
              'audible near the microphone.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.white70,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
