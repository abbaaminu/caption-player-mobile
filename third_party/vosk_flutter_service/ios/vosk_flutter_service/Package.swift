// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

// Swift Package Manager manifest for the iOS implementation of
// vosk_flutter_service.
//
// Vosk ships precompiled static libraries (libvosk.a) inside an XCFramework
// that has no Clang module of its own. It is therefore declared as a binary
// target and wrapped by the small `VoskAPI` Clang target below, which
// republishes vosk_api.h. Without that wrapper Swift cannot see
// vosk_model_new, vosk_recognizer_new, and the rest of the C API, and the
// static library is never linked into the app.
//
// The XCFramework is not committed; `dart run vosk_flutter_service install
// -t ios` downloads it into Frameworks/ before the package is resolved.
//
// `../FlutterFramework` is the Swift package that the Flutter tool generates
// next to this plugin's symlink (ios/Flutter/ephemeral/Packages/.packages/
// FlutterFramework). It vends the Flutter xcframework, which is what makes
// `import Flutter` resolve in Classes/VoskFlutterPlugin.swift.
let package = Package(
    name: "vosk_flutter_service",
    platforms: [
        .iOS(.v12)
    ],
    products: [
        .library(name: "vosk-flutter-service", targets: ["vosk_flutter_service"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        // Prebuilt Vosk static libraries: device (arm64/armv7/armv7s) and
        // simulator (arm64/x86_64).
        .binaryTarget(
            name: "Vosk",
            path: "Frameworks/vosk.xcframework"
        ),
        // Clang wrapper that exposes vosk_api.h to Swift and links the Vosk
        // static libraries together with the system libraries they need.
        // VoskAPI/include/module.modulemap is used as-is by SwiftPM and carries
        // the `link "c++"` / `link framework "Accelerate"` autolink directives.
        .target(
            name: "VoskAPI",
            dependencies: ["Vosk"],
            path: "VoskAPI",
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("include")
            ],
            linkerSettings: [
                .linkedLibrary("c++"),
                .linkedFramework("Accelerate")
            ]
        ),
        .target(
            name: "vosk_flutter_service",
            dependencies: [
                "VoskAPI",
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ],
            path: "Classes"
        )
    ]
)
