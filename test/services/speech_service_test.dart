import 'package:flutter_test/flutter_test.dart';
import 'package:premium_live_caption/services/speech_service.dart';

void main() {
  group('SpeechService.userFriendlyError', () {
    test('explains browser microphone permission denial', () {
      final message = SpeechService.userFriendlyError(
        'not-allowed',
        isWeb: true,
      );

      expect(message, contains('browser blocked microphone access'));
      expect(message, contains('HTTPS or localhost'));
      expect(message, contains('Chrome or Edge'));
    });

    test('explains unsupported web speech recognition', () {
      final message = SpeechService.userFriendlyError(
        'speech_not_supported',
        isWeb: true,
      );

      expect(message, contains('current version of Chrome or Edge'));
    });

    test('explains missing microphone hardware', () {
      final message = SpeechService.userFriendlyError(
        'audio-capture',
        isWeb: false,
      );

      expect(message, contains('No microphone is available'));
    });
  });
}
