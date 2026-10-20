import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/media_format.dart';
import 'custom_slider.dart';

/// Playback and caption controls. All callbacks are owned by the player screen
/// so this widget stays free of plugin and trial logic.
class PlayerControls extends StatelessWidget {
  const PlayerControls({
    super.key,
    required this.position,
    required this.duration,
    required this.hasMedia,
    required this.isPlaying,
    required this.isLoading,
    required this.captionsEnabled,
    required this.isRequestingCaptions,
    required this.onPickMedia,
    required this.onBack10,
    required this.onForward10,
    required this.onTogglePlay,
    required this.onSeekChanged,
    required this.onSeekEnd,
    required this.onToggleCaptions,
    this.enabled = true,
  });

  final Duration position;
  final Duration duration;
  final bool hasMedia;
  final bool isPlaying;
  final bool isLoading;
  final bool captionsEnabled;
  final bool isRequestingCaptions;
  final bool enabled;
  final VoidCallback onPickMedia;
  final VoidCallback onBack10;
  final VoidCallback onForward10;
  final VoidCallback onTogglePlay;
  final ValueChanged<double> onSeekChanged;
  final ValueChanged<double> onSeekEnd;
  final VoidCallback onToggleCaptions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canControlMedia = enabled && hasMedia;
    final durationMs = duration.inMilliseconds.toDouble();

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const SizedBox(width: 6),
                Text(
                  formatPlaybackDuration(position),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: Colors.white70,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                Expanded(
                  child: CustomSlider(
                    value: position.inMilliseconds.toDouble(),
                    max: durationMs,
                    enabled: canControlMedia && durationMs > 0,
                    onChanged: onSeekChanged,
                    onChangeEnd: onSeekEnd,
                    semanticFormatterCallback: (value) =>
                        formatPlaybackDuration(
                          Duration(milliseconds: value.round()),
                        ),
                  ),
                ),
                Text(
                  formatPlaybackDuration(duration),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: Colors.white70,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(width: 6),
              ],
            ),
            Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 6,
              children: [
                IconButton(
                  tooltip: 'Open video or audio',
                  onPressed: enabled && !isLoading ? onPickMedia : null,
                  icon: isLoading
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.video_library_outlined),
                ),
                IconButton(
                  tooltip: 'Back 10 seconds',
                  onPressed: canControlMedia ? onBack10 : null,
                  icon: const Icon(Icons.replay_10_rounded),
                ),
                IconButton.filled(
                  tooltip: isPlaying ? 'Pause' : 'Play',
                  onPressed: canControlMedia ? onTogglePlay : null,
                  iconSize: 30,
                  icon: Icon(
                    isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  ),
                ),
                IconButton(
                  tooltip: 'Forward 10 seconds',
                  onPressed: canControlMedia ? onForward10 : null,
                  icon: const Icon(Icons.forward_10_rounded),
                ),
                IconButton(
                  tooltip: captionsEnabled
                      ? 'Turn off live captions'
                      : 'Turn on live captions',
                  onPressed: enabled && !isRequestingCaptions
                      ? onToggleCaptions
                      : null,
                  color: captionsEnabled ? AppTheme.accent : Colors.white,
                  icon: isRequestingCaptions
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          captionsEnabled
                              ? Icons.mic_rounded
                              : Icons.mic_off_rounded,
                        ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
