import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_whisper_ggml/flutter_whisper.dart';

import 'media_audio_source.dart';
import 'web_caption_support_stub.dart'
    if (dart.library.js_interop) 'web_caption_support_web.dart'
    as platform;

/// Progress reported while preparing and running live captions.
enum SpeechStatus { preparing, downloading, listening, paused }

/// Session states reported by a platform speech engine.
enum SpeechEngineStatus { downloading, listening, notListening, done }

/// Thin, mockable wrapper around the media-audio transcription engine.
abstract interface class SpeechRecognitionEngine {
  bool get isSupported;

  bool get isListening;

  Future<bool> initialize({
    required void Function(String message, bool permanent) onError,
    required void Function(SpeechEngineStatus status) onStatus,
    required void Function(int progress) onProgress,
  });

  Future<void> listen({
    required void Function(String words, bool isFinal) onResult,
    required void Function(String message) onError,
    required MediaAudioSource? audioSource,
    required Duration Function() position,
  });

  Future<void> stop();

  void resetTimeline();

  Future<void> cancel();

  Future<void> dispose();
}

/// Loads the on-device Whisper model and reports 0-100 progress.
typedef WhisperModelLoader =
    Future<FlutterWhisper> Function({
      required void Function(int percent) onProgress,
    });

/// Extracts short PCM windows from the loaded media and transcribes them with
/// local Whisper.
///
/// Each window ends at the current playback position, so captions describe
/// audio that has just played instead of running ahead of the video. The
/// multilingual model is downloaded once and cached. Media audio remains
/// on-device and is never uploaded.
class LocalWhisperRecognitionEngine implements SpeechRecognitionEngine {
  LocalWhisperRecognitionEngine({
    WhisperModelLoader? loadModel,
    DateTime Function()? now,
  }) : _loadModel = loadModel ?? _loadBundledModel,
       _now = now ?? DateTime.now;

  final WhisperModelLoader _loadModel;

  /// Wall clock used to detect playhead jumps during transcription.
  final DateTime Function() _now;

  static const _transcriptionWindow = Duration(seconds: 5);
  static const _transcriptionInterval = Duration(seconds: 2);

  /// A window shorter than this cannot be transcribed reliably.
  static const _minimumWindow = Duration(seconds: 2);

  /// Windows of pure silence that clear the caption line.
  static const _silentWindowsBeforeClearing = 2;
  static const _maximumTranscriptionFailures = 3;

  /// Slack between the playhead and the wall clock before a window is treated
  /// as belonging to audio the viewer has already left behind.
  static const _playheadJumpTolerance = Duration(seconds: 2);

  FlutterWhisper? _whisper;
  Timer? _transcriptionTimer;
  void Function(String, bool)? _onResult;
  void Function(String)? _onError;
  MediaAudioSource? _audioSource;
  Duration Function() _position = () => Duration.zero;

  /// Earliest audio that captions may describe. Reset on every seek so old
  /// audio is never transcribed after the viewer jumps elsewhere.
  Duration _windowFloor = Duration.zero;
  int _silentWindows = 0;
  bool _isListening = false;
  bool _isTranscribing = false;
  int _transcriptionGeneration = 0;
  int _transcriptionFailures = 0;

  /// Downloads (once) and loads the multilingual model used by live captions.
  static Future<FlutterWhisper> _loadBundledModel({
    required void Function(int percent) onProgress,
  }) {
    return FlutterWhisper.loadModel(
      model: WhisperModels.tinyQ5_1,
      config: const WhisperModelConfig(useGpu: false, flashAttention: false),
      onDownloadProgress: (progress) => onProgress(progress.percent),
      onModelProgress: (progress) => onProgress(progress.clamp(0, 100).toInt()),
    );
  }

  @override
  bool get isSupported =>
      kIsWeb ||
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  @override
  bool get isListening => _isListening;

