# Argo companion

Separate Flutter app. Hermes talks to the host; this app polls signed jobs.

## What it does

- Pair with a one-time activation, HMAC status + job poll to the host
- Foreground listen service so polling survives `open_app`
- Allowlisted actions: `open_app`, `read_current_screen`, `tap_label`, `tap_xy`, `press_back`, `press_home`, `type_text`, `set_alarm`
- Fail closed on lock screen, missing Usage Access, or missing Accessibility

## What it does not do

- No on-device LLM
- No Telegram bot token
- No raw prompt-to-tap
- No automatic send/post/pay

## Alarm jobs

`set_alarm` uses Android's standard `AlarmClock.ACTION_SET_ALARM` contract rather
than Accessibility taps. The companion validates a 24-hour `hour`, `minute`, and
non-empty `label`, always requests `EXTRA_SKIP_UI`, and reports the native result
through the signed job-result channel.

```json
{"type":"set_alarm","hour":6,"minute":30,"label":"Doraemon wake-up"}
```

The phone may remain locked. The companion still has to be paired, running, and
able to reach the host; an offline or expired job must not be reported as set.

See `../skills/argo/SKILL.md`.
