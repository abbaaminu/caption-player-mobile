# Live Caption Player

A Flutter video player for Android, iOS, and the web. Select a video, play it,
and display live captions generated from microphone speech recognition.

## Supported platforms

- Android 7.0+ phones and tablets
- iPhone and iPad running iOS 14+
- Modern web browsers

Windows, macOS, and Linux desktop targets are not included.

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
flutter run -d chrome
```

Use `flutter devices` to list available Android or iOS devices. Build web and
Android release artifacts with:

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

iOS builds require macOS and Xcode.

## Live caption limitations

Captions use ambient sound picked up by the microphone while a video plays; the
app does not directly transcribe internal video audio. Keep playback audible
and use speakers near the microphone. Allow microphone access on your device
or in the browser's site settings. Web speech recognition needs HTTPS or
localhost and a supported browser such as current Chrome or Edge. The web
version loads the chosen video into browser memory, so very large files may
require substantial memory.