  @override
  Future<bool> initialize({
    required void Function(String message, bool permanent) onError,
    required void Function(SpeechEngineStatus status) onStatus,
    required void Function(int progress) onProgress,
  }) async {
    if (!isSupported) {
      onError(
        UnsupportedSpeechPlatformException(isWeb: kIsWeb).userMessage,
        true,
      );
      return false;
    }
    if (kIsWeb && !platform.hasCaptionIsolation) {
      onError(
        'Web captions need cross-origin isolation. Run this app with '
        '`flutter run -d web-server`, or deploy it with the COOP and COEP '
        'headers. VS Code Live Server does not add those headers.',
        true,
      );
      return false;
    }

    try {
      _whisper ??= await _loadModel(
        onProgress: (percent) {
          onStatus(SpeechEngineStatus.downloading);
          onProgress(percent);
        },
      );
      return true;
    } catch (error) {
      onError(
        'Could not prepare the on-device caption model. Check your connection '
        'for its first download, then retry captions.',
        true,
      );
      if (kDebugMode) {
        debugPrint('Loading the on-device caption model failed: $error');
      }
      return false;
    }
  }

  @override
  Future<void> listen({
    required void Function(String words, bool isFinal) onResult,
    required void Function(String message) onError,
    required MediaAudioSource? audioSource,
    required Duration Function() position,
  }) async {
    if (_isListening) {
      return;
    }
    if (_whisper == null) {
      throw StateError('The on-device caption model is not ready.');
    }
    if (audioSource == null) {
      throw StateError('No media audio source is available for captions.');
    }

    _onResult = onResult;
    _onError = onError;
    _audioSource = audioSource;
    _position = position;
    _windowFloor = position();
    _silentWindows = 0;
    _transcriptionFailures = 0;
    _isListening = true;
    final generation = ++_transcriptionGeneration;
    _transcriptionTimer = Timer.periodic(
      _transcriptionInterval,
      (_) => unawaited(_transcribeWindow(generation)),
    );
    unawaited(_transcribeWindow(generation));
  }

  Future<void> _transcribeWindow(int generation) async {
    final whisper = _whisper;
    final source = _audioSource;
    if (!_isListening ||
        _isTranscribing ||
        generation != _transcriptionGeneration ||
        whisper == null ||
        source == null) {
      return;
    }

    _isTranscribing = true;
    try {
      final position = _position();
      final transcriptionStartedAt = _now();
      final start = _windowStartFor(position);
      final window = position - start;
      if (window < _minimumWindow) {
        return;
      }
      final samples = await source.readSamplesAt(start, window);
      if (!_isListening ||
          generation != _transcriptionGeneration ||
          _positionHasJumped(position, transcriptionStartedAt)) {
        return;
      }
      // A read that yields far less audio than requested means the decoder
      // could not produce that stretch (for example past the end of the
      // file). Treating it as silence keeps captions stable instead of
      // transcribing a fraction of a window.
      final expectedSamples = window.inMilliseconds * 16;
      if (samples.length * 2 < expectedSamples) {
        _reportSilence(generation);
        return;
      }
      final result = await whisper.transcribe(
        samples,
        config: const WhisperTranscribeConfig(
          language: 'auto',
          threads: 2,
          noContext: true,
          bestOf: 1,
          beamSize: 1,
        ),
      );
      _transcriptionFailures = 0;
      if (!_isListening ||
          generation != _transcriptionGeneration ||
          _positionHasJumped(position, transcriptionStartedAt)) {
        return;
      }
      final transcript = cleanTranscript(result.text);
      if (transcript.isEmpty) {
        _reportSilence(generation);
        return;
      }
      _silentWindows = 0;
      _onResult?.call(transcript, false);
    } catch (error) {
      if (!_isListening || generation != _transcriptionGeneration) {
        return;
      }
      _transcriptionFailures += 1;
      if (kDebugMode) {
        debugPrint('On-device caption transcription failed: $error');
      }
      if (_transcriptionFailures >= _maximumTranscriptionFailures) {
        await _stopCapture();
        _onError?.call(userFriendlyError(error.toString(), isWeb: kIsWeb));
      }
    } finally {
      _isTranscribing = false;
      if (_isListening && generation != _transcriptionGeneration) {
        unawaited(_transcribeWindow(_transcriptionGeneration));
      }
    }
  }

