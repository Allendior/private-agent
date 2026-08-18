# Argo companion

Separate Flutter app. Hermes talks to the host; this app polls signed jobs.

## What it does

- Pair with a one-time activation, HMAC status + job poll to the host
- Foreground listen service so polling survives `open_app`
- Allowlisted actions: `open_app`, `read_current_screen`, `tap_label`, `tap_xy`, `press_back`, `press_home`, `type_text`
- Fail closed on lock screen, missing Usage Access, or missing Accessibility

## What it does not do

- No on-device LLM
- No Telegram bot token
- No raw prompt-to-tap
- No automatic send/post/pay

See `../skills/argo/SKILL.md`.
