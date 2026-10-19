import 'package:speech_to_text/speech_to_text.dart' as stt;

class SpeechService {
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isAvailable = false;

  Future<bool> isSupported() => _speech.hasPermission;

  Future<bool> initSpeech({required Function(String) onError}) async {
    _isAvailable = await _speech.initialize(
      onError: (error) => onError(error.errorMsg),
    );
    return _isAvailable;
  }

  static String userFriendlyError(String message, {required bool isWeb}) {
    final normalized = message.toLowerCase();
    if (normalized.contains('not-allowed') ||
        normalized.contains('permission') ||
        normalized.contains('service-not-allowed')) {
      return isWeb
          ? 'The browser blocked microphone access. Allow microphone access '
                'for this site in browser settings, then retry. Web speech needs '
                'HTTPS or localhost and a supported browser such as Chrome or Edge.'
          : 'Microphone or speech-recognition access was denied. Allow both '
                'permissions in device settings, then retry.';
    }
    if (normalized.contains('audio-capture') ||
        normalized.contains('no microphone') ||
        normalized.contains('audio capture')) {
      return 'No microphone is available. Connect or enable a microphone, '
          'allow access, and retry.';
    }
    if (normalized.contains('not supported') ||
        normalized.contains('speech_not_supported') ||
        normalized.contains('unsupported')) {
      return isWeb
          ? 'This browser does not support live speech recognition. Try a '
                'current version of Chrome or Edge.'
          : 'Live speech recognition is not supported on this device.';
    }
    if (normalized.contains('network')) {
      return 'Speech recognition could not connect to its service. Check your '
          'internet connection and retry.';
    }
    return isWeb
        ? 'Live speech recognition could not start. Allow microphone access, '
              'use HTTPS or localhost, and try a supported browser such as Chrome or Edge.'
        : 'Live speech recognition could not start. Check microphone and '
              'speech-recognition permissions, then retry.';
  }

  Future<void> startListening({
    required Function(String) onResult,
    required Function(String) onError,
  }) async {
    if (!_isAvailable) {
      onError('Speech recognition is not available.');
      return;
    }
    try {
      await _speech.listen(
        onResult: (result) {
          if (result.recognizedWords.isNotEmpty) {
            onResult(result.recognizedWords);
          }
        },
        listenOptions: stt.SpeechListenOptions(
          listenFor: const Duration(hours: 1),
          pauseFor: const Duration(seconds: 10),
          cancelOnError: false,
          partialResults: true,
        ),
      );
    } catch (error) {
      onError(error.toString());
    }
  }

  Future<void> stopListening() => _speech.stop();
}
