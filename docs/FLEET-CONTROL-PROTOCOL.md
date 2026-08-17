# Fleet Control Protocol v0

**Status:** implemented locally and host-tested only. This is a reference control-plane core, not a live Android remote-control service.

## Boundary

The Python package `fleet_control/` is deliberately narrow:

- It registers a named device and its app-package allowlist in an owner-only JSON state file.
- It accepts only two action types: `open_app` and `read_current_screen`.
- It refuses raw natural-language jobs and rejects every unrecognised action—including messages, posts, purchases, calls, form submission, account changes, and screen-coordinate tapping.
- It creates an HMAC-SHA256-signed, five-minute dispatch envelope.
- It does **not** open ports, connect to a phone, call Android Accessibility APIs, schedule cron jobs, invoke an LLM, or enable Telegram polling.

The pairing token is returned only at pairing time and is persisted only as a SHA-256 hash. The controller's per-device signing key is local state protected by owner-only file permissions. A production companion pairing flow must establish the same signing key with the phone over an authenticated private channel; that is not built yet.

## Job schema

```json
{
  "device_id": "pixel-test",
  "actions": [
    {"type": "open_app", "package": "com.example.calendar"},
    {"type": "read_current_screen"}
  ]
}
```

`open_app.package` must be syntactically valid and must match the paired device’s exact allowlist. `read_current_screen` has no arguments.

## Local demonstration

```bash
STATE="$(mktemp -d)/devices.json"
python3 -m fleet_control --state-file "$STATE" pair pixel-test \
  --allow-package com.example.calendar

printf '%s' '{"device_id":"pixel-test","actions":[{"type":"open_app","package":"com.example.calendar"}]}' > /tmp/fleet-job.json
python3 -m fleet_control --state-file "$STATE" dispatch /tmp/fleet-job.json
```

The output envelope is local evidence that the request passed the policy. It does not mean any phone received or executed it.

## Required next slice

1. Implement the Android companion-side pairing handshake and signature/expiry verification.
2. Add a foreground-only, user-visible executor that can handle the two v0 actions and report typed outcomes.
3. Add a private authenticated transport—prefer an outbound connection from phone to a Hermes-side relay, not an exposed inbound phone listener.
4. Install Flutter/Android tooling, build an APK, audit permissions, and perform screenshot-backed real-device tests.
5. Only after that, connect Hermes cron to submitted jobs. Consequential action types remain confirmation-gated by design.
