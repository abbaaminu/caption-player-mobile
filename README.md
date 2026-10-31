# Live Caption Player

A Flutter media player for Android, iOS, and the web. Select a video or audio
file, play it, and see live captions transcribed locally by Whisper. Captions
are generated directly from the selected file's audio track. Audio is not
uploaded or captured from a microphone.

## Supported platforms

- Android 7.0+ 64-bit phones and tablets (arm64-v8a, x86_64): playback and
  on-device Whisper captions. The Whisper native library has no 32-bit ARM
  build, so the Android app is not offered to 32-bit-only devices.
- iPhone and iPad running iOS 14+: playback and on-device Whisper captions
- Modern browsers with WebAssembly support: playback and
  on-device Whisper captions over HTTPS or localhost

Windows, macOS, and Linux desktop targets are not included.

## How live captions work

1. Opening a media file starts playback immediately.
2. The app extracts short PCM windows from the selected media's audio track
   and transcribes them using a multilingual Whisper model on-device. No
   microphone or room playback is involved.
3. Each audio window ends at the current playback position, so captions
   describe audio that has just played instead of running ahead of the video.
   Windows are refreshed every two seconds during playback.
4. New rolling-window results update the caption bar. It follows the look of
   the system caption overlay on Android phones (and Infinix/XOS devices): a
   near-black rounded box with white, centred text. Two lines are shown, and a
   tap or double tap expands the box to show the last phrases, as the system
   box does. The bar clears after about six seconds of silence. Seeking clears
   the previous text and resumes transcription at the new timeline position.
5. Pausing playback pauses transcription and preserves the last caption.
   Resuming starts a new session. Completing playback, opening another file, or
   locking for the paywall stops recognition.
6. The first caption session downloads the 31 MiB quantized Whisper model.
   Android and iOS cache the model for later sessions; web relies on normal
   browser HTTP caching. Once loaded, audio is transcribed locally.

The app does not request microphone permissions. Extracted PCM audio is held
only long enough for local transcription and is never uploaded.

Third-party component: `flutter_whisper_ggml` is MIT-licensed.

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

Use Flutter 3.44 or newer (Dart 3.12 or newer). Web captions require
cross-origin isolation. The included `web_dev_config.yaml` configures the
Flutter development server with the required COOP/COEP headers; run
`flutter run -d web-server --web-port 8080` from the project root. A generic
static server such as VS Code Live Server does not apply these headers, so the
app reports an actionable error instead of remaining stuck on “Preparing.”
Production hosting must also send `Cross-Origin-Opener-Policy: same-origin` and
`Cross-Origin-Embedder-Policy: require-corp`; `web/_headers` provides these for
hosts that support that file. To preview a release web build with those headers
locally, run `flutter build web --release` and then `.\tool\serve_web.ps1`,
which serves `build\web` on <http://localhost:8080/> without needing Node,
Python, or administrator rights.

The first caption session needs
an internet connection to download the Whisper model. Android and iOS can
transcribe offline after the model is cached; web model reuse depends on browser
HTTP caching. Use `flutter devices` to choose an Android or iOS device, or run
the web build from a secure origin.

Android needs no extra setup: the manifest requests internet access only, and
files are opened through the system document picker rather than broad storage
permissions. iOS declares no microphone or speech-recognition permissions
either, because captions read the selected file's audio track. iOS builds
require macOS and Xcode.

Build web and Android release artifacts with:

```sh
flutter build web
flutter build apk --release
```

The WebAssembly dry run passes for this app, so `flutter build web` needs no
extra flags; pass `--no-wasm-dry-run` only to skip that check for faster builds.
Phone builds keep trial and license state in secure storage. A web build stores
the same state in origin-scoped browser local storage instead of invoking the
secure-storage plugin, so that storage is not encrypted and users can clear it
in browser settings.

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

## When captions do not appear

The caption bar reports what the pipeline is doing, so a silent video no longer
looks identical to a broken setup:

- `Preparing live captions…` and `Downloading caption model · N%` mean the
  on-device model is still loading. The first session needs a connection for the
  31 MiB download.
- `Listening for speech…` means media audio is being read but no words have been
  recognised yet. Music, silence, or a very quiet track can stay in this state.
- A red banner above the caption bar carries the failure reason and a retry
  action. The reason is included so a failed model download can be told apart
  from an unsupported device or a media file without an audio track.
- Web builds must be served with the COOP and COEP headers from
  `web_dev_config.yaml` (development, applied by `flutter run`) or `web/_headers`
  (hosting); `tool/serve_web.ps1` adds them to a local release build. Without
  them the WebAssembly worker cannot start and the app says so instead of
  staying on “Preparing”.
- `flutter run` prints one line per transcription window:
  `Caption window <start>ms+<length>ms (<samples> samples) -> "<text>"`.
  `<silence>` means the decoder produced audio but Whisper heard no speech, and
  a missing line means no audio was read for that window.

Silent stretches and the end of an audio track are treated as silence rather
than as decoder failures, so captioning keeps running through them.

## Caption limitations

- The first caption use downloads the multilingual Whisper model (about 31 MiB).
  A connection is needed for the download; Android and iOS cache it locally.
  Web reuse depends on browser HTTP caching. Audio transcription runs on-device
  after the model is loaded, with accuracy and speed depending on device
  performance.
- Captions use the media file's audio track directly and work with muted
  playback or headphones.
- Music, overlapping speech, and low-volume source audio reduce accuracy.
- Web captions need HTTPS or localhost and the
  Whisper WebAssembly worker. Deploy the response headers in `web/_headers`
  (`Cross-Origin-Opener-Policy: same-origin` and
  `Cross-Origin-Embedder-Policy: require-corp`) for the worker runtime to work.
- The web version plays the browser file picker’s local object URL directly
  instead of copying the entire file into a second in-memory buffer. The browser
  and media decoder still use memory for playback, and Web Audio decodes the
  source for caption extraction, so very large files may require substantial
  memory. Media remains on the device; the app does not upload it.
