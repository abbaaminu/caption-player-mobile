import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_whisper_ggml/flutter_whisper.dart';

import '../config/app_config.dart';
import '../services/api_service.dart';
import '../services/speech_service.dart';
import '../services/storage_service.dart';
import 'caption_history.dart';
import 'system_caption_gate.dart';

/// Converts little-endian signed 16-bit PCM into the float samples Whisper
/// expects (-1.0 to 1.0).
Float32List pcm16ToFloat32(Uint8List pcm) {
  final count = pcm.lengthInBytes ~/ 2;
  final data = ByteData.sublistView(pcm);
  final samples = Float32List(count);
  for (var i = 0; i < count; i++) {
    samples[i] = data.getInt16(i * 2, Endian.little) / 32768.0;
  }
  return samples;
}

/// Stock phrases Whisper invents for near-silent audio. They are only
/// discarded when the audio was also very quiet, so real speech such as
/// someone saying "thank you" at normal volume is kept.
const List<String> _quietAudioHallucinations = <String>[
  'thank you',
  'thank you.',
  'thanks for watching',
  'thanks for watching!',
  'thank you for watching',
  'thank you for watching.',
  'you',
  'bye',
  'bye.',
  'subtitles by the amara.org community',
];

/// RMS (0–1) under which a stock phrase is treated as a hallucination.
const double _quietRms = 0.012;

bool isLikelyHallucination(String transcript, {required double rms}) {
  if (rms >= _quietRms) {
    return false;
  }
  return _quietAudioHallucinations.contains(transcript.trim().toLowerCase());
}

/// Runs inside the headless Flutter engine that [SystemCaptionService] (the
/// Android foreground service) hosts. The service captures playback audio and
/// sends it here every couple of seconds; this loads Whisper, transcribes, and
/// sends caption text back for the overlay to draw.
///
/// Channel contract (native → Dart): `step` {audible, rms, stepMs, pcm?} and
/// `stop`. (Dart → native): `ready`, `status` {message}, `caption` {text,
/// history}, and `fatal` {reason, message}.
class SystemCaptionWorker {
  SystemCaptionWorker({
    MethodChannel? channel,
    WhisperModelLoader? loadModel,
    SystemCaptionGate? gate,
    ApiService? api,
  }) : _channel =
           channel ??
           const MethodChannel('live_caption_player/system_caption_worker'),
       _loadModel = loadModel ?? LocalWhisperRecognitionEngine.loadDefaultModel,
       _api = api ?? ApiService() {
    _gate = gate ?? SystemCaptionGate(storage: StorageService(), api: _api);
  }

  final MethodChannel _channel;
  final WhisperModelLoader _loadModel;
  final ApiService _api;
  late final SystemCaptionGate _gate;

  /// Silent steps before the caption box clears itself (about 5 s).
  static const int silentStepsBeforeClearing = 2;
  static const int _maximumFailures = 4;

  final CaptionHistory _history = CaptionHistory();
  FlutterWhisper? _whisper;
  bool _ready = false;
  bool _stopped = false;
  int _silentSteps = 0;
  int _failures = 0;
  int _lastModelPercent = -1;

  /// Entry point called from `systemCaptionMain`.
  Future<void> run() async {
    _channel.setMethodCallHandler(_handleCall);
    try {
      await _status('Preparing live captions…');
      await _gate.load();
      if (_gate.isExhausted) {
        await _fatal('trial_ended', _trialEndedMessage);
        return;
      }
      _whisper = await _loadModel(
        onProgress: (percent) {
          if (percent == _lastModelPercent) {
            return;
          }
          _lastModelPercent = percent;
          unawaited(_status('Downloading caption model · $percent%'));
        },
      );
      if (_stopped) {
        await _disposeModel();
        return;
      }
      _ready = true;
      await _status('Listening for audio…');
      await _channel.invokeMethod<void>('ready');
    } catch (error) {
      if (kDebugMode) {
        debugPrint('System caption worker failed to start: $error');
      }
      await _fatal(
        'model_failed',
        'Could not prepare the on-device caption model. Check your '
            'connection for the first download (about 31 MB), then start '
            'captions again.',
      );
    }
  }

