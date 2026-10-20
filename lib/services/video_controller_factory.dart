import 'package:file_picker/file_picker.dart';
import 'package:video_player/video_player.dart';

import 'video_controller_factory_stub.dart'
    if (dart.library.io) 'video_controller_factory_io.dart'
    if (dart.library.js_interop) 'video_controller_factory_web.dart'
    as platform;

/// Injectable factory type so the player can be exercised without a platform
/// file picker or video surface.
typedef VideoControllerFactory =
    Future<VideoPlayerController> Function(PlatformFile file);

/// Builds a controller for a picked local file on the current platform.
Future<VideoPlayerController> createVideoController(PlatformFile file) {
  return platform.createVideoController(file);
}
