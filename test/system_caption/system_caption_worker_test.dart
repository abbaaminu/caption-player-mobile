import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_caption_player/system_caption/system_caption_worker.dart';

void main() {
  group('pcm16ToFloat32', () {
    test('converts little-endian 16-bit samples to -1..1 floats', () {
      // 0, 16384 (0.5), -16384 (-0.5), -32768 (-1.0)
      final bytes = Uint8List.fromList([
        0x00,
        0x00,
        0x00,
        0x40,
        0x00,
        0xC0,
        0x00,
        0x80,
      ]);

      final samples = pcm16ToFloat32(bytes);

      expect(samples.length, 4);
      expect(samples[0], 0.0);
      expect(samples[1], closeTo(0.5, 1e-6));
      expect(samples[2], closeTo(-0.5, 1e-6));
      expect(samples[3], closeTo(-1.0, 1e-6));
    });

    test('ignores a trailing odd byte', () {
      expect(pcm16ToFloat32(Uint8List.fromList([0x00, 0x40, 0x01])).length, 1);
    });

    test('returns an empty list for empty input', () {
      expect(pcm16ToFloat32(Uint8List(0)), isEmpty);
    });
  });

  group('isLikelyHallucination', () {
    test('drops stock phrases on very quiet audio', () {
      expect(isLikelyHallucination('Thank you.', rms: 0.004), isTrue);
      expect(isLikelyHallucination('thanks for watching', rms: 0.005), isTrue);
    });

    test('keeps the same words at normal volume', () {
      expect(isLikelyHallucination('Thank you.', rms: 0.08), isFalse);
    });

    test('never drops real sentences', () {
      expect(
        isLikelyHallucination('The meeting starts at nine', rms: 0.004),
        isFalse,
      );
    });
  });
}
