import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_caption_player/theme/app_theme.dart';
import 'package:live_caption_player/widgets/caption_audio_guide.dart';

void main() {
  testWidgets('explains internal-audio captions and can be dismissed', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var dismissed = false;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: CaptionAudioGuide(onDismiss: () => dismissed = true),
        ),
      ),
    );

    expect(find.text('Captions use internal audio'), findsOneWidget);
    expect(find.textContaining('No microphone access'), findsOneWidget);
    expect(find.text('Audio stays on-device'), findsOneWidget);
    expect(find.text('No microphone needed'), findsOneWidget);
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

  testWidgets('does not require room playback for captioning', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(body: CaptionAudioGuide(onDismiss: () {})),
      ),
    );

    expect(find.textContaining('audible room playback'), findsOneWidget);
  });
}
