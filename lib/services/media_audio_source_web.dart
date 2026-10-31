import 'dart:js_interop';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:web/web.dart' as web;

import 'media_audio_source.dart';

Future<MediaAudioSource> createMediaAudioSource(PlatformFile file) async {
  final uri = file.uri;
  if (!uri.isAbsolute || (uri.scheme != 'blob' && uri.scheme != 'data')) {
    throw StateError('The selected media file is no longer available.');
  }
  return _WebMediaAudioSource(uri);
}

class _WebMediaAudioSource implements MediaAudioSource {
  _WebMediaAudioSource(this.uri);

  final Uri uri;
  Future<_DecodedMediaAudioSource>? _decoded;

  Future<_DecodedMediaAudioSource> _decode() {
    // A failed decode is cleared so a later caption retry can try again.
    return _decoded ??= _decodeMedia(uri).catchError((Object error) {
      _decoded = null;
      throw error;
    });
  }

  @override
  Future<Float32List> readSamplesAt(
    Duration position,
    Duration duration,
  ) async {
    final decoded = await _decode();
    return decoded.readSamplesAt(position, duration);
  }
}

Future<_DecodedMediaAudioSource> _decodeMedia(Uri uri) async {
  final response = await web.window.fetch(uri.toString().toJS).toDart;
  if (!response.ok) {
    throw StateError('The selected media audio could not be read.');
  }
  final data = await response.arrayBuffer().toDart;
  final context = web.AudioContext();
  try {
    final decoded = await context.decodeAudioData(data).toDart;
    final channels = List<Float32List>.generate(
      decoded.numberOfChannels,
      (channel) => decoded.getChannelData(channel).toDart,
      growable: false,
    );
    return _DecodedMediaAudioSource(
      channels: channels,
      sampleRate: decoded.sampleRate,
    );
  } finally {
    await context.close().toDart;
  }
}

class _DecodedMediaAudioSource {
  const _DecodedMediaAudioSource({
    required this.channels,
    required this.sampleRate,
  });

  final List<Float32List> channels;
  final double sampleRate;

  Future<Float32List> readSamplesAt(
    Duration position,
    Duration duration,
  ) async {
    const outputSampleRate = 16000;
    final length = (duration.inMicroseconds * outputSampleRate / 1000000)
        .ceil();
    final output = Float32List(length);
    final channelLength = channels.isEmpty ? 0 : channels.first.length;
    if (length == 0 || channelLength == 0) {
      return output;
    }

    // Web Audio delivers the source rate (often 44.1 kHz or 48 kHz). Whisper
    // needs mono 16 kHz, so mix the channels and resample with linear
    // interpolation instead of dropping neighbouring samples.
    final start = position.inMicroseconds * sampleRate / 1000000;
    final step = sampleRate / outputSampleRate;
    for (var index = 0; index < length; index++) {
      final sourcePosition = start + index * step;
      final base = sourcePosition.floor();
      if (base >= channelLength) {
        break;
      }
      final fraction = sourcePosition - base;
      final next = base + 1 < channelLength ? base + 1 : base;
      var mixed = 0.0;
      for (final channel in channels) {
        final first = channel[base];
        final second = channel[next];
        mixed += first + (second - first) * fraction;
      }
      output[index] = (mixed / channels.length).clamp(-1.0, 1.0);
    }
    return output;
  }
}
