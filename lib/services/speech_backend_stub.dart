import 'speech_backend.dart';

/// Web and unsupported-desktop fallback. The native FFmpeg/Vosk plugins do not
/// provide a working web implementation, so captions are rejected explicitly
/// instead of silently falling back to the microphone.
class UnsupportedSpeechBackend implements SpeechBackend {
  @override
  bool get isSupported => false;

  @override
  Future<bool> initialize({
    required void Function(SpeechStatus status) onStatus,
  }) async => false;

  @override
  Future<SpeechSession> createSession(String mediaPath) {
    throw const UnsupportedSpeechPlatformException();
  }

  @override
  Future<void> dispose() async {}
}

SpeechBackend createSpeechBackend() => UnsupportedSpeechBackend();
