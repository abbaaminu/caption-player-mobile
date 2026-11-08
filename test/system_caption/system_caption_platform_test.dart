import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_caption_player/system_caption/system_caption_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SystemCaptionStatus', () {
    test('parses the native map', () {
      final status = SystemCaptionStatus.fromMap({
        'supported': true,
        'running': false,
        'overlayGranted': true,
        'micGranted': true,
        'notificationsGranted': false,
        'sdkInt': 35,
      });

      expect(status.supported, isTrue);
      expect(status.sdkInt, 35);
      expect(status.readyToStart, isTrue);
    });

    test('is not ready without overlay or audio permission', () {
      expect(
        SystemCaptionStatus.fromMap({
          'supported': true,
          'micGranted': true,
        }).readyToStart,
        isFalse,
      );
      expect(
        SystemCaptionStatus.fromMap({
          'supported': true,
          'overlayGranted': true,
        }).readyToStart,
        isFalse,
      );
    });

    test('is never ready on unsupported Android versions', () {
      expect(
        SystemCaptionStatus.fromMap({
          'supported': false,
          'overlayGranted': true,
          'micGranted': true,
        }).readyToStart,
        isFalse,
      );
    });
  });

  group('CaptionStyle', () {
    test('clamps out-of-range native values', () {
      final style = CaptionStyle.fromMap({
        'textSizeSp': 99.0,
        'backgroundOpacity': 5,
        'bottomOffsetDp': -4,
      });

      expect(style.textSizeSp, 32);
      expect(style.backgroundOpacity, 30);
      expect(style.bottomOffsetDp, 0);
    });

    test('falls back to defaults for missing values', () {
      expect(CaptionStyle.fromMap({}), const CaptionStyle());
    });

    test('round-trips through its map', () {
      const style = CaptionStyle(
        textSizeSp: 20,
        backgroundOpacity: 70,
        bottomOffsetDp: 120,
      );
      expect(CaptionStyle.fromMap(style.toMap()), style);
    });
  });

  group('MethodChannelSystemCaptionPlatform', () {
    const channel = MethodChannel('test/system_caption');
    final calls = <MethodCall>[];

    setUp(() {
      calls.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            switch (call.method) {
              case 'getStatus':
                return {
                  'supported': true,
                  'running': true,
                  'overlayGranted': true,
                  'micGranted': true,
                  'notificationsGranted': true,
                  'sdkInt': 34,
                };
              case 'requestRuntimePermissions':
                return true;
            }
            return null;
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('reads status', () async {
      final platform = MethodChannelSystemCaptionPlatform(channel: channel);
      final status = await platform.status();

      expect(status.running, isTrue);
      expect(status.sdkInt, 34);
    });

    test('sends the style to the native side', () async {
      final platform = MethodChannelSystemCaptionPlatform(channel: channel);
      await platform.setStyle(const CaptionStyle(textSizeSp: 22));

      expect(calls.single.method, 'setStyle');
      expect((calls.single.arguments as Map)['textSizeSp'], 22.0);
    });

    test('reports whether audio permission was granted', () async {
      final platform = MethodChannelSystemCaptionPlatform(channel: channel);
      expect(await platform.requestRuntimePermissions(), isTrue);
    });
  });
}
