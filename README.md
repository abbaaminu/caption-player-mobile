# Premium Live Caption Player

A Flutter video player for Android, iOS, and the web. Select a video, play it,
and display live captions generated from microphone speech recognition.

## Supported platforms

- Android 7.0+ phones and tablets
- iPhone and iPad running iOS 14+
- Modern web browsers

Windows, macOS, and Linux desktop targets are not included.

## Trial and subscription settings

- The free trial allows **30 minutes of video playback in total**. Time is
  accumulated while a video is playing and saved with secure storage.
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
CORS policy and the browser's secure-storage domain.

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

iOS builds require macOS and Xcode.

## Live caption limitations

Captions use microphone audio while a video plays; the app does not directly
transcribe the phone's internal video audio. Allow microphone access. Browser
speech-recognition support varies; use a current Chrome or Edge browser over
HTTPS (or localhost). The web version loads the chosen video into browser
memory, so very large files may require substantial memory.
