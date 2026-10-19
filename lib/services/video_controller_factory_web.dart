import 'package:file_picker/file_picker.dart';
import 'package:video_player/video_player.dart';

Future<VideoPlayerController> createVideoController(PlatformFile file) async {
  final bytes = await file.readAsBytes();
  final extension = file.extension?.toLowerCase();
  final mimeType = switch (extension) {
    'webm' => 'video/webm',
    'mov' => 'video/quicktime',
    'm4v' => 'video/x-m4v',
    _ => 'video/mp4',
  };
  final uri = Uri.dataFromBytes(bytes, mimeType: mimeType);
  return VideoPlayerController.networkUrl(uri);
}
