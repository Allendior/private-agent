# Private status transport v1

## Boundary

A manually pressed foreground-only Companion status probe travels over Tailscale HTTPS to a Python server bound **only** to `127.0.0.1`. It returns an authenticated `ok` response. It does not control the phone, read its UI, run in background, or perform external effects.

## Preconditions

- Tailscale Serve (not Funnel) maps exactly `https://mac-mini-fleet.tailed5697.ts.net/v1/status` to `127.0.0.1:8787`.
- Funnel status stays empty.
- Companion gains only `android.permission.INTERNET`; cleartext remains disabled.
- Server begins only after owner-only registry/audit state validation.

## Activation

1. Host creates a 60-second activation record: random 128-bit `activation_id`, device ID, generated 32-byte base64url device key, exact endpoint, expiry, `unused` state.
2. The local pairing payload includes this activation ID and is transferred directly to the device without chat, logs, or clipboard persistence.
3. First manual probe submits `activation_id`; host atomically consumes it and binds the device registration/key. Any retry, duplicate, or expiry fails closed.
4. Companion deletes the activation ID after a successful response. Re-pair requires host-side revoke and a new activation.

## Wire format

Request signature input is UTF-8 canonical JSON prefixed by:

`private-agent/status-request/v1\n`

Response signature input is UTF-8 canonical JSON prefixed by:

`private-agent/status-response/v1\n`

Request exact payload keys: `version`, `kind=device.status.heartbeat`, `request_id` (128-bit lower-case hex), `device_id`, `activation_id`, `created_at`, `expires_at`. TTL is 60 seconds maximum; timestamps are integer seconds, with 30-second future skew allowance.

Response exact payload keys: `version`, `kind=host.status.response`, `request_id`, `device_id`, `status=ok`, `created_at`, `expires_at`; it has a distinct 60-second TTL. The Companion verifies signature, expected ID, request ID, response kind/status, and expiry.

All signatures are exact 43-character unpadded base64url HMAC-SHA256. Reject duplicate JSON keys, unknown/missing fields, booleans/floats as timestamps, non-ASCII protocol values, and redirects.

## Replay/cache

The host persists accepted `(device_id, request_id, expires_at)` records in owner-only state under exclusive lock. Duplicate requests reject atomically, including concurrent copies and process restart before expiry. Expired cache records are pruned during each request.

## Acceptance gates

- Pure Python and Dart fixed vectors interoperate for request and response.
- Tamper/wrong key/device/kind/field/signature/expiry/request ID reject.
- Identical request concurrently succeeds exactly once.
- Android produces no traffic before manual button press and one request per press.
- Only `POST /v1/status`, HTTPS through Serve, loopback backend; Funnel remains empty.
- APK audit proves `INTERNET` plus generated internal receiver permission only.
- Real Pixel verifies success, replay rejection, Tailscale-off failure, and revoke failure.
