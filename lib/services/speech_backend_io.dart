import 'dart:io';
import 'dart:typed_data';

import 'package:ffmpeg_kit_flutter_new_audio/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_audio/return_code.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:vosk_flutter_service/vosk_flutter_service.dart' as vosk;

import '../config/app_config.dart';
import 'speech_backend.dart';
import 'wav_pcm_audio_source.dart';

/// Android/iOS implementation: FFmpeg extracts the selected file's audio track
/// and Vosk recognizes the resulting PCM locally.
class FfmpegVoskSpeechBackend implements SpeechBackend {
  vosk.VoskFlutterPlugin? _plugin;
  vosk.Model? _model;

  @override
  bool get isSupported => Platform.isAndroid || Platform.isIOS;

  @override
  Future<bool> initialize({
    required void Function(SpeechStatus status) onStatus,
  }) async {
    if (!isSupported) {
      return false;
    }
    if (_model != null) {
      return true;
    }

    onStatus(SpeechStatus.downloadingModel);
    final String modelPath;
    try {
      modelPath = await vosk.ModelLoader().loadFromNetwork(
        AppConfig.speechModelUrl,
      );
    } catch (error) {
      throw SpeechModelDownloadException(cause: error);
    }

    onStatus(SpeechStatus.loadingModel);
    try {
      _plugin = vosk.VoskFlutterPlugin.instance();
      _model = await _plugin!.createModel(modelPath);
    } catch (error) {
      throw SpeechModelException(cause: error);
    }
    return true;
  }

  @override
  Future<SpeechSession> createSession(String mediaPath) async {
    final model = _model;
    final plugin = _plugin;
    if (model == null || plugin == null) {
      throw const SpeechModelException(cause: 'Vosk is not initialized.');
    }

    final audio = await _extractAudio(mediaPath);
    try {
      final recognizer = await plugin.createRecognizer(
        model: model,
        sampleRate: audio.sampleRate,
      );
      return _VoskSpeechSession(audio: audio, recognizer: recognizer);
    } catch (error) {
      await audio.dispose();
      throw SpeechModelException(cause: error);
    }
  }

  Future<WavPcmAudioSource> _extractAudio(String mediaPath) async {
    final input = File(mediaPath);
    if (!await input.exists()) {
      throw const MediaAudioExtractionException(
        cause: 'The selected media file is no longer available.',
      );
    }

    final tempDirectory = await getTemporaryDirectory();
    final outputPath = p.join(
      tempDirectory.path,
      'live_caption_audio_${DateTime.now().microsecondsSinceEpoch}.wav',
    );

    try {
      final session = await FFmpegKit.executeWithArguments(<String>[
        '-y',
        '-hide_banner',
        '-loglevel',
        'error',
        '-i',
        mediaPath,
        '-map',
        '0:a:0',
        '-vn',
        '-acodec',
        'pcm_s16le',
        '-ar',
        '16000',
        '-ac',
        '1',
        '-f',
        'wav',
        outputPath,
      ]);
      final returnCode = await session.getReturnCode();
      if (!ReturnCode.isSuccess(returnCode)) {
        final logs = await session.getOutput();
        throw MediaAudioExtractionException(
          cause:
              'FFmpeg returned ${returnCode?.getValue() ?? 'no code'}: $logs',
        );
      }
    } catch (error) {
      await _deleteQuietly(outputPath);
      if (error is SpeechException) {
        rethrow;
      }
      throw MediaAudioExtractionException(cause: error);
    }

    try {
      return await WavPcmAudioSource.open(outputPath, deleteOnDispose: true);
    } catch (error) {
      await _deleteQuietly(outputPath);
      if (error is SpeechException) {
        rethrow;
      }
      throw MediaAudioExtractionException(cause: error);
    }
  }

  @override
  Future<void> dispose() async {
    _model?.dispose();
    _model = null;
    _plugin = null;
  }

  static Future<void> _deleteQuietly(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } on FileSystemException {
      // Best-effort cleanup only.
    }
  }
}

class _VoskSpeechSession implements SpeechSession {
  _VoskSpeechSession({
    required WavPcmAudioSource audio,
    required vosk.Recognizer recognizer,
  }) : _audio = audio,
       _recognizer = recognizer;

  final WavPcmAudioSource _audio;
  final vosk.Recognizer _recognizer;
  bool _disposed = false;

  @override
  int get sampleRate => _audio.sampleRate;

  @override
  Duration get duration => _audio.duration;

  @override
  Future<Uint8List> read(Duration position, Duration maximumLength) {
    return _audio.read(position, maximumLength);
  }

  @override
  Duration durationForBytes(int byteLength) {
    return _audio.durationForBytes(byteLength);
  }

  @override
  Future<SpeechUpdate> accept(Uint8List pcm) async {
    if (_disposed || pcm.isEmpty) {
      return const SpeechUpdate();
    }
    try {
      final resultReady = await _recognizer.acceptWaveformBytes(pcm);
      final json = resultReady
          ? await _recognizer.getResult()
          : await _recognizer.getPartialResult();
      return VoskResultParser.parse(json, isFinal: resultReady);
    } catch (error) {
      throw SpeechRecognitionException(cause: error);
    }
  }

  @override
  Future<SpeechUpdate> finish() async {
    if (_disposed) {
      return const SpeechUpdate();
    }
    try {
      final json = await _recognizer.getFinalResult();
      return VoskResultParser.parse(json, isFinal: true);
    } catch (error) {
      throw SpeechRecognitionException(cause: error);
    }
  }

  @override
  Future<void> reset() async {
    if (_disposed) {
      return;
    }
    try {
      await _recognizer.reset();
    } catch (error) {
      throw SpeechRecognitionException(cause: error);
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    try {
      await _recognizer.dispose();
    } finally {
      await _audio.dispose();
    }
  }
}

SpeechBackend createSpeechBackend() => FfmpegVoskSpeechBackend();
