import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'speech_backend.dart';

/// Random-access reader for the 16 kHz, mono, 16-bit PCM WAV files produced by
/// the FFmpeg extraction step. Keeping the file on disk avoids holding an
/// entire movie's audio in memory.
class WavPcmAudioSource {
  WavPcmAudioSource._({
    required RandomAccessFile file,
    required this.path,
    required this.sampleRate,
    required this.channels,
    required this.bitsPerSample,
    required this.dataOffset,
    required this.dataLength,
    required this.duration,
    required bool deleteOnDispose,
  }) : _file = file,
       _deleteOnDispose = deleteOnDispose;

  static const int _headerSize = 12;
  static const int _chunkHeaderSize = 8;

  final RandomAccessFile _file;
  final String path;
  final int sampleRate;
  final int channels;
  final int bitsPerSample;
  final int dataOffset;
  final int dataLength;
  final Duration duration;
  final bool _deleteOnDispose;

  bool _closed = false;

  int get blockAlign => channels * (bitsPerSample ~/ 8);
  int get bytesPerSecond => sampleRate * blockAlign;

  static Future<WavPcmAudioSource> open(
    String path, {
    bool deleteOnDispose = false,
  }) async {
    final file = File(path);
    final handle = await file.open();
    try {
      final length = await handle.length();
      if (length < _headerSize + _chunkHeaderSize) {
        throw const MediaAudioExtractionException(
          cause: 'The extracted WAV file is too short.',
        );
      }

      await handle.setPosition(0);
      final header = await handle.read(_headerSize);
      if (header.length < _headerSize ||
          _ascii(header, 0, 4) != 'RIFF' ||
          _ascii(header, 8, 4) != 'WAVE') {
        throw const MediaAudioExtractionException(
          cause: 'The extracted audio is not a RIFF/WAVE file.',
        );
      }

      int? sampleRate;
      int? channels;
      int? bitsPerSample;
      int? formatTag;
      int? dataOffset;
      int? dataLength;

      var cursor = _headerSize;
      while (cursor + _chunkHeaderSize <= length) {
        await handle.setPosition(cursor);
        final chunkHeader = await handle.read(_chunkHeaderSize);
        if (chunkHeader.length < _chunkHeaderSize) {
          break;
        }
        final chunkId = _ascii(chunkHeader, 0, 4);
        final chunkSize = ByteData.sublistView(
          chunkHeader,
          4,
          8,
        ).getUint32(0, Endian.little);
        final payloadOffset = cursor + _chunkHeaderSize;
        final available = length - payloadOffset;
        final payloadSize = math.min(chunkSize, math.max(0, available));

        if (chunkId == 'fmt ') {
          await handle.setPosition(payloadOffset);
          final fmt = await handle.read(math.min(payloadSize, 64));
          if (fmt.length < 16) {
            throw const MediaAudioExtractionException(
              cause: 'The extracted WAV format chunk is incomplete.',
            );
          }
          final fmtData = ByteData.sublistView(fmt);
          formatTag = fmtData.getUint16(0, Endian.little);
          channels = fmtData.getUint16(2, Endian.little);
          sampleRate = fmtData.getUint32(4, Endian.little);
          bitsPerSample = fmtData.getUint16(14, Endian.little);
        } else if (chunkId == 'data') {
          dataOffset = payloadOffset;
          dataLength = payloadSize;
        }

        if (formatTag != null && dataOffset != null) {
          break;
        }

        // RIFF chunks are padded to an even number of bytes.
        cursor = payloadOffset + chunkSize + (chunkSize.isOdd ? 1 : 0);
      }

      if (formatTag == null ||
          channels == null ||
          sampleRate == null ||
          bitsPerSample == null ||
          formatTag != 1 ||
          channels != 1 ||
          sampleRate != 16000 ||
          bitsPerSample != 16) {
        throw MediaAudioExtractionException(
          cause:
              'Expected 16 kHz mono 16-bit PCM, got format=$formatTag, '
              'channels=$channels, rate=$sampleRate, bits=$bitsPerSample.',
        );
      }
      if (dataOffset == null || dataLength == null || dataLength <= 0) {
        throw const MediaAudioExtractionException(
          cause: 'The extracted WAV file has no PCM data chunk.',
        );
      }

      final blockAlign = channels * (bitsPerSample ~/ 8);
      final bytesPerSecond = sampleRate * blockAlign;
      final duration = Duration(
        microseconds:
            dataLength * Duration.microsecondsPerSecond ~/ bytesPerSecond,
      );

      return WavPcmAudioSource._(
        file: handle,
        path: path,
        sampleRate: sampleRate,
        channels: channels,
        bitsPerSample: bitsPerSample,
        dataOffset: dataOffset,
        dataLength: dataLength,
        duration: duration,
        deleteOnDispose: deleteOnDispose,
      );
    } catch (_) {
      await handle.close();
      if (deleteOnDispose) {
        await _deleteQuietly(path);
      }
      rethrow;
    }
  }

  Future<Uint8List> read(Duration position, Duration maximumLength) async {
    if (_closed) {
      throw const MediaAudioExtractionException(
        cause: 'The extracted audio file is already closed.',
      );
    }

    final clampedMicros = position.inMicroseconds.clamp(
      0,
      duration.inMicroseconds,
    );
    var offset =
        dataOffset +
        (clampedMicros * bytesPerSecond ~/ Duration.microsecondsPerSecond);
    offset -= (offset - dataOffset) % blockAlign;

    final maxBytes =
        maximumLength.inMicroseconds *
        bytesPerSecond ~/
        Duration.microsecondsPerSecond;
    final end = dataOffset + dataLength;
    final available = end - offset;
    if (available <= 0 || maxBytes <= 0) {
      return Uint8List(0);
    }

    final length = math.min(maxBytes, available);
    await _file.setPosition(offset);
    return _file.read(length);
  }

  Duration durationForBytes(int byteLength) {
    if (byteLength <= 0) {
      return Duration.zero;
    }
    return Duration(
      microseconds:
          byteLength * Duration.microsecondsPerSecond ~/ bytesPerSecond,
    );
  }

  Future<void> dispose() async {
    if (_closed) {
      return;
    }
    _closed = true;
    try {
      await _file.close();
    } finally {
      if (_deleteOnDispose) {
        await _deleteQuietly(path);
      }
    }
  }

  static String _ascii(Uint8List bytes, int start, int length) {
    final end = math.min(bytes.length, start + length);
    return String.fromCharCodes(bytes.sublist(start, end));
  }

  static Future<void> _deleteQuietly(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } on FileSystemException {
      // Temporary files are also cleaned by the OS if deletion fails.
    }
  }
}
