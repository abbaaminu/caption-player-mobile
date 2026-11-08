import 'package:file_picker/file_picker.dart';
import 'package:video_player/video_player.dart';

Future<VideoPlayerController> createVideoController(PlatformFile file) {
  throw UnsupportedError(
    'Media playback is supported on Android, iOS, and the web.',
  );
}
