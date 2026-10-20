#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint vosk_flutter.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'vosk_flutter_service'

  s.version          = '0.1.2'
  s.summary          = 'Flutter plugin for offline speech recognition using the Vosk speech recognition toolkit.'
  s.description      = <<-DESC
Flutter plugin for offline speech recognition using the Vosk speech recognition toolkit.
                       DESC
  s.homepage         = 'https://www.bechattaoui.dev'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Dhia Bechattaoui' => 'dhia@bechattaoui.dev' }
  s.source           = { :path => '.' }

  # vosk_api.h is a public header on purpose: CocoaPods adds public headers to
  # the pod's umbrella header, and that umbrella is how the Swift sources of a
  # framework pod resolve the Vosk C API (vosk_model_new, vosk_recognizer_new,
  # ...). A bridging header cannot be used here because Flutter builds pods as
  # frameworks (`use_frameworks!`), and Xcode rejects bridging headers in
  # framework targets.
  s.source_files        = 'vosk_flutter_service/Classes/**/*.{swift,h}',
                          'vosk_flutter_service/VoskAPI/include/vosk_api.h'
  s.public_header_files = 'vosk_flutter_service/VoskAPI/include/vosk_api.h'

  s.dependency 'Flutter'
  s.platform = :ios, '12.0'

  # Prebuilt Vosk static libraries (libvosk.a) for device and simulator.
  # `dart run vosk_flutter_service install -t ios` populates
  # ios/vosk_flutter_service/Frameworks before `pod install` runs.
  s.vendored_frameworks = 'vosk_flutter_service/Frameworks/vosk.xcframework'

  # libvosk.a is C++ and uses Accelerate for its math kernels.
  s.libraries = 'c++'
  s.frameworks = 'Accelerate'

  # libvosk.a is a static library: vendoring this pod as a dynamic framework
  # would not re-export its symbols to the Runner target, which fails at link
  # time with "Undefined symbols: _vosk_model_new".
  s.static_framework = true

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'CLANG_ENABLE_MODULES' => 'YES',
    # Directory containing vosk_api.h, used by `#import "vosk_api.h"` and by
    # any Objective-C/Objective-C++ compiled as part of this pod.
    'HEADER_SEARCH_PATHS' => '"${PODS_TARGET_SRCROOT}/vosk_flutter_service/VoskAPI/include"',
    # Flutter.framework does not contain an i386 slice.
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386'
  }
  s.swift_version = '5.0'

  s.preserve_paths = 'vosk_flutter_service/Frameworks/vosk.xcframework',
                     'vosk_flutter_service/VoskAPI/include/vosk_api.h'
end
