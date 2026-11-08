import 'package:file_picker/file_picker.dart';

import '../utils/media_format.dart';

/// Abstraction over the native file picker so playback flows stay testable.
abstract interface class MediaPickerService {
  Future<PlatformFile?> pickMedia();
}

class FilePickerMediaPickerService implements MediaPickerService {
  @override
  Future<PlatformFile?> pickMedia() {
    return FilePicker.pickFile(
      dialogTitle: 'Choose a video or audio file',
      type: FileType.custom,
      allowedExtensions: supportedMediaExtensions,
    );
  }
}
