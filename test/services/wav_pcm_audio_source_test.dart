import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_caption_player/services/speech_backend.dart';
import 'package:live_caption_player/services/wav_pcm_audio_source.dart';

void main() {
  late Directory tempDirectory;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp('caption_wav_test');
  });

  tearDown(() async {
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test('parses 16 kHz mono PCM and reads synchronized byte ranges', () async {
    final path = _writePcmWav(
      tempDirectory,
      sampleCount: 16000,
      sampleRate: 16000,
      channels: 1,
      bitsPerSample: 16,
    );
    final source = await WavPcmAudioSource.open(path, deleteOnDispose: true);

    expect(source.sampleRate, 16000);
    expect(source.channels, 1);
    expect(source.bitsPerSample, 16);
    expect(source.duration, const Duration(seconds: 1));
    expect(source.durationForBytes(32000), const Duration(seconds: 1));

    final chunk = await source.read(
      const Duration(milliseconds: 500),
      const Duration(milliseconds: 250),
    );

    expect(chunk.length, 8000);
    final samples = ByteData.sublistView(chunk);
    expect(samples.getInt16(0, Endian.little), 8000);
    expect(samples.getInt16(2, Endian.little), 8001);

    final tail = await source.read(
      const Duration(milliseconds: 900),
      const Duration(milliseconds: 250),
    );
    expect(tail.length, 3200);

    await source.dispose();
    expect(await File(path).exists(), isFalse);
  });

  test('rejects WAV files that are not 16 kHz mono PCM', () async {
    final path = _writePcmWav(
      tempDirectory,
      sampleCount: 8000,
      sampleRate: 8000,
      channels: 1,
      bitsPerSample: 16,
    );

    await expectLater(
      WavPcmAudioSource.open(path),
      throwsA(isA<MediaAudioExtractionException>()),
    );
  });

  test('rejects non-WAV input', () async {
    final path = '${tempDirectory.path}/not-audio.wav';
    await File(path).writeAsBytes(Uint8List.fromList(List<int>.filled(64, 7)));

    await expectLater(
      WavPcmAudioSource.open(path),
      throwsA(isA<MediaAudioExtractionException>()),
    );
  });
}

String _writePcmWav(
  Directory directory, {
  required int sampleCount,
  required int sampleRate,
  required int channels,
  required int bitsPerSample,
}) {
  final bytesPerSample = bitsPerSample ~/ 8;
  final dataLength = sampleCount * channels * bytesPerSample;
  final fileBytes = Uint8List(44 + dataLength);
  final data = ByteData.sublistView(fileBytes);

  void writeAscii(int offset, String value) {
    for (var index = 0; index < value.length; index += 1) {
      fileBytes[offset + index] = value.codeUnitAt(index);
    }
  }

  writeAscii(0, 'RIFF');
  data.setUint32(4, 36 + dataLength, Endian.little);
  writeAscii(8, 'WAVE');
  writeAscii(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, channels, Endian.little);
  data.setUint32(24, sampleRate, Endian.little);
  data.setUint32(28, sampleRate * channels * bytesPerSample, Endian.little);
  data.setUint16(32, channels * bytesPerSample, Endian.little);
  data.setUint16(34, bitsPerSample, Endian.little);
  writeAscii(36, 'data');
  data.setUint32(40, dataLength, Endian.little);

  if (bitsPerSample == 16) {
    final samples = ByteData.sublistView(fileBytes, 44);
    for (var index = 0; index < sampleCount; index += 1) {
      samples.setInt16(index * 2, index, Endian.little);
    }
  }

  final path = '${directory.path}/sample.wav';
  File(path).writeAsBytesSync(fileBytes);
  return path;
}
