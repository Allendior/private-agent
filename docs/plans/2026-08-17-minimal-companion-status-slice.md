# Minimal Android Companion Status Slice Implementation Plan

> **For Hermes:** Use strict TDD for every behavior change.

**Goal:** Build a separate Android companion APK with no dangerous permissions, a local one-time pairing store, and a status-only signed-envelope proof screen.

**Architecture:** Do not attempt to flavor the inherited PrivateAgent app: every existing Flutter plugin can contribute Android manifest entries and defeats a credible least-privilege audit. Create an isolated Flutter app under `companion/` with a deliberately tiny dependency graph. Its only privileged datum is a device-specific shared key held by Android Keystore via a secure storage adapter. No network, background execution, Accessibility, LLM, Telegram, cron, or Android automation is implemented in this slice.

**Tech Stack:** Flutter/Dart, `crypto`, `flutter_secure_storage`, Material 3, Flutter unit/widget tests.

---

### Task 1: Create a testable pairing domain

**Files:**
- Create: `companion/lib/pairing/pairing_controller.dart`
- Create: `companion/lib/pairing/secure_key_store.dart`
- Test: `companion/test/pairing_controller_test.dart`

**TDD acceptance tests:**
1. Empty store reports unpaired.
2. A valid local pairing record persists device ID and key through an injected store.
3. Reject malformed records, invalid device IDs, and keys shorter than 32 characters.
4. Never expose the key in a display/status model.

### Task 2: Add status-envelope verification

**Files:**
- Create: `companion/lib/protocol/status_envelope_verifier.dart`
- Test: `companion/test/status_envelope_verifier_test.dart`

**TDD acceptance tests:**
1. Signed, unexpired `device.status.get` envelope is accepted.
2. Tampered signature and expired envelope reject.
3. Any action other than exactly `device.status.get` rejects.
4. Canonical JSON, UTF-8, HMAC-SHA256, and unpadded base64url exactly match the host protocol.

### Task 3: Add a foreground local-only pairing/proof UI

**Files:**
- Create: `companion/lib/main.dart`
- Create: `companion/lib/ui/companion_home.dart`
- Test: `companion/test/companion_home_test.dart`

**TDD acceptance tests:**
1. Unpaired screen clearly says it has no active connection.
2. The screen never prompts for Accessibility, notifications, contacts, microphone, network, or background operation.
3. A paired status is visible without rendering the secret.

### Task 4: Build and audit the separate APK

**Files:**
- Create: `companion/pubspec.yaml`
- Create: `companion/android/app/src/main/AndroidManifest.xml`
- Create: `companion/README.md`

**Verification:**
1. `flutter test` passes from `companion/`.
2. `flutter build apk --debug` succeeds.
3. `aapt dump permissions build/app/outputs/flutter-apk/app-debug.apk` shows no dangerous permissions.
4. Record APK SHA-256, size, test/build output, and known boundary in README.
5. Do not call it device-tested until a dedicated phone is attached and manually paired.
