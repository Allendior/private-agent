# PrivateAgent Companion — status-only proof

This is a **separate** Flutter Android app, not a new mode inside the inherited PrivateAgent executor.

## What it does now

- Stores a paired device ID and shared status-proof key through `flutter_secure_storage` (Android Keystore-backed on Android), with Android backup disabled.
- Imports an explicit, short-lived, schema-locked one-time pairing payload into secure storage only after the person operating the device presses **Save pairing**.
- Verifies a signed, unexpired, exactly-one-action `device.status.get` envelope using canonical JSON, HMAC-SHA256, and unpadded base64url.
- Displays whether the local companion is paired, without rendering its shared key.

## What it explicitly does not do

- No network listener or outgoing network connection.
- No Android Accessibility service, foreground service, background work, notifications, LLM, Telegram, ADB, cron, screen reading, taps, typing, calls, SMS, or app launching.
- No transport or host-to-phone delivery is implemented yet.
- No real Android device test has occurred.

## Local verification — 2026-08-17

- `flutter test`: **13 passed**
- `flutter analyze`: **no issues**
- `flutter build apk --debug`: **passed**
- APK: `build/app/outputs/flutter-apk/app-debug.apk`
- SHA-256: `f2e0f1a8f46de32e8ba7134a2319ea945e68bc41ea5b8b946dc77bfc31b5ff6f`
- `aapt dump permissions`: only Android's generated non-exported dynamic-receiver permission; **no Android dangerous permissions and no `INTERNET` permission**.
- Pixel 4 XL baseline: installed successfully; prior companion version reached the unpaired local screen with no runtime-permission prompt. The updated pairing-import UI is installed but awaiting an awake, unobstructed screen verification.

Do not describe it as transport-connected or able to control a phone.

## Next slice

Implement an explicit local pairing import (e.g. a one-time QR payload) and a private, authenticated outbound transport. Before enabling any phone action, test tampered envelopes, expiry, cancellation, disconnection, app crash, and lock-screen behavior on a dedicated test phone.
