import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_caption_player/theme/app_theme.dart';
import 'package:live_caption_player/widgets/caption_overlay.dart';

void main() {
  Future<void> pumpOverlay(WidgetTester tester, Widget overlay) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(body: Center(child: overlay)),
      ),
    );
  }

  testWidgets('renders nothing until there is a caption or a status', (
    tester,
  ) async {
    await pumpOverlay(tester, const CaptionOverlay(text: ''));

    expect(tester.getSize(find.byType(CaptionOverlay)).height, 0);
  });

  testWidgets('shows the caption status before the first phrase arrives', (
    tester,
  ) async {
    await pumpOverlay(
      tester,
      const CaptionOverlay(text: '', status: 'Downloading caption model · 40%'),
    );

    expect(find.text('Downloading caption model · 40%'), findsOneWidget);
    expect(find.byIcon(Icons.graphic_eq_rounded), findsOneWidget);
  });

  testWidgets('draws white caption text on a near-black rounded box', (
    tester,
  ) async {
    await pumpOverlay(tester, const CaptionOverlay(text: 'hello there'));

    final caption = tester.widget<Text>(find.text('hello there'));
    expect(caption.style?.color, Colors.white);
    expect(caption.maxLines, 2);
    expect(caption.textAlign, TextAlign.center);

    final box = tester.widget<DecoratedBox>(
      find
          .descendant(
            of: find.byType(CaptionOverlay),
            matching: find.byType(DecoratedBox),
          )
          .first,
    );
    final decoration = box.decoration as BoxDecoration;
    expect(decoration.color, const Color(0xE6000000));
    expect(decoration.borderRadius, BorderRadius.circular(12));
  });

  testWidgets('expands to show more lines when tapped', (tester) async {
    const longCaption =
        'This is a long caption line that needs more than two rows to be read '
        'completely on a narrow phone screen.';

    await pumpOverlay(
      tester,
      const SizedBox(
        width: 240,
        child: CaptionOverlay(text: longCaption),
      ),
    );

    expect(tester.widget<Text>(find.text(longCaption)).maxLines, 2);
    expect(find.byIcon(Icons.unfold_more_rounded), findsOneWidget);

    await tester.tap(find.text(longCaption));
    // The double-tap recognizer waits out the tap timeout before a single tap
    // toggles the box, the same as the system caption overlay.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(tester.widget<Text>(find.text(longCaption)).maxLines, 12);
    expect(find.byIcon(Icons.unfold_less_rounded), findsOneWidget);

    await tester.tap(find.text(longCaption));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(tester.widget<Text>(find.text(longCaption)).maxLines, 2);
  });
}
