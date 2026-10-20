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

The installer writes to this package's `ios/Frameworks/` directory. That
directory is git-ignored and must be regenerated in a clean checkout, including
CI, before building for iOS.

To update the fork, copy `lib/`, `bin/`, `android/`, and the non-framework files
from `ios/` in the new published package, reapply the platform-table and
`compileSdk` changes, and verify both `flutter build apk` and `flutter build
web`.