  /// Captions describe audio that has just played, never audio the viewer has
  /// not heard yet. The window therefore ends at the current position.
  Duration _windowStartFor(Duration position) {
    final trailing = position - _transcriptionWindow;
    return trailing < _windowFloor ? _windowFloor : trailing;
  }

  /// Clears the caption line once the media has been silent long enough,
  /// instead of leaving the last spoken phrase on screen indefinitely.
  void _reportSilence(int generation) {
    if (generation != _transcriptionGeneration || !_isListening) {
      return;
    }
    _silentWindows += 1;
    if (_silentWindows >= _silentWindowsBeforeClearing) {
      _onResult?.call('', false);
    }
  }

  /// A playhead that stalls (buffering or a pause) legitimately trails the wall
  /// clock, so only a playhead that moved backwards, or that ran ahead of the
  /// time that actually passed, means the window was abandoned.
  bool _positionHasJumped(Duration initialPosition, DateTime startedAt) {
    final current = _position();
    if (current < initialPosition) {
      return true;
    }
    final elapsed = _now().difference(startedAt);
    return current - initialPosition > elapsed + _playheadJumpTolerance;
  }

  Future<void> _stopCapture() async {
    _isListening = false;
    _transcriptionGeneration += 1;
    _transcriptionTimer?.cancel();
    _transcriptionTimer = null;
    _audioSource = null;
    _position = () => Duration.zero;
    _windowFloor = Duration.zero;
    _silentWindows = 0;
  }

  @override
  Future<void> stop() => _stopCapture();

  @override
  void resetTimeline() {
    if (!_isListening) {
      return;
    }
    _windowFloor = _position();
    _silentWindows = 0;
    _transcriptionTimer?.cancel();
    final generation = ++_transcriptionGeneration;
    _transcriptionTimer = Timer.periodic(
      _transcriptionInterval,
      (_) => unawaited(_transcribeWindow(generation)),
    );
    unawaited(_transcribeWindow(generation));
  }

  @override
  Future<void> cancel() => _stopCapture();

  @override
  Future<void> dispose() async {
    await _stopCapture();
    final whisper = _whisper;
    _whisper = null;
    await whisper?.dispose();
  }
}

/// Whisper annotates silence with bracketed cues such as `[BLANK_AUDIO]`.
/// Those cues are not speech and must never reach the caption overlay.
final RegExp _silenceCue = RegExp(
  r'[\[(]\s*(?:blank[ _]?audio|silence|no[ _]speech|inaudible|unintelligible)'
  r'\s*[\])]',
  caseSensitive: false,
);

