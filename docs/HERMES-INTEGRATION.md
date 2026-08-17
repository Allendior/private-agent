# Hermes Integration Assessment

**Audited:** 2026-08-16  
**Fork:** https://github.com/Allendior/private-agent  
**Upstream:** https://github.com/orailnoor/private-agent

## What PrivateAgent is

PrivateAgent is a Flutter Android app. Its native `AgentAccessibilityService` reads Android accessibility trees and can tap, type, swipe, scroll, and invoke Home/Back. Its Dart task executor sends screen descriptions and task prompts to a user-configured OpenAI-compatible LLM endpoint, then executes the returned next action.

## What it is not

The current codebase is **not a Hermes skill or Hermes tool**:

- It has no authenticated HTTP, MCP, WebSocket, or local IPC interface that Hermes can call.
- Its Telegram mode is an app-owned polling client, not Hermes Gateway integration.
- It does not provide a typed confirmation protocol for high-impact actions.

A local Hermes skill named `private-agent-android` has been installed as an operational/audit playbook. It does not falsely claim that Hermes can command the app directly.

## Security findings

The Android manifest requests broad permissions including `INTERNET`, microphone, contacts, phone calls, SMS sending, phone state, write settings, notifications, package visibility, and foreground service. The Accessibility service can inspect foreground UI text and execute gestures.

Do not use this as an unattended general-purpose phone agent. In particular:

1. Keep keys in local device settings only—never repository files, logs, issues, or commits.
2. Do not use the Telegram integration with a shared bot. Before enabling it, implement a strict allowed-chat-ID policy and explicit confirmation for external actions.
3. Require a visible final confirmation before messages, calls, purchases, account/security changes, or form submissions.
4. Test on a real device with screenshots and a declared permission audit before distributing an APK.

## Licensing block

The upstream repository does not declare a license. That means source reuse and redistribution rights are not established. Do not publish modified source/releases as open-source or distribute a derivative APK until the upstream author provides an explicit license or written permission.

## Recommended bridge design

If direct Hermes control is wanted, build it as a separate reviewed feature:

- pair a specific device with a short-lived, locally stored token;
- bind only to a local/private network surface—never an unauthenticated public listener;
- accept a constrained typed action schema, not unrestricted natural-language remote commands;
- support allowlists, user confirmation for external effects, cancellation, and append-only action audit records;
- default to disabled, with no background Telegram command execution.

## Build and device readiness (2026-08-17)

Flutter 3.47.0/Dart 3.13.0, Android SDK platform 36/build-tools 36.0.0, and JDK 17 are now installed and configured. Flutter analytics was disabled. `flutter test` passed four Dart tests and `flutter build apk --debug` produced a debug APK.

The APK permission audit remains a blocker for unattended use: it currently declares broad permissions including Internet, microphone, contacts, calls, SMS sending, package visibility, settings changes, and foreground service. This build is evidence of compilation only—not of safe deployment or real-device behavior. No Android device is attached, no Accessibility permission has been enabled, and no network/Hermes/Cron endpoint has been added.

## v0 control-plane core (2026-08-17)

A host-only reference core lives in `fleet_control/`, with protocol documentation at `docs/FLEET-CONTROL-PROTOCOL.md`. It pairs named devices into a local owner-only registry, validates only the read-only `open_app` and `read_current_screen` action types, checks exact package allowlists, and produces five-minute signed dispatch envelopes. Its tests run with the macOS system Python.

The Android app now also contains a separate pure-Dart `StatusEnvelopeVerifier`. It accepts only a signed, unexpired `device.status.get` envelope and performs no Android action. This is the first companion-side conformance boundary; it remains unconnected to the current broad Accessibility executor.

No transport, Cron/Hermes job adapter, real-device execution, or permission minimization has been completed. Do not interpret a locally created envelope or APK as a command delivered to a phone.
