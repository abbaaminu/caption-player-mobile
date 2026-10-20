import 'package:speech_to_text/speech_to_text.dart' as stt;

/// Thin wrapper around `speech_to_text` that keeps UI code free of plugin
/// details and exposes predictable listening state.
class SpeechService {
  SpeechService({stt.SpeechToText? speech})
    : _speech = speech ?? stt.SpeechToText();

  final stt.SpeechToText _speech;
  bool _isAvailable = false;
  bool _isListening = false;
  bool _isStarting = false;

  bool get isAvailable => _isAvailable;
  bool get isListening => _isListening;

  Future<bool> isSupported() => _speech.hasPermission;

  Future<bool> initSpeech({
    required void Function(String) onError,
    void Function(String status)? onStatus,
  }) async {
    _isAvailable = await _speech.initialize(
      onError: (error) {
        _isListening = false;
        onError(error.errorMsg);
      },
      onStatus: onStatus == null
          ? null
          : (status) {
              _isListening = status == 'listening';
              onStatus(status);
            },
    );
    return _isAvailable;
  }

  static String userFriendlyError(String message, {required bool isWeb}) {
    final normalized = message.toLowerCase();
    if (normalized.contains('not-allowed') ||
        normalized.contains('permission') ||
        normalized.contains('service-not-allowed')) {
      return isWeb
          ? 'The browser blocked speech recognition. Allow it for this site '
                'in browser settings, then retry. Web speech needs '
                'HTTPS or localhost and a supported browser such as Chrome or Edge.'
          : 'Speech-recognition permission was denied. Update app permissions '
                'in device settings, then retry.';
    }
    if (normalized.contains('audio-capture') ||
        normalized.contains('no microphone') ||
        normalized.contains('audio capture')) {
      return 'Speech recognition could not access audio input. Check app '
          'permissions and retry.';
    }
    if (normalized.contains('language-not-supported') ||
        normalized.contains('language_not_supported')) {
      return 'The selected speech-recognition language is not available on '
          'this device.';
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
    if (normalized.contains('busy')) {
      return 'Speech recognition is already starting. Wait a moment, then '
          'retry.';
    }
    return isWeb
        ? 'Live speech recognition could not start. Allow speech recognition, '
              'use HTTPS or localhost, and try a supported browser such as Chrome or Edge.'
        : 'Live speech recognition could not start. Check app permissions, '
              'then retry.';
  }

  /// Silence and explicit stops are normal and must not surface as errors.
  static bool isSilenceOrAbort(String message) {
    final normalized = message.toLowerCase();
    return normalized.contains('no-speech') ||
        normalized.contains('no_match') ||
        normalized.contains('aborted') ||
        normalized.contains('speech_timeout');
  }

  static bool isNetworkError(String message) {
    return message.toLowerCase().contains('network');
  }

  static bool isPermissionError(String message) {
    final normalized = message.toLowerCase();
    return normalized.contains('not-allowed') ||
        normalized.contains('permission') ||
        normalized.contains('service-not-allowed');
  }

  Future<void> startListening({
    required void Function(String) onResult,
    required void Function(String) onError,
  }) async {
    if (!_isAvailable) {
      onError('Speech recognition is not available.');
      return;
    }
    if (_isListening || _isStarting) {
      return;
    }

    _isStarting = true;
    try {
      await _speech.listen(
        onResult: (result) {
          final words = result.recognizedWords.trim();
          if (words.isNotEmpty) {
            onResult(words);
          }
        },
        listenOptions: stt.SpeechListenOptions(
          listenFor: const Duration(hours: 1),
          pauseFor: const Duration(seconds: 10),
          cancelOnError: false,
          partialResults: true,
        ),
      );
      _isListening = _speech.isListening;
    } catch (error) {
      _isListening = false;
      onError(error.toString());
    } finally {
      _isStarting = false;
    }
  }

  Future<void> stopListening() async {
    if (!_isListening && !_isAvailable) {
      return;
    }

    try {
      await _speech.stop();
    } finally {
      _isListening = false;
    }
  }
}
