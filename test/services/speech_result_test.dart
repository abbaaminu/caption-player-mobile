import 'package:flutter_test/flutter_test.dart';
import 'package:live_caption_player/services/speech_backend.dart';

void main() {
  group('VoskResultParser', () {
    test('reads partial results', () {
      final update = VoskResultParser.parse(
        '{"partial":"hello wor"}',
        isFinal: false,
      );

      expect(update.partialText, 'hello wor');
      expect(update.finalText, isEmpty);
    });

    test('reads finalized results', () {
      final update = VoskResultParser.parse(
        '{"text":"hello world"}',
        isFinal: true,
      );

      expect(update.finalText, 'hello world');
      expect(update.partialText, isEmpty);
    });

    test('falls back to word-level results', () {
      final update = VoskResultParser.parse(
        '{"result":[{"word":"hello"},{"word":"world"}],"text":""}',
        isFinal: true,
      );

      expect(update.finalText, 'hello world');
    });

    test('accepts plain text from a recognizer', () {
      final update = VoskResultParser.parse('plain caption', isFinal: true);

      expect(update.finalText, 'plain caption');
    });

    test('ignores empty and malformed empty documents', () {
      expect(VoskResultParser.parse('', isFinal: true).isEmpty, isTrue);
      expect(VoskResultParser.parse('{}', isFinal: false).isEmpty, isTrue);
    });
  });
}
