import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

/// Progress reported while preparing and running live captions.
enum SpeechStatus { preparing, listening, paused }

/// Session states reported by a platform speech engine.
enum SpeechEngineStatus { listening, notListening, done }

/// Thin, mockable wrapper around the platform speech recognizer.
abstract interface class SpeechRecognitionEngine {
  bool get isSupported;

  bool get isListening;

  Future<bool> initialize({
    required void Function(String message, bool permanent) onError,
    required void Function(SpeechEngineStatus status) onStatus,
  });

  Future<void> listen({
    required void Function(String words, bool isFinal) onResult,
    required Duration listenFor,
    required Duration pauseFor,
  });

  Future<void> stop();

  Future<void> cancel();
}

/// Uses the device or browser speech-recognition service.
///
/// Captions listen to nearby audio through the microphone. The recognizer
/// transcribes what it hears, so playback must be audible near the device.
class PlatformSpeechRecognitionEngine implements SpeechRecognitionEngine {
  PlatformSpeechRecognitionEngine({stt.SpeechToText? speech})
    : _speech = speech ?? stt.SpeechToText();

  final stt.SpeechToText _speech;

  @override
  bool get isSupported => true;

  @override
  bool get isListening => _speech.isListening;

  @override
  Future<bool> initialize({
    required void Function(String message, bool permanent) onError,
    required void Function(SpeechEngineStatus status) onStatus,
  }) async {
    try {
      return await _speech.initialize(
        onError: (error) => onError(error.errorMsg, error.permanent),
        onStatus: (status) => onStatus(_statusFor(status)),
        debugLogging: kDebugMode,
      );
    } catch (error) {
      onError(error.toString(), true);
      return false;
    }
  }

  @override
  Future<void> listen({
    required void Function(String words, bool isFinal) onResult,
    required Duration listenFor,
    required Duration pauseFor,
  }) async {
    await _speech.listen(
      onResult: (result) =>
          onResult(result.recognizedWords, result.finalResult),
      listenOptions: stt.SpeechListenOptions(
        partialResults: true,
        cancelOnError: false,
        listenFor: listenFor,
        pauseFor: pauseFor,
        listenMode: stt.ListenMode.dictation,
      ),
    );
  }

  @override
  Future<void> stop() => _speech.stop();

  @override
  Future<void> cancel() => _speech.cancel();

  static SpeechEngineStatus _statusFor(String status) {
    switch (status) {
      case 'listening':
        return SpeechEngineStatus.listening;
      case 'done':
        return SpeechEngineStatus.done;
      default:
        return SpeechEngineStatus.notListening;
    }
  }
}

/// A captioning failure that already carries user-facing wording.
class SpeechException implements Exception {
  const SpeechException(this.userMessage, {this.cause});

  final String userMessage;
  final Object? cause;

  @override
  String toString() => 'SpeechException: $userMessage';
}

/// Speech recognition is missing on this device.
class SpeechUnavailableException extends SpeechException {
  const SpeechUnavailableException({Object? cause})
    : super(
        'Live speech recognition is unavailable on this device. Check that '
        'speech recognition is installed and enabled, then retry captions.',
        cause: cause,
      );
}

/// The browser or operating system does not offer speech recognition.
class UnsupportedSpeechPlatformException extends SpeechException {
  const UnsupportedSpeechPlatformException({bool isWeb = false})
    : super(
        isWeb
            ? 'This browser does not support live speech recognition. Try a '
                  'current version of Chrome or Edge.'
            : 'Live speech recognition is unavailable on this device. Check '
                  'that speech recognition is installed and enabled, then '
                  'retry captions.',
      );
}

/// Microphone or speech-recognition permission was refused.
class SpeechPermissionException extends SpeechException {
  const SpeechPermissionException({bool isWeb = false, Object? cause})
    : super(
        isWeb
            ? 'Microphone access is blocked. Allow microphone access for this '
                  'site in your browser settings, then retry captions. Web '
                  'captions also need HTTPS or localhost.'
            : 'Microphone access is denied. Allow microphone and '
                  'speech-recognition access for this app in device settings, '
                  'then retry captions.',
        cause: cause,
      );
}

/// A transient failure stopped the current listening session.
class SpeechRecognitionException extends SpeechException {
  const SpeechRecognitionException({Object? cause})
    : super(
        'Live captions stopped unexpectedly. Retry captions, or check that '
        'microphone access is still allowed.',
        cause: cause,
      );
}

/// Runs live captions from microphone audio and keeps them running.
///
/// Platform recognizers end their session after a period of silence or after
/// the platform's maximum session length. While playback continues, this
/// service transparently starts a new session so captions do not stop.
class SpeechService {
  SpeechService({
    SpeechRecognitionEngine? engine,
    this.initialRestartDelay = const Duration(milliseconds: 300),
    this.maximumRestartDelay = const Duration(seconds: 5),
  }) : _engine = engine ?? PlatformSpeechRecognitionEngine();

