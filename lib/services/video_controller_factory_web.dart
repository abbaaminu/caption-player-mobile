import 'dart:js_interop';

import 'package:file_picker/file_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:web/web.dart' as web;

import '../utils/media_format.dart';

Future<VideoPlayerController> createVideoController(PlatformFile file) async {
  final extension = normalizeMediaExtension(file.extension);
  if (extension != null && !isSupportedMediaExtension(extension)) {
    throw UnsupportedError('Unsupported media type: $extension');
  }

  final bytes = await file.readAsBytes();
  if (bytes.isEmpty) {
    throw StateError('The selected media file is empty.');
  }

  final blob = web.Blob(
    <web.BlobPart>[bytes.toJS].toJS,
    web.BlobPropertyBag(type: mimeTypeForExtension(extension)),
  );
  final objectUrl = web.URL.createObjectURL(blob);
  return _BlobVideoPlayerController(Uri.parse(objectUrl), objectUrl: objectUrl);
}

/// Revokes the browser object URL once the controller is disposed so the file
/// contents can be garbage collected.
class _BlobVideoPlayerController extends VideoPlayerController {
  _BlobVideoPlayerController(super.url, {required this.objectUrl})
    : super.networkUrl();

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
