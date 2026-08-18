---
name: argo
description: Drive paired Android phones with signed typed jobs.
version: 0.1.0
author: Allen Ghanghas (Allendior), Hermes Agent
license: MIT
platforms: [linux, macos]
metadata:
  hermes:
    tags: [Android, Fleet, Accessibility, Privacy, Hermes]
    homepage: https://github.com/Allendior/private-agent
---

# Argo

Argo is Hermes' ship for Android phones. Hermes plans. The phone executes signed, allowlisted jobs. There is no on-device LLM and no raw prompt-to-tap path.

Use only `companion/` + `fleet_control/` in this repo. Do not enable the upstream PrivateAgent Accessibility/LLM/Telegram app.

## When to Use

- Pair a phone, dispatch `open_app` / `read_current_screen` / tap / type / Home / Back.
- Schedule a bounded phone workflow from Hermes chat or cron.
- Audit or extend the fail-closed action policy.

Don't use for general ADB chores with no Argo companion, or for messages, posts, payments, or account changes without a separate explicit confirmation.

## Prerequisites

- Python 3.9+ (stdlib only for `fleet_control`)
- Flutter + Android SDK to build the companion
- `adb` and a USB-authorized phone
- A private LAN or Tailscale path from phone to host `:8787`

## Quick Reference

```bash
python3 -m fleet_control --status-state-file execution/fleet-control/status-state.json status-serve --bind 0.0.0.0

python3 -m fleet_control --status-state-file execution/fleet-control/status-state.json status-activate DEVICE_ID > /tmp/activation.json
adb shell am force-stop com.allendior.private_agent_companion
cat /tmp/activation.json | adb shell "run-as com.allendior.private_agent_companion sh -c 'cat > files/pending_activation.json'"
adb shell am start -n com.allendior.private_agent_companion/.MainActivity

python3 -m fleet_control \
  --state-file execution/fleet-control/registry.json \
  --status-state-file execution/fleet-control/status-state.json \
  dispatch-send job.json
```

Job file:

```json
{
  "device_id": "pixel-4-xl",
  "actions": [
    {"type": "open_app", "package": "org.telegram.messenger"},
    {"type": "read_current_screen"}
  ]
}
```

Allowlisted actions: `device.status.get`, `open_app`, `read_current_screen`, `tap_label`, `tap_xy`, `press_back`, `press_home`, `type_text`. Unknown actions fail closed.

## Procedure

1. Clone this repo. Completion: `fleet_control/` and `companion/` exist.
2. Build and install the companion: `terminal(command="flutter build apk --debug && adb install -r build/app/outputs/flutter-apk/app-debug.apk", workdir="companion", timeout=600)`. Completion: `pm path com.allendior.private_agent_companion` prints a path.
3. Grant Usage Access and enable the companion Accessibility service. Completion: Usage Access is allow; `CompanionA11yService` is enabled.
4. Pair (`pair` + `status-activate`) and start `status-serve` on `:8787`. Completion: `[bootstrap] auto-probe: OK` and a listen notification is visible.
5. Dispatch with `dispatch-send`. Completion: status-state result is `status=ok`.
6. Fail closed on lock screen, missing Accessibility, missing Usage Access, unknown actions, or signature mismatch.

## Pitfalls

- Activation tokens expire in 60s. Generate, push, start in one sequence.
- Dart `HttpClient` must set `Content-Length`.
- Job HMAC uses domain `private-agent/job-request/v1` and the status-state shared key.
- Android 11+ `open_app` needs `<queries>` for the target package.
- After `open_app` the listen foreground service must stay up.
- Never put pairing keys, activation JSON, or status-state files in git or chat.

## Verification

- `python3 -m unittest discover -s fleet_control_tests -v` passes.
- `flutter test` in `companion/` passes.
- A real device job returns `status=ok`.

## Install this skill

```bash
hermes skills install https://raw.githubusercontent.com/Allendior/private-agent/main/skills/argo/SKILL.md
```