/// Normalizes one Whisper transcript for display.
///
/// Removes silence annotations, collapses whitespace, and trims the edges.
/// Music, applause, and laughter cues are kept because they describe what the
/// viewer is hearing.
String cleanTranscript(String text) {
  return text
      .replaceAll(_silenceCue, ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

/// A captioning failure that already carries user-facing wording.
class SpeechException implements Exception {
  const SpeechException(this.userMessage, {this.cause});

  final String userMessage;
  final Object? cause;

  @override
  String toString() => 'SpeechException: $userMessage';
}

/// On-device transcription is not available on this device.
class SpeechUnavailableException extends SpeechException {
  const SpeechUnavailableException({Object? cause})
    : super(
        'On-device caption transcription is unavailable. Check that the app '
        'supports this device, then retry captions.',
        cause: cause,
      );
}

/// On-device transcription is not supported on this platform.
class UnsupportedSpeechPlatformException extends SpeechException {
  const UnsupportedSpeechPlatformException({bool isWeb = false})
    : super(
        isWeb
            ? 'This browser does not support on-device live captions. Try a '
                  'current browser with WebAssembly support.'
            : 'On-device live captions are unavailable on this device. Check '
                  'that the app supports this device, then '
                  'retry captions.',
      );
}

/// A transient failure stopped the current listening session.
class SpeechRecognitionException extends SpeechException {
  const SpeechRecognitionException({Object? cause})
    : super(
        'Live captions stopped unexpectedly. Retry captions, or reopen the '
        'media file if its audio track could not be decoded.',
        cause: cause,
      );
}

/// Runs live captions from the loaded media's audio track.
///
/// Transcription follows the playback position, so seeking the video moves
/// captions to that point and discards the old caption line.
class SpeechService {
  SpeechService({
    SpeechRecognitionEngine? engine,
    this.initialRestartDelay = const Duration(milliseconds: 300),
    this.maximumRestartDelay = const Duration(seconds: 5),
  }) : _engine = engine ?? LocalWhisperRecognitionEngine();

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
  MediaAudioSource? _audioSource;
  Duration Function() _position = () => Duration.zero;
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
    SpeechStatus.downloading => 'Downloading caption model…',
    SpeechStatus.listening => 'Live captions on',
    SpeechStatus.paused => 'Live captions paused',
  };

  /// Prepares the on-device transcription model. Returns `false` when
  /// transcription cannot start.
  Future<bool> initialize({
    required void Function(String message) onError,
    void Function(SpeechStatus status)? onStatus,
    void Function(int progress)? onProgress,
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
        onStatus: (status) {
          if (status == SpeechEngineStatus.downloading) {
            onStatus?.call(SpeechStatus.downloading);
          } else {
            _handleEngineStatus(status);
          }
        },
        onProgress: (progress) => onProgress?.call(progress),
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
            : detail.startsWith('Could not prepare the on-device caption model')
            ? detail
            : userFriendlyError(detail, isWeb: kIsWeb),
      );
    }
    return _initialized;
  }

  /// Starts (or resumes) listening and streams rolling caption text.
  Future<void> startListening({
    required void Function(String text) onResult,
    required void Function(String message) onError,
    MediaAudioSource? audioSource,
    Duration Function()? position,
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
    _audioSource = audioSource;
    _position = position ?? (() => Duration.zero);
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

  /// Pauses transcription without discarding the last caption.
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
    _audioSource = null;
    _position = () => Duration.zero;
  }

  /// Clears the rolling transcript after a seek while leaving captions active.
  void resetTimeline() {
    if (_disposed) {
      return;
    }
    _engine.resetTimeline();
    _committedText = '';
    _partialText = '';
    _lastCaption = '';
    _onResult?.call('');
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    await stop();
    // Marking the service disposed before releasing the engine keeps a failed
    // engine cleanup from leaving a half-disposed service usable.
    _disposed = true;
    await _engine.dispose();
  }

  /// Starts one transcription loop. The restart path handles an engine that
  /// stops or fails while captions should remain active.
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
        onError: (message) {
          if (!_disposed && _shouldListen && generation == _generation) {
            _onError?.call(message);
          }
        },
        audioSource: _audioSource,
        position: _position,
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

/// Maps platform errors to wording a user can act on.
String userFriendlyError(String detail, {bool isWeb = kIsWeb}) {
  final message = detail.toLowerCase();
  if (message.contains('permission') || message.contains('not-allowed')) {
    return 'Live captions could not access the selected media audio. Reopen '
        'the file, then retry captions.';
  }
  if (message.contains('network')) {
    return 'Live captions need a network connection to download the on-device '
        'model. Reconnect, then retry captions.';
  }
  if (message.contains('no speech') ||
      message.contains('no_match') ||
      message.contains('speech_timeout')) {
    return 'No speech was recognized in this section of the media.';
  }
  if (message.contains('busy')) {
    return 'Speech recognition is busy with another app. Close it, then retry '
        'captions.';
  }
  if (message.contains('audio')) {
    return 'The media audio track could not be decoded. Try a supported video '
        'or audio format, then retry captions.';
  }
  return SpeechRecognitionException().userMessage;
}