  Future<Object?> _handleCall(MethodCall call) async {
    switch (call.method) {
      case 'step':
        await _handleStep(call.arguments);
        return null;
      case 'stop':
        await _shutDown();
        return null;
    }
    throw MissingPluginException('Unknown method ${call.method}');
  }

  Future<void> _handleStep(Object? arguments) async {
    if (!_ready || _stopped || arguments is! Map) {
      return;
    }
    final audible = arguments['audible'] == true;
    final stepMs = (arguments['stepMs'] as num?)?.toInt() ?? 0;
    final rms = (arguments['rms'] as num?)?.toDouble() ?? 0;
    final pcm = arguments['pcm'];

    if (!audible) {
      _silentSteps += 1;
      if (_silentSteps == silentStepsBeforeClearing) {
        _history.clear();
        await _sendCaption();
      }
      return;
    }
    _silentSteps = 0;

    final withinTrial = await _gate.spend(stepMs);
    if (!withinTrial) {
      await _fatal('trial_ended', _trialEndedMessage);
      return;
    }

    final whisper = _whisper;
    if (pcm is! Uint8List || whisper == null) {
      return;
    }
    try {
      final result = await whisper.transcribe(
        pcm16ToFloat32(pcm),
        config: const WhisperTranscribeConfig(
          language: 'auto',
          threads: 2,
          noContext: true,
          bestOf: 1,
          beamSize: 1,
        ),
      );
      _failures = 0;
      if (_stopped) {
        return;
      }
      final text = cleanTranscript(result.text);
      if (text.isEmpty || isLikelyHallucination(text, rms: rms)) {
        return;
      }
      if (_history.add(text)) {
        await _sendCaption();
      }
    } catch (error) {
      _failures += 1;
      if (kDebugMode) {
        debugPrint('System caption transcription failed: $error');
      }
      if (_failures >= _maximumFailures) {
        await _fatal(
          'transcribe_failed',
          'Live captions stopped because the on-device model kept failing. '
              'Start captions again, or restart your phone if it persists.',
        );
      }
    }
  }

  Future<void> _sendCaption() async {
    try {
      await _channel.invokeMethod<void>('caption', <String, Object>{
        'text': _history.latest,
        'history': _history.lines,
      });
    } on PlatformException {
      // The overlay is gone; the service is shutting down.
    } on MissingPluginException {
      // Same.
    }
  }

  Future<void> _status(String message) async {
    try {
      await _channel.invokeMethod<void>('status', <String, Object>{
        'message': message,
      });
    } on PlatformException {
      // Service already stopping.
    } on MissingPluginException {
      // Same.
    }
  }

  Future<void> _fatal(String reason, String message) async {
    if (_stopped) {
      return;
    }
    _ready = false;
    try {
      await _channel.invokeMethod<void>('fatal', <String, Object>{
        'reason': reason,
        'message': message,
      });
    } on PlatformException {
      // Service already stopping.
    } on MissingPluginException {
      // Same.
    }
  }

  Future<void> _shutDown() async {
    if (_stopped) {
      return;
    }
    _stopped = true;
    _ready = false;
    try {
      await _gate.flush();
    } catch (_) {
      // Best effort: trial time is re-saved on the next flush.
    }
    await _disposeModel();
    _api.close();
  }

  Future<void> _disposeModel() async {
    final whisper = _whisper;
    _whisper = null;
    try {
      await whisper?.dispose();
    } catch (_) {
      // The engine is about to be destroyed anyway.
    }
  }

  static final String _trialEndedMessage =
      'Your ${AppConfig.freeTrialDuration.inMinutes}-minute free trial has '
      'ended. Open Live Caption Player to unlock unlimited captions.';
}
