import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_caption_player/services/speech_service.dart';

void main() {
  group('SpeechService.initialize', () {
    test(
      'reports an unsupported platform without starting the engine',
      () async {
        final engine = _FakeEngine(supported: false);
        final service = SpeechService(engine: engine);
        final statuses = <SpeechStatus>[];
        String? error;

        final available = await service.initialize(
          onError: (message) => error = message,
          onStatus: statuses.add,
        );

        expect(available, isFalse);
        expect(engine.initializeCalls, 0);
        expect(statuses, isEmpty);
        expect(error, const UnsupportedSpeechPlatformException().userMessage);
        expect(service.isInitialized, isFalse);
      },
    );

    test('maps a denied permission to actionable wording', () async {
      final engine = _FakeEngine(initializationError: 'permission denied');
      final service = SpeechService(engine: engine);
      String? error;

      final available = await service.initialize(
        onError: (message) => error = message,
      );

      expect(available, isFalse);
      expect(error, const SpeechPermissionException().userMessage);
    });

    test('returns true once the platform recognizer is ready', () async {
      final engine = _FakeEngine();
      final service = SpeechService(engine: engine);
      final statuses = <SpeechStatus>[];

      final available = await service.initialize(
        onError: (_) {},
        onStatus: statuses.add,
      );

      expect(available, isTrue);
      expect(service.isInitialized, isTrue);
      expect(engine.initializeCalls, 1);
      expect(statuses, [SpeechStatus.preparing]);
    });
  });

  group('SpeechService listening', () {
    test('streams partial and final captions without duplicate updates', () {
      fakeAsync((async) {
        final engine = _FakeEngine();
        final service = SpeechService(engine: engine);
        final results = <String>[];
        String? error;

        service.initialize(onError: (_) {});
        async.flushMicrotasks();
        service.startListening(
          onResult: results.add,
          onError: (message) => error = message,
        );
        async.flushMicrotasks();

        engine.emit('hello world', false);
        engine.emit('hello world', false);
        engine.emit('hello world again', false);
        engine.emit('hello world again', false);
        engine.emit('hello world again', true);

        expect(results, ['', 'hello world', 'hello world again']);
        expect(error, isNull);
        expect(engine.listenCalls, 1);

        service.dispose();
        async.flushMicrotasks();
      });
    });

    test('keeps committed words when the recognizer renews its session', () {
      fakeAsync((async) {
        final engine = _FakeEngine();
        final service = SpeechService(
          engine: engine,
          initialRestartDelay: const Duration(milliseconds: 5),
        );
        final results = <String>[];
        final statuses = <SpeechStatus>[];

        service.initialize(onError: (_) {}, onStatus: statuses.add);
        async.flushMicrotasks();
        service.startListening(
          onResult: results.add,
          onError: (_) {},
          onStatus: statuses.add,
        );
        async.flushMicrotasks();

        engine.emit('first phrase', true);
        engine.finishSession();
        async.elapse(const Duration(milliseconds: 5));
        async.flushMicrotasks();

        expect(engine.listenCalls, 2);
        expect(statuses, contains(SpeechStatus.listening));

        engine.emit('second phrase', true);

        expect(results.last, 'first phrase second phrase');
        expect(service.isActive, isTrue);

        service.dispose();
        async.flushMicrotasks();
      });
    });

    test('resets the restart backoff after each successful session', () {
      fakeAsync((async) {
        final engine = _FakeEngine();
        final service = SpeechService(
          engine: engine,
          initialRestartDelay: const Duration(milliseconds: 10),
        );

        service.initialize(onError: (_) {});
        async.flushMicrotasks();
        service.startListening(onResult: (_) {}, onError: (_) {});
        async.flushMicrotasks();

        engine.emit('first phrase', true);
        engine.finishSession();
        async.elapse(const Duration(milliseconds: 10));
        async.flushMicrotasks();
        expect(engine.listenCalls, 2);

        engine.emit('second phrase', true);
        engine.finishSession();
        async.elapse(const Duration(milliseconds: 10));
        async.flushMicrotasks();
        expect(engine.listenCalls, 3);

        service.dispose();
        async.flushMicrotasks();
      });
    });

    test('pause stops the microphone and startListening resumes', () {
      fakeAsync((async) {
        final engine = _FakeEngine();
        final service = SpeechService(engine: engine);
        final results = <String>[];
        final statuses = <SpeechStatus>[];

        service.initialize(onError: (_) {});
        async.flushMicrotasks();
        service.startListening(
          onResult: results.add,
          onError: (_) {},
          onStatus: statuses.add,
        );
        async.flushMicrotasks();

        engine.emit('hello', false);
        service.pause();
        async.flushMicrotasks();

        expect(engine.stopCalls, 1);
        expect(service.isActive, isFalse);
        expect(statuses, contains(SpeechStatus.paused));
        expect(results.last, 'hello');

        service.startListening(
          onResult: results.add,
          onError: (_) {},
          onStatus: statuses.add,
        );
        async.flushMicrotasks();

        expect(engine.listenCalls, 2);
        expect(results.last, isEmpty);

        engine.emit('again', true);
        expect(results.last, 'again');

        service.dispose();
        async.flushMicrotasks();
      });
    });

    test('gives up after six consecutive listen failures', () {
      fakeAsync((async) {
        final engine = _FakeEngine(listenError: StateError('recognizer busy'));
        final service = SpeechService(
          engine: engine,
          initialRestartDelay: const Duration(milliseconds: 1),
          maximumRestartDelay: const Duration(milliseconds: 5),
        );
        final errors = <String>[];
        final statuses = <SpeechStatus>[];

        service.initialize(onError: (_) {});
        async.flushMicrotasks();
        service.startListening(
          onResult: (_) {},
          onError: errors.add,
          onStatus: statuses.add,
        );
        async.flushMicrotasks();

        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();

        expect(engine.listenCalls, 6);
        expect(errors, [const SpeechRecognitionException().userMessage]);
        expect(statuses.last, SpeechStatus.paused);
        expect(service.isActive, isFalse);

        service.dispose();
        async.flushMicrotasks();
      });
    });

    test('stop cancels the engine and ignores late results', () {
      fakeAsync((async) {
        final engine = _FakeEngine();
        final service = SpeechService(engine: engine);
        final results = <String>[];

        service.initialize(onError: (_) {});
        async.flushMicrotasks();
        service.startListening(onResult: results.add, onError: (_) {});
        async.flushMicrotasks();

        engine.emit('before stop', true);
        service.stop();
        async.flushMicrotasks();
        engine.emit('after stop', true);

        expect(engine.cancelCalls, 1);
        expect(results.last, 'before stop');
        expect(service.isActive, isFalse);
      });
    });
  });

  group('SpeechService wording', () {
    test('maps recognizer errors to actionable messages', () {
      expect(
        userFriendlyError('permission denied', isWeb: false),
        const SpeechPermissionException().userMessage,
      );
      expect(
        userFriendlyError('network timeout'),
        contains('network connection'),
      );
      expect(userFriendlyError('no speech detected'), contains('No speech'));
      expect(userFriendlyError('recognizer busy'), contains('busy'));
      expect(userFriendlyError('audio error'), contains('microphone'));
      expect(
        userFriendlyError('unknown failure'),
        const SpeechRecognitionException().userMessage,
      );
    });

    test('describes each caption status for the player chip', () {
      expect(
        SpeechService.statusMessage(SpeechStatus.preparing),
        'Preparing live captions…',
      );
      expect(
        SpeechService.statusMessage(SpeechStatus.listening),
        'Live captions on',
      );
      expect(
        SpeechService.statusMessage(SpeechStatus.paused),
        'Live captions paused',
      );
    });
  });
}

