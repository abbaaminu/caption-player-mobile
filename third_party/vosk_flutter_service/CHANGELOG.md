# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed
- **iOS build: Vosk C API no longer visible to Swift.** `vosk_api.h` moved into
  `ios/vosk_flutter_service/VoskAPI/include/` and the `VoskAPI` Clang wrapper
  target was restored in `Package.swift`. The old manifest declared a single
  Swift target with no access to the header and no dependency on
  `vosk.xcframework`, so SwiftPM builds failed with `Cannot find
  'vosk_model_new' in scope` and (once the header was reachable) would have
  failed to link `libvosk.a`.
- **`ios/vosk_flutter_service.podspec` pointed at the wrong XCFramework path**
  (`Frameworks/vosk.xcframework`, i.e. `ios/Frameworks/…`, which does not
  exist). It now uses `vosk_flutter_service/Frameworks/vosk.xcframework`,
  matching the installer output, and sets `static_framework` so `libvosk.a` is
  not wrapped in a dynamic framework that hides `vosk_*` symbols from the app.
- **`Package.swift` could not resolve `import Flutter`.** The manifest now
  declares the Flutter-generated `FlutterFramework` package
  (`.package(name: "FlutterFramework", path: "../FlutterFramework")`) and adds it
  as a target dependency, matching Flutter's `plugin_swift_package_manager`
  template and the plugins Flutter itself ships.
- **Missing `-lc++` / `-framework Accelerate` under SwiftPM.**
  `ios/vosk_flutter_service/VoskAPI/include/module.modulemap` is a custom module
  map (SwiftPM uses it verbatim instead of generating one) with `link "c++"` and
  `link framework "Accelerate"` autolink directives, so the app links the C++
  runtime and Accelerate that `libvosk.a` requires.
- `dart run vosk_flutter_service install -t ios` now downloads the XCFramework
  into `ios/vosk_flutter_service/Frameworks/`, inside the Swift package, because
  SwiftPM binary targets cannot reference paths outside the package root. Delete
  an older `ios/Frameworks/` directory after upgrading; the installer will fetch
  the framework again.

## [0.1.2] - 2026-06-25

### Added
- `.agents` folder containing AI agent configuration (rules and workflows).
- `plan.md` file at the root to track project tasks and milestones.

### Fixed
- **iOS Swift Package Manager (SPM) Compatibility**: Restructured the iOS package to provide native SPM support by adding a dedicated `VoskAPI` C-wrapper target for `vosk.xcframework` headers. This resolves the `mixed language source files` and `Cannot find 'vosk_model_new' in scope` compilation errors on modern Flutter versions.


## [0.1.1] - 2026-04-07

### Fixed
- **iOS & macOS Structure**: Fixed incorrect path mappings in `.podspec` files that caused "Module not found" errors. Native classes are now correctly located within the `vosk_flutter_service/Classes` subfolder as per the repository structure.
- Synchronized version across `pubspec.yaml` and platform `podspec` files.

## [0.1.0] - 2026-03-15

### Added
- **Web & WASM support**: Implemented a "stub-first" conditional import strategy
  across all native-dependent libraries (`dart:ffi`, `dart:io`, `archive`,
  `path_provider`, `permission_handler`), making the package analyzable and
  functional on Web and WASM targets.
- **Swift Package Manager (SPM) support**: Added `Package.swift` manifests for
  both iOS (`ios/vosk_flutter_service/Package.swift`) and macOS
  (`macos/vosk_flutter_service/Package.swift`).
- Stub files for `dart:ffi`, `dart:io`, `archive`, `path_provider`, and
  `permission_handler` under `lib/src/stubs/` to enable cross-platform analysis.
- `lib/src/ffi_provider.dart` as a single re-export point for FFI libraries,
  switching between real and stub implementations based on `dart.library.io`.

### Changed
- Replaced `dart:isolate`/`Isolate.run` with Flutter's `compute()` in
  `ModelLoader` for better cross-platform compatibility (Web included).
- Updated `PermissionService` to guard permission requests behind
  `Platform.isAndroid || Platform.isIOS`, preventing crashes on other platforms.
- All conditional imports now use the **stub-first** pattern
  (`import 'stub.dart' if (dart.library.io) 'real.dart'`) for correct WASM
  resolution.
- Updated iOS Podspec version and metadata to match the package.

### Fixed
- Achieved a perfect **160/160 pana score**: all six platforms fully supported
  (Android, iOS, macOS, Linux, Windows, Web), WASM-ready, SPM-ready, static
  analysis clean, and all dependency constraints satisfied.

## [0.0.7] - 2026-03-15

### Changed
- Updated Vosk Android dependency to 0.3.75 to support 16KB page size.

## [0.0.6] - 2026-01-22

### Changed
- Configured CLI download URLs to point to the official repository for native binaries.
- Improved CLI installation flow and error reporting.

## [0.0.5] - 2026-01-22

### Fixed
- Fixed CLI executable name to match package name (`vosk_flutter_service`).
- Updated internal package name constants in CLI tool.

## [0.0.4] - 2026-01-22

### Changed
- Excluded large iOS and MacOS native binaries from the pub.dev package to comply with the 100MB size limit.
- Updated the CLI tool to support downloading and installing native binaries for iOS and MacOS.
- Updated `README.md` with instructions for native binaries installation.

## [0.0.3] - 2026-01-22

> [!IMPORTANT]
> **Technical Note**: Previous versions had an incomplete iOS implementation due to missing native frameworks in the `ios/Frameworks` directory and a casing discrepancy in the method bridge. We apologize for these technical omissions which have now been fully resolved.

### Fixed
- Resolved iOS microphone input issue by adding explicit `AVAudioSession` configuration.
- Fixed critical method name mismatch between Dart and Swift.
- Added robust debug logging for iOS (NSLog) and Dart sides to track audio data flow.
- Optimized `SpeechService` listener logic in Dart for better performance and reliability.
- Fixed various linting issues across the codebase.

## [0.0.2] - 2026-01-14

### Changed
- Updated repository URL to `https://github.com/dhia-bechattaoui/vosk-flutter-service`.

## [0.0.1] - 2026-01-05

### Changed
- **BREAKING**: Renamed package to `vosk_flutter_service`.
- Migrated Android build to Kotlin DSL.
- Updated `record` dependency to v6 in example app.
- Enforced strict type safety (0 analysis issues).

### Fixed
- Resolved all analysis issues.
- Updated AGP/Gradle versions.

[0.1.0]: https://github.com/dhia-bechattaoui/vosk-flutter-service/compare/v0.0.7...v0.1.0
[0.0.7]: https://github.com/dhia-bechattaoui/vosk-flutter-service/compare/v0.0.6...v0.0.7
[0.0.6]: https://github.com/dhia-bechattaoui/vosk-flutter-service/compare/v0.0.5...v0.0.6
[0.0.5]: https://github.com/dhia-bechattaoui/vosk-flutter-service/compare/v0.0.4...v0.0.5
[0.0.4]: https://github.com/dhia-bechattaoui/vosk-flutter-service/compare/v0.0.3...v0.0.4
[0.0.3]: https://github.com/dhia-bechattaoui/vosk-flutter-service/compare/v0.0.2...v0.0.3
[0.0.2]: https://github.com/dhia-bechattaoui/vosk-flutter-service/compare/v0.0.1...v0.0.2
[0.0.1]: https://github.com/dhia-bechattaoui/vosk-flutter-service/releases/tag/v0.0.1