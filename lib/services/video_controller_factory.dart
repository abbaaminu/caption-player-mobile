import 'package:file_picker/file_picker.dart';
import 'package:video_player/video_player.dart';

import 'video_controller_factory_stub.dart'
    if (dart.library.io) 'video_controller_factory_io.dart'
    if (dart.library.html) 'video_controller_factory_web.dart' as platform;

Future<VideoPlayerController> createVideoController(PlatformFile file) {
  return platform.createVideoController(file);
}
