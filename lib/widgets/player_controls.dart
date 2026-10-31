import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/media_format.dart';
import 'custom_slider.dart';

/// Playback controls are kept separate from player and trial state.
class PlayerControls extends StatelessWidget {
  const PlayerControls({
    super.key,
    required this.position,
    required this.duration,
    required this.volume,
    required this.hasMedia,
    required this.isPlaying,
    required this.isLoading,
    this.loadingLabel = 'Opening…',
    required this.enabled,
    required this.onPickMedia,
    required this.onBack10,
    required this.onForward10,
    required this.onTogglePlay,
    required this.onVolumeChanged,
    required this.onSeekChanged,
    required this.onSeekEnd,
  });

  final Duration position;
  final Duration duration;
  final double volume;
  final bool hasMedia;
  final bool isPlaying;
  final bool isLoading;
  final String loadingLabel;
  final bool enabled;
  final VoidCallback onPickMedia;
  final VoidCallback onBack10;
  final VoidCallback onForward10;
  final VoidCallback onTogglePlay;
  final ValueChanged<double> onVolumeChanged;
  final ValueChanged<double> onSeekChanged;
  final ValueChanged<double> onSeekEnd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canControlMedia = enabled && hasMedia;
    final durationMs = duration.inMilliseconds.toDouble();
    final volumeIcon = volume == 0
        ? Icons.volume_off_rounded
        : Icons.volume_up_rounded;

    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppTheme.background,
        border: Border(top: BorderSide(color: Color(0xFF242424))),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                OutlinedButton.icon(
                  onPressed: enabled && !isLoading ? onPickMedia : null,
                  icon: isLoading
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.folder_open_rounded),
                  label: Text(isLoading ? loadingLabel : 'Open File'),
                ),
                TextButton.icon(
                  onPressed: canControlMedia ? onBack10 : null,
                  icon: const Icon(Icons.replay_10_rounded),
                  label: const Text('-10s'),
                ),
                FilledButton.icon(
                  onPressed: canControlMedia ? onTogglePlay : null,
                  icon: Icon(
                    isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  ),
                  label: Text(isPlaying ? 'Pause' : 'Play'),
                ),
                TextButton.icon(
                  onPressed: canControlMedia ? onForward10 : null,
                  icon: const Icon(Icons.forward_10_rounded),
                  label: const Text('+10s'),
                ),
                SizedBox(
                  width: 150,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(volumeIcon, color: Colors.white70, size: 20),
                      Expanded(
                        child: Slider(
                          value: volume.clamp(0.0, 1.0),
                          min: 0,
                          max: 1,
                          onChanged: canControlMedia ? onVolumeChanged : null,
                          semanticFormatterCallback: (value) =>
                              'Volume ${(value * 100).round()} percent',
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '${formatPlaybackDuration(position)} / '
                  '${formatPlaybackDuration(duration)}',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: Colors.white70,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
            CustomSlider(
              value: position.inMilliseconds.toDouble(),
              max: durationMs,
              enabled: canControlMedia && durationMs > 0,
              onChanged: onSeekChanged,
              onChangeEnd: onSeekEnd,
              semanticFormatterCallback: (value) =>
                  formatPlaybackDuration(Duration(milliseconds: value.round())),
            ),
          ],
        ),
      ),
    );
  }
}
