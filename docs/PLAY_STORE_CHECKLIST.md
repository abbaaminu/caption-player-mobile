# Play Store checklist — system-wide Live Caption

Do these in Play Console before the first release that contains Live Caption.

## 1. Foreground service declaration
App content → **Foreground service permissions** → declare
`FOREGROUND_SERVICE_MEDIA_PROJECTION`.
- Use case: the user starts live captions; the app captures audio playing on the
  device so it can display on-screen captions for people who are deaf, hard of
  hearing, or watching with sound off.
- Provide a short screen recording: Start → Android consent dialog → caption box
  over another app → Stop from the notification.

## 2. Permissions declaration
- `SYSTEM_ALERT_WINDOW`: required to show the caption box above other apps.
  Core feature; no alternative.
- `RECORD_AUDIO`: required by Android for `AudioPlaybackCapture`. State that the
  microphone is not recorded, and that audio is processed on-device only.

## 3. Data safety form
- Audio: **processed ephemerally on-device**, not collected, not shared.
- License key: collected (app functionality), sent to `api.caption.stackbuildco.com`
  over HTTPS to verify activation, not shared with third parties.

## 4. Prominent disclosure
The app shows an in-app dialog ("Caption audio on this phone") before it asks
for any permission. Keep its wording in sync with your privacy policy, and add
this to the privacy policy: system audio is captioned on-device, never uploaded
or stored; the microphone is not recorded.

## 5. Privacy policy
Update the policy URL to mention on-device audio processing and the license-key
check. Both the policy and the app listing must name the permissions above.

## 6. Pre-launch testing
Test on a real phone running Android 10, 13, 14, and 15 (the Infinix Smart 10
Plus runs Android 15 / XOS 15.1). Emulators have no usable playback capture for
many apps.
