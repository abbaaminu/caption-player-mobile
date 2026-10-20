# Live Caption Player

A Flutter media player for Android, iOS, and the web. Select a video or audio
file, play it, and display captions generated from that file's own audio track.
On Android and iOS the audio is decoded locally and transcribed on-device; the
app never opens the microphone.

## Supported platforms

- Android 7.0+ phones and tablets: playback and on-device captions
- iPhone and iPad running iOS 14+: playback and on-device captions
- Modern web browsers: playback only. The current FFmpeg/Vosk native plugins
  have no working web implementation, so file-audio captions are unavailable in
  the web build and the app shows an explicit message instead of opening the
  microphone.

Windows, macOS, and Linux desktop targets are not included.

## How file-audio captions work

1. Opening a media file starts playback immediately.
2. `ffmpeg_kit_flutter_new_audio` extracts the first audio stream from the
   selected file into a temporary WAV file using:
   `-vn -acodec pcm_s16le -ar 16000 -ac 1`.
3. The first time captions run, the compact English Vosk model
   (`vosk-model-small-en-us-0.15`, about 40 MB) is downloaded and cached in the
   app documents directory. Later sessions are fully offline.
4. `vosk_flutter_service` creates an on-device recognizer at 16 kHz. The app
   reads only the PCM that playback has reached, feeds it to Vosk, and updates
   the yellow caption overlay with partial and finalized text.
5. Pausing stops audio feed without destroying recognizer state. Seeking resets
   the recognizer and clears stale caption text. Stopping or completing playback
   flushes the final buffered audio.

No `RECORD_AUDIO` permission and no `NSMicrophoneUsageDescription` are declared.
The app does not request microphone or speech-recognition access. The merged
Android manifest contains `INTERNET` (used for the one-time model download and
license verification) plus `ACCESS_NETWORK_STATE` and `WAKE_LOCK`, which the
media playback and FFmpeg libraries contribute.

The model is English-only by default. To use another Vosk model, change
`AppConfig.speechModelUrl` in `lib/config/app_config.dart`; the ZIP must extract
to a top-level directory named exactly like the ZIP file (without `.zip`).

Third-party components: the audio-only FFmpeg Kit fork is LGPL-3.0 and the Vosk
runtime/model are Apache-2.0. Review their licenses before distributing the app.
`vosk_flutter_service` is pinned to the minimal local fork in
`third_party/vosk_flutter_service`; it removes upstream 0.1.2's invalid web
plugin declaration (which breaks every Flutter web build) without changing the
Dart API or native Android/iOS code. See that directory's README for details.

## Trial and subscription settings

- The free trial allows **30 minutes of video playback in total**. Time is
  accumulated while a video is playing. Phone trial data uses secure storage;
  browser trial data uses origin-scoped browser storage.
