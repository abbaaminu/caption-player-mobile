import 'package:file_picker/file_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:web/web.dart' as web;

import '../utils/media_format.dart';

Future<VideoPlayerController> createVideoController(PlatformFile file) async {
  final extension = normalizeMediaExtension(file.extension);
  if (extension != null && !isSupportedMediaExtension(extension)) {
    throw UnsupportedError('Unsupported media type: $extension');
  }

  final uri = file.uri;
  if (!uri.isAbsolute || (uri.scheme != 'blob' && uri.scheme != 'data')) {
    throw StateError('The selected media file is no longer available.');
  }
  // The web picker reports an empty file as a null synchronous length, so the
  // asynchronous length is used to detect files that cannot be played.
  final length = await file.length();
  if (length != null && length <= 0) {
    throw StateError('The selected media file is empty.');
  }

  final videoPlayerOptions = VideoPlayerOptions(mixWithOthers: true);
  if (uri.scheme == 'blob') {
    return _BlobVideoPlayerController(
      uri,
      objectUrl: uri.toString(),
      videoPlayerOptions: videoPlayerOptions,
    );
  }

  return VideoPlayerController.networkUrl(
    uri,
    videoPlayerOptions: videoPlayerOptions,
  );
}

/// Revokes the file picker's browser object URL after playback is disposed.
class _BlobVideoPlayerController extends VideoPlayerController {
  _BlobVideoPlayerController(
    super.url, {
    required this.objectUrl,
    required VideoPlayerOptions videoPlayerOptions,
  }) : super.networkUrl(videoPlayerOptions: videoPlayerOptions);

  final String objectUrl;
  bool _objectUrlRevoked = false;

  @override
  Future<void> dispose() async {
    await super.dispose();
    if (!_objectUrlRevoked) {
      _objectUrlRevoked = true;
      web.URL.revokeObjectURL(objectUrl);
    }
  }
}