  /// How long a single recognition session may run before it is renewed.
  static const Duration listenFor = Duration(minutes: 5);

  /// How much silence ends the current phrase.
  static const Duration pauseFor = Duration(seconds: 4);

  static const int _maximumCaptionWords = 32;
  static const int _maximumCommittedWords = 60;
  static const int _maximumConsecutiveFailures = 6;

  final SpeechRecognitionEngine _engine;

  /// Delay before the first automatic restart after a session ends.
  final Duration initialRestartDelay;

  /// Upper bound for the exponential restart backoff.
  final Duration maximumRestartDelay;

  bool _disposed = false;
  bool _initialized = false;
  bool _shouldListen = false;
  bool _starting = false;
  int _generation = 0;
  int _restartAttempts = 0;
  int _consecutiveFailures = 0;
  Timer? _restartTimer;
  String? _initializationError;
  String _committedText = '';
  String _partialText = '';
  String _lastCaption = '';
  void Function(String text)? _onResult;
  void Function(String message)? _onError;
  void Function(SpeechStatus status)? _onStatus;

  bool get isSupported => _engine.isSupported;

  bool get isInitialized => _initialized;

  /// Whether captions should currently be listening.
  bool get isActive => _shouldListen;

  /// Short status text suitable for a playback status chip.
  static String statusMessage(SpeechStatus status) => switch (status) {
    SpeechStatus.preparing => 'Preparing live captions…',
    SpeechStatus.listening => 'Live captions on',
    SpeechStatus.paused => 'Live captions paused',
  };

  /// Requests microphone and speech-recognition permission and prepares the
  /// platform recognizer. Returns `false` when captions cannot start.
  Future<bool> initialize({
    required void Function(String message) onError,
    void Function(SpeechStatus status)? onStatus,
  }) async {
    if (_disposed) {
      return false;
    }
    if (!_engine.isSupported) {
      onError(UnsupportedSpeechPlatformException(isWeb: kIsWeb).userMessage);
      return false;
    }
    if (_initialized) {
      return true;
    }

    _initializationError = null;
    onStatus?.call(SpeechStatus.preparing);
    try {
      _initialized = await _engine.initialize(
        onError: (message, permanent) {
          _initializationError = message;
        },
        onStatus: _handleEngineStatus,
      );
    } catch (error) {
      _initializationError = error.toString();
      _initialized = false;
    }

    if (!_initialized) {
      final detail = _initializationError;
      onError(
        detail == null
            ? SpeechUnavailableException().userMessage
            : userFriendlyError(detail, isWeb: kIsWeb),
      );
    }
    return _initialized;
  }

  /// Starts (or resumes) listening and streams rolling caption text.
  Future<void> startListening({
    required void Function(String text) onResult,
    required void Function(String message) onError,
    void Function(SpeechStatus status)? onStatus,
  }) async {
    if (_disposed) {
      return;
    }
    if (!_initialized) {
      onError(SpeechUnavailableException().userMessage);
      return;
    }

    _onResult = onResult;
    _onError = onError;
    _onStatus = onStatus;
    _shouldListen = true;
    _restartAttempts = 0;
    _consecutiveFailures = 0;
    _cancelRestart();
    _resetCaption();

    if (_engine.isListening) {
      onStatus?.call(SpeechStatus.listening);
      return;
    }
    await _beginListening();
  }

  /// Stops the microphone without discarding the last caption.
  ///
  /// Call [startListening] to resume after a pause.
  Future<void> pause() async {
    if (_disposed || !_shouldListen) {
      return;
    }
    _shouldListen = false;
    _cancelRestart();
    _generation += 1;
    _commitPartial();
    try {
      await _engine.stop();
    } catch (error) {
      if (kDebugMode) {
        debugPrint('Stopping speech recognition failed: $error');
      }
    }
    _onStatus?.call(SpeechStatus.paused);
  }

  /// Stops listening and clears the streaming callbacks.
  Future<void> stop() async {
    if (_disposed) {
      return;
    }
    _shouldListen = false;
    _cancelRestart();
    _generation += 1;
    _commitPartial();
    try {
      await _engine.cancel();
    } catch (error) {
      if (kDebugMode) {
        debugPrint('Cancelling speech recognition failed: $error');
      }
    }
    _onResult = null;
    _onError = null;
    _onStatus = null;
    _resetCaption(emit: false);
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    await stop();
    _disposed = true;
  }

