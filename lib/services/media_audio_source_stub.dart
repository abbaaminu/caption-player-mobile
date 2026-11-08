import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import 'media_audio_source.dart';

Future<MediaAudioSource> createMediaAudioSource(PlatformFile file) async {
  throw UnsupportedError('Internal audio extraction is not supported here.');
}

class UnsupportedMediaAudioSource implements MediaAudioSource {
  @override
  Future<Float32List> readSamplesAt(
    Duration position,
    Duration duration,
  ) async => throw UnsupportedError(
    'Internal audio extraction is not supported here.',
  );
}
