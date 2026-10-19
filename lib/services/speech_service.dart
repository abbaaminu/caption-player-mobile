import 'package:speech_to_text/speech_to_text.dart' as stt;

class SpeechService {
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isAvailable = false;

  Future<bool> initSpeech({required Function(String) onError}) async {
    _isAvailable = await _speech.initialize(
      onError: (error) => onError(error.errorMsg),
    );
    return _isAvailable;
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