class _FakeEngine implements SpeechRecognitionEngine {
  _FakeEngine({
    this.supported = true,
    this.initializationError,
    this.listenError,
  });

  final bool supported;
  final String? initializationError;
  final Object? listenError;

  int initializeCalls = 0;
  int listenCalls = 0;
  int stopCalls = 0;
  int cancelCalls = 0;
  bool listening = false;

  void Function(String words, bool isFinal)? _onResult;
  void Function(SpeechEngineStatus status)? _onStatus;

  @override
  bool get isSupported => supported;

  @override
  bool get isListening => listening;

  @override
  Future<bool> initialize({
    required void Function(String message, bool permanent) onError,
    required void Function(SpeechEngineStatus status) onStatus,
  }) async {
    initializeCalls += 1;
    _onStatus = onStatus;
    final error = initializationError;
    if (error != null) {
      onError(error, true);
      return false;
    }
    return true;
  }

  @override
  Future<void> listen({
    required void Function(String words, bool isFinal) onResult,
    required Duration listenFor,
    required Duration pauseFor,
  }) async {
    listenCalls += 1;
    _onResult = onResult;
    final error = listenError;
    if (error != null) {
      listening = false;
      throw error;
    }
    listening = true;
  }

  @override
  Future<void> stop() async {
    stopCalls += 1;
    listening = false;
  }

  @override
  Future<void> cancel() async {
    cancelCalls += 1;
    listening = false;
  }

  void emit(String words, bool isFinal) {
    _onResult?.call(words, isFinal);
  }

  void finishSession() {
    listening = false;
    _onStatus?.call(SpeechEngineStatus.done);
  }
}
