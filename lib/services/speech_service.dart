import 'dart:async';

import 'speech_backend.dart';
import 'speech_backend_stub.dart'
    if (dart.library.io) 'speech_backend_io.dart'
    as platform;

/// Coordinates playback position, FFmpeg extraction, and Vosk recognition.
///
/// Audio is read from the extracted WAV file only up to the position the
/// player has actually reached, so captions stay aligned with playback.
class SpeechService {
  SpeechService({SpeechBackend? backend})
    : _backend = backend ?? platform.createSpeechBackend();

  static const Duration _pollInterval = Duration(milliseconds: 80);
  static const Duration _seekThreshold = Duration(milliseconds: 1500);
  static const Duration _captionLatency = Duration(milliseconds: 200);
  static const Duration _minimumChunk = Duration(milliseconds: 250);
  static const Duration _maximumChunk = Duration(seconds: 1);

  final SpeechBackend _backend;

  bool _initialized = false;
  bool _active = false;
  bool _disposed = false;
  bool _flushOnStop = false;
  int _generation = 0;
  int _epoch = 0;

  Future<void>? _pumpFuture;
  Completer<void>? _wake;
  Duration _nextPosition = Duration.zero;
  bool _resetPending = false;
  String _finalText = '';
  String _partialText = '';
  void Function(String text)? _displayCallback;

  bool get isSupported => _backend.isSupported;
  bool get isInitialized => _initialized;
  bool get isActive => _active;

  Future<bool> initialize({
    required void Function(String) onError,
    void Function(SpeechStatus status)? onStatus,
  }) async {
    if (_disposed) {
      return false;
    }
    if (!_backend.isSupported) {
      onError(const UnsupportedSpeechPlatformException().userMessage);
      return false;
    }
    if (_initialized) {
      return true;
    }

    try {
      _initialized = await _backend.initialize(
        onStatus: (status) {
          if (!_disposed) {
            onStatus?.call(status);
          }
        },
      );
      if (!_initialized) {
        onError(
          const SpeechModelException(
            cause: 'Speech backend did not initialize.',
          ).userMessage,
        );
      }
      return _initialized;
    } catch (error) {
      _initialized = false;
      onError(userFriendlyError(error));
      return false;
    }
  }

  /// Starts a new file-audio transcription session.
  ///
  /// [position] is read repeatedly so no player-specific types leak into the
  /// service. Seeking is detected from a large position jump and also through
  /// an explicit [seek] call.
  Future<void> startTranscription({
    required String mediaPath,
    required Duration Function() position,
    required void Function(String text) onResult,
    required void Function(String message) onError,
    required void Function(SpeechStatus status) onStatus,
  }) async {
    if (_disposed) {
      return;
    }
    if (!_initialized || !_backend.isSupported) {
      onError(const UnsupportedSpeechPlatformException().userMessage);
      return;
    }

    await _stopCurrent(flush: false);
    if (_disposed) {
      return;
    }

    _epoch += 1;
    _generation += 1;
    _active = true;
    _resetPending = false;
    _finalText = '';
    _partialText = '';
    _displayCallback = onResult;
    _nextPosition = _safePosition(position);
    onResult('');

    _pumpFuture = _run(
      generation: _generation,
      epoch: _epoch,
      mediaPath: mediaPath,
      position: position,
      onResult: onResult,
      onError: onError,
      onStatus: onStatus,
    );
  }

  /// Stops recognition, flushes the final buffered audio, and clears handlers.
  Future<void> stop() => _stopCurrent(flush: true);

  /// Clears recognition state immediately after the player seeks.
  void seek(Duration position) {
    if (!_active || _disposed) {
      return;
    }
    _nextPosition = position;
    _resetPending = true;
    _finalText = '';
    _partialText = '';
    _displayCallback?.call('');
    _signal();
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    await _stopCurrent(flush: false);
    await _backend.dispose();
  }

  static String statusMessage(SpeechStatus status) {
    return switch (status) {
      SpeechStatus.downloadingModel =>
        'Downloading the offline speech model (about 40 MB, first run only)…',
      SpeechStatus.loadingModel => 'Loading the offline speech model…',
      SpeechStatus.extractingAudio => "Extracting this file's audio track…",
      SpeechStatus.transcribing => 'Transcribing file audio on this device…',
    };
  }

  static String userFriendlyError(Object error, {bool isWeb = false}) {
    if (error is SpeechException) {
      return error.userMessage;
    }
    if (isWeb) {
      return const UnsupportedSpeechPlatformException().userMessage;
    }

    final message = error.toString().toLowerCase();
    if (message.contains('socket') ||
        message.contains('http') ||
        message.contains('network') ||
        message.contains('connection')) {
      return const SpeechModelDownloadException().userMessage;
    }
    if (message.contains('ffmpeg') ||
        message.contains('decode') ||
        message.contains('audio')) {
      return const MediaAudioExtractionException().userMessage;
    }
    if (message.contains('model') || message.contains('vosk')) {
      return const SpeechModelException().userMessage;
    }
    if (message.contains('space') ||
        message.contains('storage') ||
        message.contains('enospc')) {
      return 'The device does not have enough free storage for offline '
          'captions. Free some space, then retry.';
    }
    return const SpeechRecognitionException().userMessage;
  }

  static bool isNetworkError(String message) {
    final normalized = message.toLowerCase();
    return normalized.contains('network') ||
        normalized.contains('socket') ||
        normalized.contains('http');
  }

