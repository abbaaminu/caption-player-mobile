import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_caption_player/theme/app_theme.dart';
import 'package:live_caption_player/widgets/caption_audio_guide.dart';

void main() {
  testWidgets('explains why playback must stay audible and can be dismissed', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var dismissed = false;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: CaptionAudioGuide(
            isWeb: false,
            onDismiss: () => dismissed = true,
          ),
        ),
      ),
    );

    expect(find.text('Play audio for live captions'), findsOneWidget);
    expect(find.textContaining('device’s microphone'), findsOneWidget);
    expect(find.text('Keep playback audible'), findsOneWidget);
    expect(find.text('Speak clearly nearby'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.label == 'Live caption audio guidance',
      ),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('Dismiss caption guidance'));
    await tester.pump();

    expect(dismissed, isTrue);
    semantics.dispose();
  });

  testWidgets('uses browser-specific guidance on the web', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(body: CaptionAudioGuide(isWeb: true, onDismiss: () {})),
      ),
    );

    expect(find.textContaining('browser listens'), findsOneWidget);
    expect(find.textContaining('device’s microphone'), findsOneWidget);
  });
}
