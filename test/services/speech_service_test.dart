import 'package:flutter_test/flutter_test.dart';
import 'package:live_caption_player/services/speech_service.dart';

void main() {
  group('SpeechService.userFriendlyError', () {
    test('explains browser speech-recognition permission denial', () {
      final message = SpeechService.userFriendlyError(
        'not-allowed',
        isWeb: true,
      );

      expect(message, contains('browser blocked speech recognition'));
      expect(message, contains('HTTPS or localhost'));
      expect(message, contains('Chrome or Edge'));
    });

    test('explains device speech-recognition permission denial', () {
      final message = SpeechService.userFriendlyError(
        'service-not-allowed',
        isWeb: false,
      );

      expect(message, contains('device settings'));
      expect(message, isNot(contains('microphone')));
      expect(message, isNot(contains('browser')));
    });

    test('explains unsupported web speech recognition', () {
      final message = SpeechService.userFriendlyError(
        'speech_not_supported',
        isWeb: true,
      );

      expect(message, contains('current version of Chrome or Edge'));
    });

    test('explains unavailable audio input', () {
      final message = SpeechService.userFriendlyError(
        'audio-capture',
        isWeb: false,
      );

      expect(message, contains('could not access audio input'));
    });

    test('explains network and busy failures', () {
      expect(
        SpeechService.userFriendlyError('network', isWeb: false),
        contains('internet connection'),
      );
      expect(
        SpeechService.userFriendlyError('busy', isWeb: false),
        contains('already starting'),
      );
    });

    test('falls back to a generic recovery message', () {
      final message = SpeechService.userFriendlyError(
        'unexpected-failure',
        isWeb: false,
      );

      expect(message, contains('Check app permissions'));
    });
  });

  group('SpeechService error classification', () {
    test('treats silence and explicit stops as normal', () {
      for (final message in <String>[
        'no-speech',
        'no_match',
        'aborted',
        'speech_timeout',
      ]) {
        expect(
          SpeechService.isSilenceOrAbort(message),
          isTrue,
          reason: message,
        );
      }
      expect(SpeechService.isSilenceOrAbort('network'), isFalse);
    });

    test('recognizes permission failures', () {
      expect(SpeechService.isPermissionError('not-allowed'), isTrue);
      expect(SpeechService.isPermissionError('Permission denied'), isTrue);
      expect(SpeechService.isPermissionError('network'), isFalse);
    });

    test('recognizes network failures', () {
      expect(SpeechService.isNetworkError('Network error'), isTrue);
      expect(SpeechService.isNetworkError('audio-capture'), isFalse);
    });
  });
}
