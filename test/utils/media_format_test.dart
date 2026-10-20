import 'package:flutter_test/flutter_test.dart';
import 'package:live_caption_player/utils/media_format.dart';

void main() {
  group('media extensions', () {
    test('normalizes case and a leading dot', () {
      expect(normalizeMediaExtension(' .MP4 '), 'mp4');
      expect(normalizeMediaExtension(''), isNull);
      expect(normalizeMediaExtension('  '), isNull);
      expect(normalizeMediaExtension(null), isNull);
    });

    test('recognizes supported video and audio formats', () {
      expect(isSupportedMediaExtension('MP4'), isTrue);
      expect(isSupportedMediaExtension('.webm'), isTrue);
      expect(isSupportedMediaExtension('mp3'), isTrue);
      expect(isSupportedMediaExtension('avi'), isFalse);
      expect(isSupportedMediaExtension(null), isFalse);
    });

    test('distinguishes audio formats', () {
      expect(isAudioMediaExtension('mp3'), isTrue);
      expect(isAudioMediaExtension('M4A'), isTrue);
      expect(isAudioMediaExtension('mp4'), isFalse);
      expect(isAudioMediaExtension(null), isFalse);
    });

    test('maps extensions to MIME types used for web blobs', () {
      expect(mimeTypeForExtension('mp4'), 'video/mp4');
      expect(mimeTypeForExtension('.M4V'), 'video/x-m4v');
      expect(mimeTypeForExtension('webm'), 'video/webm');
      expect(mimeTypeForExtension('mp3'), 'audio/mpeg');
      expect(mimeTypeForExtension('ogg'), 'audio/ogg');
      expect(mimeTypeForExtension('mkv'), 'application/octet-stream');
      expect(mimeTypeForExtension(null), 'application/octet-stream');
    });

    test('every supported extension has a specific MIME type', () {
      for (final extension in supportedMediaExtensions) {
        expect(
          mimeTypeForExtension(extension),
          isNot('application/octet-stream'),
          reason: extension,
        );
      }
    });
  });

  group('formatPlaybackDuration', () {
    test('formats minutes and seconds', () {
      expect(formatPlaybackDuration(Duration.zero), '0:00');
      expect(formatPlaybackDuration(const Duration(seconds: 5)), '0:05');
      expect(formatPlaybackDuration(const Duration(seconds: 65)), '1:05');
      expect(
        formatPlaybackDuration(const Duration(minutes: 59, seconds: 59)),
        '59:59',
      );
    });

    test('formats hours', () {
      expect(
        formatPlaybackDuration(
          const Duration(hours: 1, minutes: 2, seconds: 3),
        ),
        '1:02:03',
      );
      expect(formatPlaybackDuration(const Duration(hours: 12)), '12:00:00');
    });

    test('clamps negative durations', () {
      expect(formatPlaybackDuration(const Duration(seconds: -4)), '0:00');
    });
  });
}