  /// Runs one recognition session. The recognizer may end it on silence or
  /// after its maximum session length; [_scheduleRestart] renews it while
  /// captions should stay on.
  Future<void> _beginListening() async {
    if (_disposed || !_shouldListen) {
      return;
    }
    if (_starting) {
      _scheduleRestart();
      return;
    }

    _starting = true;
    final generation = _generation;
    _onStatus?.call(SpeechStatus.listening);

    try {
      await _engine.listen(
        onResult: (words, isFinal) {
          if (_disposed || !_shouldListen || generation != _generation) {
            return;
          }
          _handleResult(words, isFinal);
        },
        listenFor: listenFor,
        pauseFor: pauseFor,
      );
      _consecutiveFailures = 0;
    } catch (error) {
      if (_disposed || !_shouldListen || generation != _generation) {
        return;
      }
      _consecutiveFailures += 1;
      if (_consecutiveFailures >= _maximumConsecutiveFailures) {
        _shouldListen = false;
        _onError?.call(SpeechRecognitionException(cause: error).userMessage);
        _onStatus?.call(SpeechStatus.paused);
        return;
      }
      _scheduleRestart();
    } finally {
      _starting = false;
    }
  }

  void _handleEngineStatus(SpeechEngineStatus status) {
    if (_disposed) {
      return;
    }
    if (status == SpeechEngineStatus.listening) {
      if (_shouldListen) {
        _restartAttempts = 0;
        _onStatus?.call(SpeechStatus.listening);
      }
      return;
    }
    if (!_shouldListen) {
      return;
    }
    _scheduleRestart();
  }

  /// Renews the recognition session with a short, capped backoff so a burst of
  /// status events cannot spin up duplicate sessions.
  void _scheduleRestart() {
    if (_disposed || !_shouldListen || _restartTimer != null) {
      return;
    }
    final exponent = math.min(_restartAttempts, 5);
    final delay = _backoffDelay(exponent);
    _restartAttempts += 1;
    _restartTimer = Timer(delay, () {
      _restartTimer = null;
      _beginListening();
    });
  }

  Duration _backoffDelay(int exponent) {
    final delay = initialRestartDelay * (1 << exponent);
    return delay > maximumRestartDelay ? maximumRestartDelay : delay;
  }

  void _cancelRestart() {
    _restartTimer?.cancel();
    _restartTimer = null;
  }

  void _handleResult(String words, bool isFinal) {
    final normalized = _normalize(words);
    if (isFinal) {
      _partialText = '';
      _commitWords(normalized);
      _consecutiveFailures = 0;
      _restartAttempts = 0;
    } else {
      _partialText = normalized;
    }
    _emitCaption();
  }

  /// Moves the interim phrase into the committed caption. Keeping committed
  /// words means a new recognition session continues the same caption instead
  /// of starting every phrase from an empty line.
  void _commitWords(String words) {
    if (words.isEmpty) {
      return;
    }
    final combined = <String>[
      ..._committedText.split(' ').where((word) => word.isNotEmpty),
      ...words.split(' ').where((word) => word.isNotEmpty),
    ];
    final start = math.max(0, combined.length - _maximumCommittedWords);
    _committedText = combined.sublist(start).join(' ');
  }

  void _commitPartial() {
    final partial = _partialText;
    _partialText = '';
    if (partial.isEmpty) {
      return;
    }
    _commitWords(partial);
    _emitCaption();
  }

  void _emitCaption() {
    final builder = <String>[
      if (_committedText.isNotEmpty) _committedText,
      if (_partialText.isNotEmpty) _partialText,
    ];
    final words = builder.join(' ').split(' ').where((word) => word.isNotEmpty);
    final visible = words.length > _maximumCaptionWords
        ? words.skip(words.length - _maximumCaptionWords).join(' ')
        : words.join(' ');
    if (visible == _lastCaption) {
      return;
    }
    _lastCaption = visible;
    _onResult?.call(visible);
  }

  void _resetCaption({bool emit = true}) {
    _committedText = '';
    _partialText = '';
    _lastCaption = '';
    if (emit) {
      _onResult?.call('');
    }
  }

  static String _normalize(String value) =>
      value.replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Maps raw platform recognizer errors to wording a user can act on.
String userFriendlyError(String detail, {bool isWeb = kIsWeb}) {
  final message = detail.toLowerCase();
  if (message.contains('permission') ||
      message.contains('not-allowed') ||
      message.contains('denied') ||
      message.contains('microphone')) {
    return SpeechPermissionException(isWeb: isWeb).userMessage;
  }
  if (message.contains('network')) {
    return 'Live captions need a network connection for speech recognition. '
        'Reconnect, then retry captions.';
  }
  if (message.contains('no speech') ||
      message.contains('no_match') ||
      message.contains('speech_timeout')) {
    return 'No speech was recognized yet. Keep playback audible and speak '
        'clearly near the device, then retry captions.';
  }
  if (message.contains('busy')) {
    return 'Speech recognition is busy with another app. Close it, then retry '
        'captions.';
  }
  if (message.contains('audio')) {
    return 'The microphone is unavailable. Check that no other app is using '
        'it, then retry captions.';
  }
  return SpeechRecognitionException().userMessage;
}
