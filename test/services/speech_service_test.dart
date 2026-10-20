import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_caption_player/services/speech_backend.dart';
import 'package:live_caption_player/services/speech_service.dart';

void main() {
  group('SpeechService error mapping', () {
    test('explains unsupported web and desktop builds', () {
      final message = SpeechService.userFriendlyError(
        'MissingPluginException',
        isWeb: true,
      );

      expect(message, contains('Android and iOS'));
      expect(message, contains('decode'));
      expect(message, isNot(contains('microphone')));
    });

    test('maps download failures to a first-run network message', () {
      final message = SpeechService.userFriendlyError(
        'SocketException: Network is unreachable',
      );

      expect(message, contains('Connect to the internet'));
      expect(message, contains('first run'));
    });

    test('maps extraction failures to media guidance', () {
      final message = SpeechService.userFriendlyError('FFmpeg returned 1');

      expect(message, contains('audio track'));
      expect(message, contains('MP4'));
    });

    test('maps model failures to storage and retry guidance', () {
      final message = SpeechService.userFriendlyError(
        'Vosk model could not be loaded',
      );

      expect(message, contains('offline speech model'));
      expect(message, contains('free storage'));
    });

    test('uses typed exception messages directly', () {
      final message = SpeechService.userFriendlyError(
        const MediaAudioExtractionException(cause: 'no audio stream'),
      );

      expect(message, contains('audio track'));
    });

    test('classifies network failures', () {
      expect(SpeechService.isNetworkError('SocketException'), isTrue);
      expect(SpeechService.isNetworkError('ffmpeg failed'), isFalse);
    });
  });

  group('SpeechService pipeline', () {
    test('rejects unsupported platforms with a user-facing message', () async {
      final service = SpeechService(
        backend: _FakeSpeechBackend(supported: false),
      );
      String? error;

      final initialized = await service.initialize(
        onError: (message) => error = message,
      );

      expect(initialized, isFalse);
      expect(error, contains('Android and iOS'));
      await service.dispose();
    });

    test('streams recognized media audio into the caption callback', () async {
      final session = _FakeSpeechSession();
      final service = SpeechService(
        backend: _FakeSpeechBackend(session: session),
      );
      final captionReady = Completer<String>();
      var latestCaption = '';
      final playbackStart = DateTime.now();

      final initialized = await service.initialize(onError: fail);
      expect(initialized, isTrue);

      await service.startTranscription(
        mediaPath: '/tmp/example.mp4',
        position: () =>
            const Duration(seconds: 3) +
            Duration(
              milliseconds: DateTime.now()
                  .difference(playbackStart)
                  .inMilliseconds,
            ),
        onResult: (text) {
          latestCaption = text;
          if (text.contains('hello world') && !captionReady.isCompleted) {
            captionReady.complete(text);
          }
        },
        onError: fail,
        onStatus: (_) {},
      );

      final caption = await captionReady.future.timeout(
        const Duration(seconds: 2),
      );
      expect(caption, contains('hello world'));
      expect(service.isActive, isTrue);

      await service.stop();
      expect(service.isActive, isFalse);
      expect(latestCaption, isNotEmpty);
      await service.dispose();
    });

    test('clears the caption when the player seeks', () async {
      final session = _FakeSpeechSession();
      final service = SpeechService(
        backend: _FakeSpeechBackend(session: session),
      );
      final captionReady = Completer<void>();
      var latestCaption = '';
      final playbackStart = DateTime.now();

      await service.initialize(onError: fail);
      await service.startTranscription(
        mediaPath: '/tmp/example.mp4',
        position: () =>
            const Duration(seconds: 3) +
            Duration(
              milliseconds: DateTime.now()
                  .difference(playbackStart)
                  .inMilliseconds,
            ),
        onResult: (text) {
          latestCaption = text;
          if (text.isNotEmpty && !captionReady.isCompleted) {
            captionReady.complete();
          }
        },
        onError: fail,
        onStatus: (_) {},
      );
      await captionReady.future.timeout(const Duration(seconds: 2));

      service.seek(const Duration(seconds: 12));
      await Future<void>.delayed(const Duration(milliseconds: 250));

      expect(latestCaption, isEmpty);
      expect(session.resetCount, greaterThan(0));
      await service.dispose();
    });
  });
}

class _FakeSpeechBackend implements SpeechBackend {
  _FakeSpeechBackend({this.supported = true, _FakeSpeechSession? session})
    : session = session ?? _FakeSpeechSession();

  final bool supported;
  final _FakeSpeechSession session;
  bool disposed = false;

  @override
  bool get isSupported => supported;

  @override
  Future<bool> initialize({
    required void Function(SpeechStatus status) onStatus,
  }) async {
    onStatus(SpeechStatus.downloadingModel);
    onStatus(SpeechStatus.loadingModel);
    return supported;
  }

  @override
  Future<SpeechSession> createSession(String mediaPath) async => session;

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

class _FakeSpeechSession implements SpeechSession {
  static const int _bytesPerSecond = 16000 * 2;

  bool disposed = false;
  int resetCount = 0;
  int acceptCount = 0;

  @override
  int get sampleRate => 16000;

  @override
  Duration get duration => const Duration(minutes: 1);

  @override
  Future<Uint8List> read(Duration position, Duration maximumLength) async {
    final requested =
        maximumLength.inMicroseconds *
        _bytesPerSecond ~/
        Duration.microsecondsPerSecond;
    return Uint8List(requested.clamp(0, 32000));
  }

  @override
  Duration durationForBytes(int byteLength) {
    return Duration(
      microseconds:
          byteLength * Duration.microsecondsPerSecond ~/ _bytesPerSecond,
    );
  }

  @override
  Future<SpeechUpdate> accept(Uint8List pcm) async {
    acceptCount += 1;
    if (acceptCount == 1) {
      return const SpeechUpdate(finalText: 'hello world');
    }
    return const SpeechUpdate(partialText: 'hello world again');
  }

  @override
  Future<SpeechUpdate> finish() async {
    return const SpeechUpdate(finalText: 'final words');
  }

  @override
  Future<void> reset() async {
    resetCount += 1;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}
