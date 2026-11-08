import 'package:flutter_test/flutter_test.dart';
import 'package:live_caption_player/utils/activation_link.dart';

void main() {
  group('parseActivationLink', () {
    test('extracts a key from the custom scheme', () {
      final result = parseActivationLink(
        'captionplayer://activate?key=CLP-123',
      );

      expect(result, isA<ActivationLinkKey>());
      expect((result as ActivationLinkKey).key, 'CLP-123');
    });

    test('matches scheme and host case-insensitively and trims the key', () {
      final result = parseActivationLink(
        '  CaptionPlayer://Activate?key=%20CLP-ABC%20  ',
      );

      expect(result, isA<ActivationLinkKey>());
      expect((result as ActivationLinkKey).key, 'CLP-ABC');
    });

    test('accepts a path-only activate link', () {
      final result = parseActivationLink('captionplayer:/activate?key=CLP-9');

      expect(result, isA<ActivationLinkKey>());
      expect((result as ActivationLinkKey).key, 'CLP-9');
    });

    test('reports an activation link without a key', () {
      expect(
        parseActivationLink('captionplayer://activate'),
        isA<ActivationLinkMissingKey>(),
      );
      expect(
        parseActivationLink('captionplayer://activate?key=%20%20'),
        isA<ActivationLinkMissingKey>(),
      );
    });

    test('ignores unrelated or malformed links', () {
      for (final link in <String>[
        '',
        '   ',
        'https://caption.stackbuildco.com/activate?key=CLP-123',
        'captionplayer://other?key=CLP-123',
        'captionplayer:/not-activate?key=CLP-123',
      ]) {
        expect(
          parseActivationLink(link),
          isA<ActivationLinkIgnored>(),
          reason: link,
        );
      }
    });
  });
}
