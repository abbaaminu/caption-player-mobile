import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import 'media_audio_source_stub.dart'
    if (dart.library.io) 'media_audio_source_io.dart'
    if (dart.library.js_interop) 'media_audio_source_web.dart'
    as platform;

abstract interface class MediaAudioSource {
  Future<Float32List> readSamplesAt(Duration position, Duration duration);
}

Future<MediaAudioSource> createMediaAudioSource(PlatformFile file) {
  return platform.createMediaAudioSource(file);
}
