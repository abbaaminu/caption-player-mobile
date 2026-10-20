# vosk_flutter_service (local fork)

This directory is a minimal local copy of
[`vosk_flutter_service` 0.1.2](https://pub.dev/packages/vosk_flutter_service)
(Apache-2.0; see `LICENSE`). The Dart API and native Android/iOS code are
unchanged.

Changes from the published package:

- The `flutter.plugin.platforms` table declares only Android and iOS. This app's
  caption pipeline uses FFmpeg and Vosk on mobile only; the web build plays
  media but intentionally has no transcription backend.
- `android/build.gradle` compiles against Android API 36. Upstream uses API 33,
  but its `androidx.appcompat:1.7.0` dependency requires API 34 or newer and
  fails Gradle's AAR metadata check before the app can build.
- The `macos`, `linux`, `windows`, and `web` plugin entries and directories were
  removed.
- Upstream 0.1.2 declares `fileName: lib/src/vosk_flutter_web.dart` for its web
  implementation. Flutter prepends `package:vosk_flutter_service/` to that path,
  producing the nonexistent `lib/lib/src/vosk_flutter_web.dart`, which fails
  every Flutter web build even when Vosk is never imported. Removing the web
  entry avoids that upstream bug.

The iOS XCFramework is **not** committed. Populate it after `flutter pub get`:

```sh
dart run vosk_flutter_service install -t ios
```

The installer writes to this package's `ios/vosk_flutter_service/Frameworks/`
directory. That directory is git-ignored and must be regenerated in a clean
checkout, including CI, before building for iOS.

The framework lives inside the Swift package directory (rather than
`ios/Frameworks/`) because `Package.swift` declares it as a SwiftPM binary
target, and SwiftPM rejects binary target paths outside the package root. Both
`ios/vosk_flutter_service.podspec` (CocoaPods) and `Package.swift` (SwiftPM)
point at that location.

The plugin needs the Vosk C API in Swift scope. On CocoaPods this works because
`vosk_api.h` is a public header of the pod, so it is part of the pod's umbrella
header. On SwiftPM it works through the `VoskAPI` Clang wrapper target, which is
why `VoskFlutterPlugin.swift` starts with:

```swift
#if canImport(VoskAPI)
import VoskAPI
#endif
```

`VoskAPI/include/module.modulemap` is a custom module map: SwiftPM uses it
verbatim and it carries `link "c++"` / `link framework "Accelerate"`, so every
object file that imports the module records the autolink options that the Runner
target needs to link `libvosk.a`.

`Package.swift` also declares a dependency on `../FlutterFramework`, the package
the Flutter tool generates inside `ios/Flutter/ephemeral/Packages/.packages/`.
That is the canonical way for a plugin written in Swift to `import Flutter`, and
it is the same layout Flutter's own `plugin_swift_package_manager` template
generates.

To update the fork, copy `lib/`, `bin/`, `android/`, and the non-framework files
from `ios/` in the new published package, reapply the platform-table and
`compileSdk` changes, and verify both `flutter build apk` and `flutter build
web`.
