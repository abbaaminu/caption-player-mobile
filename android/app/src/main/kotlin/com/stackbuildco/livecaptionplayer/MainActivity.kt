package com.stackbuildco.livecaptionplayer

import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.AudioFormat
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.ceil

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "live_caption_player/media_audio",
        ).setMethodCallHandler { call, result ->
            if (call.method != "readSamples") {
                result.notImplemented()
                return@setMethodCallHandler
            }

            val path = call.argument<String>("path")
            val positionMs = call.argument<Number>("positionMs")?.toLong()
            val durationMs = call.argument<Number>("durationMs")?.toLong()
            if (path == null || positionMs == null || durationMs == null ||
                positionMs < 0 || durationMs <= 0
            ) {
                result.error("invalid_audio_range", "Invalid audio range.", null)
                return@setMethodCallHandler
            }

            Thread {
                try {
                    val samples = readAudioSamples(path, positionMs, durationMs)
                    Handler(Looper.getMainLooper()).post { result.success(samples) }
                } catch (error: Exception) {
                    Handler(Looper.getMainLooper()).post {
                        result.error(
                            "audio_extraction_failed",
                            error.message ?: "Could not decode internal audio.",
                            null,
                        )
                    }
                }
            }.start()
        }
    }

    private fun readAudioSamples(
        path: String,
        positionMs: Long,
        durationMs: Long,
    ): ByteArray {
        val startUs = positionMs * 1000
        val endUs = startUs + durationMs * 1000
        val extractor = MediaExtractor()
        var decoder: MediaCodec? = null
        try {
            extractor.setDataSource(path)
            val trackIndex = (0 until extractor.trackCount).firstOrNull { index ->
                extractor.getTrackFormat(index).getString(MediaFormat.KEY_MIME)
                    ?.startsWith("audio/") == true
            } ?: throw IllegalArgumentException("This media file has no audio track.")

            extractor.selectTrack(trackIndex)
            val inputFormat = extractor.getTrackFormat(trackIndex)
            val mime = inputFormat.getString(MediaFormat.KEY_MIME)
                ?: throw IllegalArgumentException("The audio format is unknown.")
            decoder = MediaCodec.createDecoderByType(mime)
            decoder.configure(inputFormat, null, null, 0)
            decoder.start()
            extractor.seekTo(startUs, MediaExtractor.SEEK_TO_PREVIOUS_SYNC)

            val output = ByteArrayOutputStream()
            val info = MediaCodec.BufferInfo()
            var inputEnded = false
            var outputEnded = false
            var sampleRate = inputFormat.getInteger(MediaFormat.KEY_SAMPLE_RATE)
            var channelCount = inputFormat.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
            var pcmEncoding = AudioFormat.ENCODING_PCM_16BIT
            var nextOutputUs = startUs.toDouble()
            val outputIntervalUs = 1_000_000.0 / OUTPUT_SAMPLE_RATE
            val deadlineNanos = System.nanoTime() + DECODE_TIMEOUT_NANOS

            while (!outputEnded) {
                if (System.nanoTime() > deadlineNanos) {
                    throw IllegalStateException(
                        "Timed out while decoding this file's audio track.",
                    )
                }
                if (!inputEnded) {
                    val inputIndex = decoder.dequeueInputBuffer(CODEC_TIMEOUT_US)
                    if (inputIndex >= 0) {
                        val inputBuffer = decoder.getInputBuffer(inputIndex)
                            ?: throw IllegalStateException("Audio decoder input is unavailable.")
                        val size = extractor.readSampleData(inputBuffer, 0)
                        if (size < 0) {
                            decoder.queueInputBuffer(
                                inputIndex, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM,
                            )
                            inputEnded = true
                        } else {
                            decoder.queueInputBuffer(
                                inputIndex, 0, size, extractor.sampleTime, 0,
                            )
                            extractor.advance()
                        }
                    }
                }

                when (val outputIndex = decoder.dequeueOutputBuffer(info, CODEC_TIMEOUT_US)) {
                    MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                        val format = decoder.outputFormat
                        sampleRate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                        channelCount = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                        if (format.containsKey(MediaFormat.KEY_PCM_ENCODING)) {
                            pcmEncoding = format.getInteger(MediaFormat.KEY_PCM_ENCODING)
                        }
                    }
                    MediaCodec.INFO_TRY_AGAIN_LATER -> Unit
                    else -> if (outputIndex >= 0) {
                        if (info.size > 0) {
                            val buffer = decoder.getOutputBuffer(outputIndex)
                                ?: throw IllegalStateException("Audio decoder output is unavailable.")
                            buffer.position(info.offset)
                            buffer.limit(info.offset + info.size)
                            appendPcm(
                                output,
                                buffer.slice().order(ByteOrder.LITTLE_ENDIAN),
                                info.presentationTimeUs,
                                sampleRate,
                                channelCount,
                                pcmEncoding,
                                startUs,
                                endUs,
                                outputIntervalUs,
                                nextOutputUs,
                            ).also { nextOutputUs = it }
                        }
                        outputEnded =
                            info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0
                        decoder.releaseOutputBuffer(outputIndex, false)
                    }
                }
                if (nextOutputUs >= endUs || (inputEnded && outputEnded)) {
                    outputEnded = true
                }
            }
            if (output.size() == 0) {
                throw IllegalArgumentException("No audio was found at this video position.")
            }
            return output.toByteArray()
        } finally {
            try {
                decoder?.stop()
            } catch (_: Exception) {
                // The decoder may not have reached its started state.
            }
            decoder?.release()
            extractor.release()
        }
    }

    private fun appendPcm(
        output: ByteArrayOutputStream,
        pcm: ByteBuffer,
        presentationTimeUs: Long,
        sampleRate: Int,
        channelCount: Int,
        encoding: Int,
        startUs: Long,
        endUs: Long,
        outputIntervalUs: Double,
        firstOutputUs: Double,
    ): Double {
        val bytesPerSample = when (encoding) {
            AudioFormat.ENCODING_PCM_FLOAT -> 4
            AudioFormat.ENCODING_PCM_16BIT -> 2
            else -> throw IllegalArgumentException("The decoded PCM format is unsupported.")
        }
        val bytesPerFrame = bytesPerSample * channelCount
        val frameCount = pcm.remaining() / bytesPerFrame
        var nextOutputUs = firstOutputUs
        // Resampling rounds each frame boundary, so allow a few spare floats
        // beyond the exact 16 kHz estimate.
        val estimatedSamples =
            ceil(frameCount * OUTPUT_SAMPLE_RATE.toDouble() / sampleRate).toInt()
        val outputBytes = ByteBuffer.allocate((estimatedSamples + 8) * 4)
            .order(ByteOrder.LITTLE_ENDIAN)
        for (frame in 0 until frameCount) {
            val frameTimeUs = presentationTimeUs + frame * 1_000_000L / sampleRate
            val mono = readMonoSample(pcm, frame, channelCount, bytesPerSample, encoding)
            val nextFrameTimeUs = frameTimeUs + 1_000_000.0 / sampleRate
            if (frameTimeUs < startUs || frameTimeUs >= endUs) continue
            while (nextOutputUs < nextFrameTimeUs && nextOutputUs < endUs) {
                if (nextOutputUs >= frameTimeUs) {
                    outputBytes.putFloat(mono)
                }
                nextOutputUs += outputIntervalUs
            }
        }
        output.write(outputBytes.array(), 0, outputBytes.position())
        return nextOutputUs
    }

    private fun readMonoSample(
        pcm: ByteBuffer,
        frame: Int,
        channelCount: Int,
        bytesPerSample: Int,
        encoding: Int,
    ): Float {
        val frameOffset = frame * channelCount * bytesPerSample
        var total = 0f
        for (channel in 0 until channelCount) {
            val offset = frameOffset + channel * bytesPerSample
            total += if (encoding == AudioFormat.ENCODING_PCM_FLOAT) {
                pcm.getFloat(offset)
            } else {
                pcm.getShort(offset).toFloat() / 32768f
            }
        }
        return (total / channelCount).coerceIn(-1f, 1f)
    }

    companion object {
        private const val OUTPUT_SAMPLE_RATE = 16000
        private const val CODEC_TIMEOUT_US = 10000L
        private const val DECODE_TIMEOUT_NANOS = 20_000_000_000L
    }
}
