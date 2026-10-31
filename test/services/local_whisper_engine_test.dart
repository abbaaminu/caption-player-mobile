import 'dart:async';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_whisper_ggml/flutter_whisper.dart';
import 'package:live_caption_player/services/media_audio_source.dart';
import 'package:live_caption_player/services/speech_service.dart';

void main() {
  group('LocalWhisperRecognitionEngine', () {
    test('captions the audio that has just played', () {
      fakeAsync((async) {
        var position = Duration.zero;
        var clock = DateTime(2026);
        final source = _RecordingSource();
        final engine = _engine('hello there', clock: () => clock);
        final results = <String>[];

        _initialize(engine, async);
        _listen(engine, source, () => position, results);
        async.flushMicrotasks();

        // Nothing has played yet, so there is no audio to caption.
        expect(source.ranges, isEmpty);

        position = const Duration(seconds: 2);
        clock = clock.add(const Duration(seconds: 2));
        async.elapse(const Duration(seconds: 2));
        async.flushMicrotasks();

        expect(source.ranges.last, (Duration.zero, const Duration(seconds: 2)));
        expect(results, ['hello there']);

        position = const Duration(seconds: 6);
        clock = clock.add(const Duration(seconds: 2));
        async.elapse(const Duration(seconds: 2));
        async.flushMicrotasks();

        // A trailing window never reaches past the playhead.
        final (start, window) = source.ranges.last;
        expect(start, const Duration(seconds: 1));
        expect(window, const Duration(seconds: 5));
        expect(start + window, position);

        engine.dispose();
        async.flushMicrotasks();
      });
    });

    test('drops Whisper silence cues and clears the caption line', () {
      fakeAsync((async) {
        var position = Duration.zero;
        var clock = DateTime(2026);
        final source = _RecordingSource();
        final engine = _engine('[BLANK_AUDIO]', clock: () => clock);
        final results = <String>[];

        _initialize(engine, async);
        _listen(engine, source, () => position, results);

        for (var window = 1; window <= 2; window++) {
          position = Duration(seconds: window * 2);
          clock = clock.add(const Duration(seconds: 2));
          async.elapse(const Duration(seconds: 2));
          async.flushMicrotasks();
        }

        expect(results, ['']);
        expect(results, isNot(contains('[BLANK_AUDIO]')));

        engine.dispose();
        async.flushMicrotasks();
      });
    });

    test('moves the window to the seek target', () {
      fakeAsync((async) {
        var position = const Duration(seconds: 10);
        var clock = DateTime(2026);
        final source = _RecordingSource();
        final engine = _engine('hello', clock: () => clock);

        _initialize(engine, async);
        _listen(engine, source, () => position, <String>[]);
        async.flushMicrotasks();

        position = const Duration(seconds: 12);
        clock = clock.add(const Duration(seconds: 2));
        async.elapse(const Duration(seconds: 2));
        async.flushMicrotasks();
        expect(source.ranges.last.$1, const Duration(seconds: 10));

        position = const Duration(seconds: 42);
        clock = clock.add(const Duration(milliseconds: 100));
        engine.resetTimeline();
        async.flushMicrotasks();

        position = const Duration(seconds: 44);
        clock = clock.add(const Duration(seconds: 2));
        async.elapse(const Duration(seconds: 2));
        async.flushMicrotasks();

        expect(source.ranges.last.$1, const Duration(seconds: 42));
        expect(source.ranges.last.$2, const Duration(seconds: 2));

        engine.dispose();
        async.flushMicrotasks();
      });
    });

    test('discards a transcript produced for an abandoned playhead', () {
      fakeAsync((async) {
        var position = Duration.zero;
        var clock = DateTime(2026);
        final source = _RecordingSource();
        final gate = Completer<void>();
        final engine = _engineWithBackend(
          _FakeBackend('hello', gate: gate),
          clock: () => clock,
        );
        final results = <String>[];

        _initialize(engine, async);
        _listen(engine, source, () => position, results);

        position = const Duration(seconds: 2);
        clock = clock.add(const Duration(seconds: 2));
        async.elapse(const Duration(seconds: 2));
        async.flushMicrotasks();
        expect(source.ranges, isNotEmpty);

        // Playback jumped while the window was being transcribed.
        position = const Duration(minutes: 3);
        clock = clock.add(const Duration(seconds: 1));
        gate.complete();
        async.flushMicrotasks();
        expect(results, isEmpty);

        // Captions resume from the new playhead.
        position = const Duration(minutes: 3, seconds: 4);
        clock = clock.add(const Duration(seconds: 2));
        async.elapse(const Duration(seconds: 2));
        async.flushMicrotasks();
        expect(results, ['hello']);

        engine.dispose();
        async.flushMicrotasks();
      });
    });
    test('keeps a transcript when the playhead stalls while buffering', () {
      fakeAsync((async) {
        var position = Duration.zero;
        var clock = DateTime(2026);
        final source = _RecordingSource();
        final backend = _FakeBackend('hello');
        final engine = _engineWithBackend(backend, clock: () => clock);
        final results = <String>[];

        _initialize(engine, async);
        _listen(engine, source, () => position, results);

        position = const Duration(seconds: 2);
        clock = clock.add(const Duration(seconds: 2));
        async.elapse(const Duration(seconds: 2));
        async.flushMicrotasks();
        expect(results, ['hello']);

        final gate = Completer<void>();
        backend
          ..gate = gate
          ..text = 'again';

        position = const Duration(seconds: 4);
        clock = clock.add(const Duration(seconds: 2));
        async.elapse(const Duration(seconds: 2));
        async.flushMicrotasks();
        expect(source.ranges, hasLength(2));

        // The player stalls while the window is transcribed, so the playhead
        // stays put while the wall clock keeps running.
        clock = clock.add(const Duration(seconds: 10));
        gate.complete();
        async.flushMicrotasks();

        expect(results, ['hello', 'again']);

        engine.dispose();
        async.flushMicrotasks();
      });
    });
  });

  group('cleanTranscript', () {
    test('removes silence annotations', () {
      expect(cleanTranscript(' [BLANK_AUDIO] '), isEmpty);
      expect(cleanTranscript('[SILENCE] (inaudible)'), isEmpty);
      expect(cleanTranscript('Hello [BLANK_AUDIO] world'), 'Hello world');
    });

    test('keeps audio cues that describe the scene', () {
      expect(cleanTranscript('[Music] Hello'), '[Music] Hello');
    });
  });
}