- Monthly plan: **$1.00/month**.
- Lifetime pass: **$19.00 one-time**.
- Both purchase buttons open the pricing page:
  [caption.stackbuildco.com/pricing](https://caption.stackbuildco.com/#/pricing).
- After checkout, enter the license key from the payment confirmation page.
  Android and iOS also register the `captionplayer://activate?key=...` link.

Trial time is stored locally on each device/browser; it is not a server-enforced
account quota. Clearing browser storage, changing browser/domain, or reinstalling
can reset a local trial. The web app should be deployed at
`https://caption.stackbuildco.com` so the origin matches the licensing server's
CORS policy and its browser storage remains available for that site.
The browser storage backend changed from secure storage to browser preferences;
existing web trial and license data is not migrated and may need to be entered
again after upgrading.

## Licensing backend

License keys are verified by POSTing `{"license_key":"..."}` to
`https://api.caption.stackbuildco.com/verify`. The app does not contain
Supabase or payment-provider secrets. Keep those credentials on the backend.

For a deployed Flutter web client, the backend must allow the app's HTTPS origin
for `/verify`. The provided `caption_server_backend/server.py` now allows the
production caption website and localhost development origins for this route.
Redeploy the backend after making backend changes.

The backend issues licenses from Paystack/Paddle webhooks and verifies active
licenses against Supabase. Configure the existing Supabase and webhook
environment variables on the server; never place them in this Flutter app.

## Run and build

Install Flutter, then run:

```sh
flutter config --enable-native-assets
flutter pub get
flutter run
```

Use `flutter devices` to choose an Android or iOS device. The web target can
play files but cannot generate captions with this native pipeline, so use a
mobile device to test captioning.

For iOS builds, install the Vosk native framework into the local plugin
directory once after fetching packages:

```sh
dart run vosk_flutter_service install -t ios
```

Run that command again in a fresh checkout or if
`third_party/vosk_flutter_service/ios/vosk_flutter_service/Frameworks` is
deleted; the framework is git-ignored and not committed to this repository.

The iOS build uses Flutter's Swift Package Manager integration
(`ios/Runner.xcodeproj` references `FlutterGeneratedPluginSwiftPackage`), so the
plugin is compiled from `third_party/vosk_flutter_service/ios/vosk_flutter_service/Package.swift`,
which pulls the Vosk framework in as a SwiftPM binary target. Install the
framework before the first iOS build, and run `flutter clean` once if you added
it after a failed build: Xcode caches the failed package resolution. The
podspec in the same directory is only used if SwiftPM is turned off for the
project.

Android needs no extra setup.

Build web and Android release artifacts with:

```sh
flutter build web --no-wasm-dry-run
flutter build apk --release
```

Use `--no-wasm-dry-run` for web builds. The secure-storage web plugin uses
JavaScript interop that Flutter's WebAssembly dry run does not support. In a
web build, this app uses browser local storage for trial and license state
instead of invoking the secure-storage plugin. Browser storage is scoped to
the deployed origin and is not encrypted; users can clear it in browser
settings.

iOS builds require macOS and Xcode. Run the Vosk iOS install command before
building. The release workflow packages an unsigned iOS IPA as
`live-caption-player-ios-unsigned.ipa`. Sign it with an Apple distribution
certificate and provisioning profile before installing or distributing it.

The Android application ID and iOS bundle identifier are
`com.stackbuildco.livecaptionplayer`. Keep these identifiers stable after the
first store release, because stores use them to match updates to an existing
app.

### Android release signing

For a distributable APK, create an upload keystore outside version control and
add `android/key.properties`:

```properties
storePassword=your-store-password
keyPassword=your-key-password
keyAlias=upload
storeFile=upload-keystore.jks
```

Place the keystore at `android/app/upload-keystore.jks`. Both the keystore and
`key.properties` are git-ignored. Without them, release builds fall back to the
debug signing key and must not be published to a store.

The release workflow reads the same values from the
`ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, and
`ANDROID_KEY_PASSWORD` repository secrets. All four are required; the release
job fails before publishing if any is missing, so a debug-signed APK cannot be
released by accident.

## Tests

```sh
flutter analyze
flutter test
```

The tests cover the licensing client, on-device speech-service error mapping,
the playback-synchronized caption pipeline, Vosk result parsing, WAV/PCM
parsing, storage, activation-link parsing, media formats, web-origin checks,
and the player screen's startup, paywall, activation, and deep-link flows.

On Windows, also set `PUB_CACHE` to a path without spaces and keep the project
path space-free before running tests or Android builds. Flutter 3.44's
native-asset build hooks do not quote paths correctly, so a location such as
`C:\Users\ABBA AMINU\...` fails with `'C:\Users\ABBA' is not recognized`.

## Release workflow

Pushing a tag that starts with `v` (for example `v1.0.0`) runs
`.github/workflows/release.yml`. The workflow pins Flutter 3.44.6, verifies
formatting, analysis, and tests, then builds and publishes:

- `live-caption-player-android.apk` (signed with the release keystore)
- `live-caption-player-web.zip`
- `live-caption-player-ios-unsigned.ipa`

The assets are attached to a release in the
`abbaaminu/caption-player-mobile-release` repository. The workflow requires the
four Android signing secrets above plus `RELEASE_TOKEN`, a token with
`contents: write` access to that release repository. The default
`GITHUB_TOKEN` cannot publish releases to a different repository.

Set `version:` in `pubspec.yaml` before tagging so the Android version name and
build number, and the iOS short version and bundle version, match the release
tag.

## Caption limitations

- Captions are generated on-device from the first audio track only. Embedded
  subtitle tracks are not read, and a file without an audio stream shows an
  error instead of captions.
- The bundled default model is compact English
  (`vosk-model-small-en-us-0.15`). Other languages require a different Vosk
  model URL and enough storage for it.
- The first caption session downloads about 40 MB of model data. It needs a
  network connection; later sessions run offline. If playback starts before the
  model is ready, captioning begins at the playback position reached when the
  model and PCM extraction finish.
- Audio extraction writes a temporary 16 kHz mono WAV file, roughly 115 MB per
  hour of media, and removes it when the session ends. Large files can take a
  few seconds to prepare.
- Partial results may change as Vosk refines them. Seeking clears the current
  caption and restarts recognition at the new position, so a word crossing the
  seek point can be lost.
- The web build plays selected files but does not generate captions; with a
  native-only FFmpeg/Vosk pipeline the app reports that captions are unavailable
  on the web instead of requesting microphone access.
- The web version loads the chosen video into browser memory, so very large
  files may require substantial memory.
