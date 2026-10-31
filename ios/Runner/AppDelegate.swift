import Flutter
import AVFoundation
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "MediaAudioSource")
    let channel = FlutterMethodChannel(
      name: "live_caption_player/media_audio",
      binaryMessenger: registrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      guard call.method == "readSamples" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard
        let arguments = call.arguments as? [String: Any],
        let path = arguments["path"] as? String,
        let positionMs = arguments["positionMs"] as? Int,
        let durationMs = arguments["durationMs"] as? Int,
        positionMs >= 0,
        durationMs > 0
      else {
        result(FlutterError(
          code: "invalid_audio_range",
          message: "Invalid audio range.",
          details: nil
        ))
        return
      }

      DispatchQueue.global(qos: .userInitiated).async {
        do {
          let data = try Self.readAudioSamples(
            path: path,
            positionMs: positionMs,
            durationMs: durationMs
          )
          DispatchQueue.main.async {
            result(FlutterStandardTypedData(bytes: data))
          }
        } catch {
          DispatchQueue.main.async {
            result(FlutterError(
              code: "audio_extraction_failed",
              message: error.localizedDescription,
              details: nil
            ))
          }
        }
      }
    }
  }

  private static func readAudioSamples(
    path: String,
    positionMs: Int,
    durationMs: Int
  ) throws -> Data {
    let asset = AVURLAsset(url: URL(fileURLWithPath: path))
    guard let track = asset.tracks(withMediaType: .audio).first else {
      throw NSError(
        domain: "MediaAudioSource",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "This media file has no audio track."]
      )
    }

    let start = CMTime(value: Int64(positionMs), timescale: 1000)
    let duration = CMTime(value: Int64(durationMs), timescale: 1000)
    let reader = try AVAssetReader(asset: asset)
    reader.timeRange = CMTimeRange(start: start, duration: duration)
    let output = AVAssetReaderTrackOutput(
      track: track,
      outputSettings: [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVSampleRateKey: 16000,
        AVNumberOfChannelsKey: 1,
        AVLinearPCMBitDepthKey: 32,
        AVLinearPCMIsFloatKey: true,
        AVLinearPCMIsBigEndianKey: false,
        AVLinearPCMIsNonInterleaved: false
      ]
    )
    output.alwaysCopiesSampleData = false
    guard reader.canAdd(output) else {
      throw NSError(
        domain: "MediaAudioSource",
        code: 2,
        userInfo: [NSLocalizedDescriptionKey: "The audio track could not be decoded."]
      )
    }
    reader.add(output)
    guard reader.startReading() else {
      throw reader.error ?? NSError(
        domain: "MediaAudioSource",
        code: 3,
        userInfo: [NSLocalizedDescriptionKey: "The audio track could not be decoded."]
      )
    }

    var data = Data()
    while let sampleBuffer = output.copyNextSampleBuffer() {
      guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
        continue
      }
      let length = CMBlockBufferGetDataLength(blockBuffer)
      guard length > 0 else {
        continue
      }
      let oldCount = data.count
      data.append(Data(count: length))
      let status = data.withUnsafeMutableBytes { bytes in
        CMBlockBufferCopyDataBytes(
          blockBuffer,
          atOffset: 0,
          dataLength: length,
          destination: bytes.baseAddress!.advanced(by: oldCount)
        )
      }
      guard status == kCMBlockBufferNoErr else {
        throw NSError(
          domain: "MediaAudioSource",
          code: 4,
          userInfo: [NSLocalizedDescriptionKey: "The audio samples could not be read."]
        )
      }
    }
    if reader.status == .failed {
      throw reader.error ?? NSError(
        domain: "MediaAudioSource",
        code: 5,
        userInfo: [NSLocalizedDescriptionKey: "The audio track could not be decoded."]
      )
    }
    guard !data.isEmpty else {
      throw NSError(
        domain: "MediaAudioSource",
        code: 6,
        userInfo: [NSLocalizedDescriptionKey: "No audio was found at this video position."]
      )
    }
    return data
  }
}
