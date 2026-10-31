import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_caption_player/theme/app_theme.dart';
import 'package:live_caption_player/widgets/player_controls.dart';

void main() {
  testWidgets('shows the current stage while opening media', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: PlayerControls(
            position: Duration.zero,
            duration: Duration.zero,
            volume: 1,
            hasMedia: false,
            isPlaying: false,
            isLoading: true,
            loadingLabel: 'Preparing playback…',
            enabled: true,
            onPickMedia: () {},
            onBack10: () {},
            onForward10: () {},
            onTogglePlay: () {},
            onVolumeChanged: (_) {},
            onSeekChanged: (_) {},
            onSeekEnd: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('Preparing playback…'), findsOneWidget);
    expect(find.text('Open File'), findsNothing);
  });

  testWidgets('shows the desktop playback controls and time tracker', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: PlayerControls(
            position: Duration.zero,
            duration: const Duration(minutes: 2, seconds: 5),
            volume: 0.5,
            hasMedia: true,
            isPlaying: true,
            isLoading: false,
            loadingLabel: 'Choose a media file…',
            enabled: true,
            onPickMedia: () {},
            onBack10: () {},
            onForward10: () {},
            onTogglePlay: () {},
            onVolumeChanged: (_) {},
            onSeekChanged: (_) {},
            onSeekEnd: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('Open File'), findsOneWidget);
    expect(find.text('-10s'), findsOneWidget);
    expect(find.text('Pause'), findsOneWidget);
    expect(find.text('+10s'), findsOneWidget);
    expect(find.text('00:00 / 02:05'), findsOneWidget);
    expect(find.byType(Slider), findsNWidgets(2));
  });
}
