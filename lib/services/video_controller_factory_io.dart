import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:video_player/video_player.dart';

import '../utils/media_format.dart';

Future<VideoPlayerController> createVideoController(PlatformFile file) async {
  final path = file.path?.trim();
  if (path == null || path.isEmpty) {
    throw StateError('The selected media does not have a readable file path.');
  }

  final extension = normalizeMediaExtension(file.extension);
  if (extension != null && !isSupportedMediaExtension(extension)) {
    throw UnsupportedError('Unsupported media type: $extension');
  }

  final mediaFile = File(path);
  if (!await mediaFile.exists()) {
    throw StateError('The selected media file is no longer available.');
  }
  return VideoPlayerController.file(mediaFile);
}
