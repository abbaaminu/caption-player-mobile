# Live Caption Player

A Flutter media player for Android, iOS, and the web. Select a video or audio
file, play it, and see live captions produced by the device's speech
recognition. Captions listen to nearby playback through the microphone; the app
does not record or store audio.

## Supported platforms

- Android 7.0+ phones and tablets: playback and live captions through the
  device speech recognizer
- iPhone and iPad running iOS 14+: playback and live captions through iOS Speech
- Modern web browsers with the SpeechRecognition API (typically Chrome or Edge):
  playback and live captions when the app is served over HTTPS or localhost

Windows, macOS, and Linux desktop targets are not included.

## How live captions work

1. Opening a media file starts playback immediately.
2. `speech_to_text` wraps Android's `SpeechRecognizer`, iOS Speech, and the
   browser's `SpeechRecognition` API. The microphone picks up the audio played
   through the device speaker, so playback must stay audible.
3. While playback is running, captions listen in rolling sessions. Platform
   recognizers end a session after a stretch of silence or their maximum
   session length; the service renews the session automatically and keeps the
   last caption instead of stopping.
4. Partial results update the yellow caption overlay as words are recognized,
   and a short rolling window keeps the newest phrases visible.
5. Pausing playback pauses the microphone and preserves the last caption.
   Resuming starts a new session. Completing playback, opening another file, or
   locking for the paywall stops recognition.
6. The first caption session requests microphone and speech-recognition
   permission. Recognition may run on-device or through the platform provider's
   service, depending on the device and installed languages.

Android declares `RECORD_AUDIO` and a `<queries>` entry for
`android.speech.RecognitionService` so Android 11+ can find the recognizer. iOS
declares `NSMicrophoneUsageDescription` and
`NSSpeechRecognitionUsageDescription`. No audio is written to storage; only the
recognized text is shown.

Third-party components: `speech_to_text` is MIT-licensed. The recognition
service itself is provided by the operating system or browser and is subject to
that provider's terms.

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
flutter pub get
flutter run
```

Use `flutter devices` to choose an Android or iOS device, or run the web build
from a secure origin. Live captions work on Android, iOS, and browsers that
expose the SpeechRecognition API.

Android needs no extra setup. iOS permissions are declared in
`ios/Runner/Info.plist`; iOS builds require macOS and Xcode.

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

iOS builds require macOS and Xcode. The release workflow packages an unsigned
iOS IPA as `live-caption-player-ios-unsigned.ipa`. Sign it with an Apple
distribution certificate and provisioning profile before installing or
distributing it.

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

The tests cover the licensing client, live speech-service session recovery and
error mapping, the caption audio-guidance notice, storage, activation-link
parsing, media formats, web-origin checks, and the player screen's startup,
paywall, activation, and deep-link flows.

On Windows, set `PUB_CACHE` to a path without spaces and run the project from a
path that also has no spaces before running tests or Android builds. Flutter
3.44's native-asset build hooks do not quote paths correctly, so a location such
as `C:\Users\ABBA AMINU\...` fails with `'C:\Users\ABBA' is not recognized`. A
temporary drive mapping works without moving the project:

```powershell
subst X: "C:\path\to"
$env:PUB_CACHE = "C:\pubcache"
Set-Location X:\premiumcaption_player
flutter pub get
flutter analyze
flutter test
```

Map the project's parent folder and run from its subfolder, rather than mapping
the project folder directly. Flutter 3.44's analyzer cannot log a workspace whose
root is a drive root such as `X:\` and stops with an analysis-server
`FormatException`. Run `flutter pub get` from the mapped path so generated
tooling records that location. Remove the mapping with `subst X: /D` when you
are done; run `flutter pub get` from the original path again if you need its
generated files afterwards.

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

- Captions depend on the device's speech-recognition service and installed
  languages. Availability, accuracy, and supported languages vary by device,
  OS version, and browser.
- Captions listen through the microphone, so playback must be audible. Using
  headphones prevents the recognizer from hearing the audio.
- Background noise, music, overlapping speech, and low volume reduce accuracy.
- Recognizers end sessions after silence or a platform time limit. The service
  restarts automatically while playback continues, but a word at the boundary
  can be missed.
- Web captions need a browser with the SpeechRecognition API (typically Chrome
  or Edge) and an HTTPS or localhost origin. Safari and Firefox do not offer
  this API, and the app reports that captions are unavailable instead of
  silently failing.
- The web version loads the chosen video into browser memory, so very large
  files may require substantial memory.