LocalWhisperRecognitionEngine _engine(
  String transcript, {
  required DateTime Function() clock,
}) {
  return _engineWithBackend(_FakeBackend(transcript), clock: clock);
}

LocalWhisperRecognitionEngine _engineWithBackend(
  WhisperBackend backend, {
  required DateTime Function() clock,
}) {
  return LocalWhisperRecognitionEngine(
    loadModel: ({required void Function(int percent) onProgress}) async {
      onProgress(100);
      return FlutterWhisper.withBackend(backend);
    },
    now: clock,
  );
}

void _initialize(LocalWhisperRecognitionEngine engine, FakeAsync async) {
  var ready = false;
  unawaited(
    engine
        .initialize(onError: (_, _) {}, onStatus: (_) {}, onProgress: (_) {})
        .then((value) => ready = value),
  );
  async.flushMicrotasks();
  expect(ready, isTrue);
}

void _listen(
  LocalWhisperRecognitionEngine engine,
  MediaAudioSource source,
  Duration Function() position,
  List<String> results,
) {
  unawaited(
    engine.listen(
      onResult: (words, _) => results.add(words),
      onError: (_) {},
      audioSource: source,
      position: position,
    ),
  );
}

class _FakeBackend implements WhisperBackend {
  _FakeBackend(this.text, {this.gate});

  String text;

  /// When set, the next transcription waits for this gate to complete.
  Completer<void>? gate;

  @override
  Future<WhisperResult> transcribe(
    Float32List samples,
    WhisperTranscribeConfig config, {
    void Function(int progress)? onProgress,
    void Function(WhisperSegment segment)? onSegment,
  }) async {
    final pending = gate;
    if (pending != null) {
      gate = null;
      await pending.future;
    }
    onProgress?.call(100);
    return WhisperResult(
      language: 'en',
      segments: [
        WhisperSegment(
          text: text,
          start: Duration.zero,
          end: Duration(milliseconds: samples.length ~/ 16),
        ),
      ],
    );
  }

  @override
  void cancel() {}

  @override
  void dispose() {}
}

class _RecordingSource implements MediaAudioSource {
  final List<(Duration, Duration)> ranges = <(Duration, Duration)>[];

  @override
  Future<Float32List> readSamplesAt(
    Duration position,
    Duration duration,
  ) async {
    ranges.add((position, duration));
    final length = (duration.inMicroseconds * 16000 / 1000000).round();
    return Float32List(length);
  }
}
