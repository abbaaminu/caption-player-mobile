import 'dart:convert';
import 'dart:typed_data';

/// Progress reported while preparing on-device captions.
enum SpeechStatus {
  downloadingModel,
  loadingModel,
  extractingAudio,
  transcribing,
}

/// A partial or finalized piece of text returned by a recognizer.
class SpeechUpdate {
  const SpeechUpdate({this.finalText = '', this.partialText = ''});

  final String finalText;
  final String partialText;

  bool get isEmpty => finalText.trim().isEmpty && partialText.trim().isEmpty;
}

/// A user-facing failure raised by the file-audio speech pipeline.
class SpeechException implements Exception {
  const SpeechException(this.userMessage, {this.cause});

  final String userMessage;
  final Object? cause;

  @override
  String toString() {
    final detail = cause;
    return detail == null
        ? 'SpeechException: $userMessage'
        : 'SpeechException: $userMessage ($detail)';
  }
}

/// Raised when the current build cannot run the native file-audio pipeline.
class UnsupportedSpeechPlatformException extends SpeechException {
  const UnsupportedSpeechPlatformException()
    : super(
        'On-device captions are available in the Android and iOS apps. '
        "This build cannot decode a local media file's audio track.",
      );
}

/// Raised when FFmpeg cannot extract an audio track from the selected file.
class MediaAudioExtractionException extends SpeechException {
  const MediaAudioExtractionException({Object? cause})
    : super(
        "The selected file's audio track could not be decoded. Try an MP4, "
        'MOV, M4A, MP3, WAV, or OGG file with a standard audio track.',
        cause: cause,
      );
}

/// Raised when the offline model cannot be downloaded on first use.
class SpeechModelDownloadException extends SpeechException {
  const SpeechModelDownloadException({Object? cause})
    : super(
        'The offline speech model could not be downloaded. Connect to the '
        'internet for the first run, then retry captions.',
        cause: cause,
      );
}

/// Raised when the downloaded model cannot be opened by Vosk.
class SpeechModelException extends SpeechException {
  const SpeechModelException({Object? cause})
    : super(
        'The offline speech model could not be loaded. Check that the device '
        'has free storage, then retry captions.',
        cause: cause,
      );
}

/// Raised when Vosk fails while processing PCM audio.
class SpeechRecognitionException extends SpeechException {
  const SpeechRecognitionException({Object? cause})
    : super(
        'On-device speech recognition stopped unexpectedly. Retry captions.',
        cause: cause,
      );
}

/// The platform backend that owns audio extraction, model loading, and Vosk.
abstract interface class SpeechBackend {
  bool get isSupported;

  Future<bool> initialize({
    required void Function(SpeechStatus status) onStatus,
  });

  Future<SpeechSession> createSession(String mediaPath);

  Future<void> dispose();
}

/// One extracted media file plus its recognizer.
abstract interface class SpeechSession {
  int get sampleRate;

  Duration get duration;

  /// Reads at most [maximumLength] of 16-bit mono PCM at [position].
  Future<Uint8List> read(Duration position, Duration maximumLength);

  /// Converts a number of PCM bytes into playback duration.
  Duration durationForBytes(int byteLength);

  /// Feeds PCM into the recognizer and returns any newly available text.
  Future<SpeechUpdate> accept(Uint8List pcm);

  /// Flushes the recognizer's buffered audio and returns final text.
  Future<SpeechUpdate> finish();

  /// Clears recognizer state, for example after a seek.
  Future<void> reset();

  Future<void> dispose();
}

/// Parses the JSON documents returned by Vosk's C API.
abstract final class VoskResultParser {
  static SpeechUpdate parse(String json, {required bool isFinal}) {
    final trimmed = json.trim();
    if (trimmed.isEmpty) {
      return const SpeechUpdate();
    }

    Object? decoded;
    try {
      decoded = jsonDecode(trimmed);
    } on FormatException {
      return _fromText(trimmed, isFinal: isFinal);
    }

    if (decoded is! Map) {
      return _fromText(trimmed, isFinal: isFinal);
    }

    final text =
        _readText(decoded['text']) ??
        (isFinal ? _joinWords(decoded['result']) : null) ??
        _readText(decoded['partial']) ??
        '';

    if (text.isEmpty) {
      return const SpeechUpdate();
    }
    return SpeechUpdate(
      finalText: isFinal ? text : '',
      partialText: isFinal ? '' : text,
    );
  }

  static SpeechUpdate _fromText(String text, {required bool isFinal}) {
    if (text.isEmpty) {
      return const SpeechUpdate();
    }
    return SpeechUpdate(
      finalText: isFinal ? text : '',
      partialText: isFinal ? '' : text,
    );
  }

  static String? _readText(Object? value) {
    if (value is! String) {
      return null;
    }
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static String? _joinWords(Object? value) {
    if (value is! List) {
      return null;
    }
    final words = <String>[];
    for (final item in value) {
      if (item is Map) {
        final word = _readText(item['word']);
        if (word != null) {
          words.add(word);
        }
      }
    }
    return words.isEmpty ? null : words.join(' ');
  }
}
