import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';

import 'media_audio_source.dart';

const _audioChannel = MethodChannel('live_caption_player/media_audio');

Future<MediaAudioSource> createMediaAudioSource(PlatformFile file) async {
  final path = file.path?.trim();
  if (path == null || path.isEmpty) {
    throw StateError('The selected media does not have a readable file path.');
  }
  return _NativeMediaAudioSource(path);
}

class _NativeMediaAudioSource implements MediaAudioSource {
  const _NativeMediaAudioSource(this.path);

  final String path;

  @override
  Future<Float32List> readSamplesAt(
    Duration position,
    Duration duration,
  ) async {
    final data = await _audioChannel.invokeMethod<Uint8List>('readSamples', {
      'path': path,
      'positionMs': position.inMilliseconds,
      'durationMs': duration.inMilliseconds,
    });
    if (data == null || data.lengthInBytes % 4 != 0) {
      throw const FormatException(
        'Invalid PCM audio data returned by decoder.',
      );
    }
    final bytes = ByteData.sublistView(data);
    return Float32List.fromList(
      List<double>.generate(
        data.lengthInBytes ~/ 4,
        (index) => bytes.getFloat32(index * 4, Endian.little),
        growable: false,
      ),
    );
  }
}
