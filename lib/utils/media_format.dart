/// Extensions offered by the file picker. Keep this list in sync with
/// [mimeTypeForExtension] and the video_player platform support.
const supportedMediaExtensions = <String>[
  'mp4',
  'm4v',
  'mov',
  'webm',
  '3gp',
  'mp3',
  'm4a',
  'aac',
  'wav',
  'flac',
  'ogg',
];

const audioMediaExtensions = <String>{
  'mp3',
  'm4a',
  'aac',
  'wav',
  'flac',
  'ogg',
};

String? normalizeMediaExtension(String? extension) {
  if (extension == null) {
    return null;
  }
  final normalized = extension.trim().toLowerCase().replaceFirst('.', '');
  return normalized.isEmpty ? null : normalized;
}

bool isSupportedMediaExtension(String? extension) {
  final normalized = normalizeMediaExtension(extension);
  return normalized != null && supportedMediaExtensions.contains(normalized);
}

bool isAudioMediaExtension(String? extension) {
  final normalized = normalizeMediaExtension(extension);
  return normalized != null && audioMediaExtensions.contains(normalized);
}

String mimeTypeForExtension(String? extension) {
  return switch (normalizeMediaExtension(extension)) {
    'mp4' => 'video/mp4',
    'm4v' => 'video/x-m4v',
    'mov' => 'video/quicktime',
    'webm' => 'video/webm',
    '3gp' => 'video/3gpp',
    'mp3' => 'audio/mpeg',
    'm4a' => 'audio/mp4',
    'aac' => 'audio/aac',
    'wav' => 'audio/wav',
    'flac' => 'audio/flac',
    'ogg' => 'audio/ogg',
    _ => 'application/octet-stream',
  };
}

/// Formats a playback position as `M:SS` or `H:MM:SS`.
String formatPlaybackDuration(Duration duration) {
  final totalSeconds = duration.inSeconds < 0 ? 0 : duration.inSeconds;
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;
  final paddedSeconds = seconds.toString().padLeft(2, '0');

  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:$paddedSeconds';
  }
  return '${minutes.toString().padLeft(2, '0')}:$paddedSeconds';
}