  Future<void> _run({
    required int generation,
    required int epoch,
    required String mediaPath,
    required Duration Function() position,
    required void Function(String text) onResult,
    required void Function(String message) onError,
    required void Function(SpeechStatus status) onStatus,
  }) async {
    SpeechSession? session;
    var activated = false;
    try {
      onStatus(SpeechStatus.extractingAudio);
      session = await _backend.createSession(mediaPath);
      if (!_isCurrent(generation)) {
        await session.dispose();
        session = null;
        return;
      }

      activated = true;
      _nextPosition = _safePosition(position);
      var lastObserved = _nextPosition;
      onStatus(SpeechStatus.transcribing);

      while (_isCurrent(generation)) {
        final current = _safePosition(position);
        if ((current - lastObserved).abs() > _seekThreshold) {
          _nextPosition = current;
          _finalText = '';
          _partialText = '';
          await session.reset();
          if (!_isCurrent(generation)) {
            break;
          }
          _emit('', epoch, onResult);
        }
        lastObserved = current;

        if (_resetPending) {
          _resetPending = false;
          _nextPosition = current;
          _finalText = '';
          _partialText = '';
          await session.reset();
          if (!_isCurrent(generation)) {
            break;
          }
          _emit('', epoch, onResult);
        }

        final available = current - _captionLatency;
        if (_nextPosition >= available) {
          await _waitForTick();
          continue;
        }

        var chunk = available - _nextPosition;
        if (chunk > _maximumChunk) {
          chunk = _maximumChunk;
        }
        if (chunk < _minimumChunk) {
          await _waitForTick();
          continue;
        }

        final pcm = await session.read(_nextPosition, chunk);
        if (!_isCurrent(generation)) {
          break;
        }
        if (pcm.isEmpty) {
          await _waitForTick();
          continue;
        }

        _nextPosition += session.durationForBytes(pcm.length);
        final update = await session.accept(pcm);
        if (!_isCurrent(generation)) {
          break;
        }
        if (_resetPending) {
          continue;
        }
        _apply(update, epoch, onResult);
      }
    } catch (error) {
      if (_isCurrent(generation)) {
        _active = false;
        _displayCallback = null;
        onError(userFriendlyError(error));
      }
    } finally {
      if (_flushOnStop && activated && session != null) {
        try {
          await _drainRemaining(session, position, epoch, onResult);
          _apply(await session.finish(), epoch, onResult);
        } catch (_) {
          // Stopping is best-effort; the last caption remains visible.
        }
      }
      await session?.dispose();
    }
  }

  Future<void> _drainRemaining(
    SpeechSession session,
    Duration Function() position,
    int epoch,
    void Function(String text) onResult,
  ) async {
    final current = _safePosition(position);
    while (_nextPosition < current) {
      var chunk = current - _nextPosition;
      if (chunk > _maximumChunk) {
        chunk = _maximumChunk;
      }
      if (chunk < const Duration(milliseconds: 20)) {
        break;
      }
      final pcm = await session.read(_nextPosition, chunk);
      if (pcm.isEmpty) {
        break;
      }
      _nextPosition += session.durationForBytes(pcm.length);
      _apply(await session.accept(pcm), epoch, onResult);
    }
  }

  void _apply(
    SpeechUpdate update,
    int epoch,
    void Function(String text) onResult,
  ) {
    if (epoch != _epoch || _disposed) {
      return;
    }
    if (update.finalText.trim().isNotEmpty) {
      _finalText = _tailWords('$_finalText ${update.finalText}', 40);
      _partialText = '';
      _emit(_composeCaption(), epoch, onResult);
    } else if (update.partialText.trim().isNotEmpty) {
      _partialText = update.partialText.trim();
      _emit(_composeCaption(), epoch, onResult);
    }
  }

  String _composeCaption() => _tailWords('$_finalText $_partialText', 32);

  static String _tailWords(String text, int maximumWords) {
    final words = text
        .trim()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList(growable: false);
    if (words.length <= maximumWords) {
      return words.join(' ');
    }
    return words.sublist(words.length - maximumWords).join(' ');
  }

  void _emit(String text, int epoch, void Function(String text) onResult) {
    if (epoch != _epoch || _disposed) {
      return;
    }
    onResult(text);
  }

  Future<void> _stopCurrent({required bool flush}) async {
    _flushOnStop = flush;
    _active = false;
    _generation += 1;
    _resetPending = false;
    _signal();

    final pump = _pumpFuture;
    _pumpFuture = null;
    if (pump != null) {
      try {
        await pump;
      } catch (_) {
        // The pump reports its own failures through onError.
      }
    }
    _flushOnStop = false;
    _displayCallback = null;
  }

  Future<void> _waitForTick() async {
    if (!_active || _disposed) {
      return;
    }
    final wake = Completer<void>();
    _wake = wake;
    try {
      await Future.any<void>([
        wake.future,
        Future<void>.delayed(_pollInterval),
      ]);
    } finally {
      if (identical(_wake, wake)) {
        _wake = null;
      }
    }
  }

  void _signal() {
    final wake = _wake;
    if (wake != null && !wake.isCompleted) {
      wake.complete();
    }
    _wake = null;
  }

  bool _isCurrent(int generation) {
    return _active && !_disposed && _generation == generation;
  }

  static Duration _safePosition(Duration Function() position) {
    try {
      final value = position();
      return value < Duration.zero ? Duration.zero : value;
    } catch (_) {
      return Duration.zero;
    }
  }
}
