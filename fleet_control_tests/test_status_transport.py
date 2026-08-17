import base64
from concurrent.futures import ThreadPoolExecutor
import hashlib
import hmac
import json
import os
from pathlib import Path
import tempfile
import unittest

from fleet_control.status_transport import (
    REQUEST_DOMAIN,
    RESPONSE_DOMAIN,
    ProtocolError,
    StatusState,
    build_request,
    canonical_json,
    handle_status_request,
    parse_strict_json,
    verify_response,
)


NOW = 1_700_000_000
ENDPOINT = "https://mac-mini-fleet.tailed5697.ts.net/v1/status"
DEVICE = "pixel-test"
KEY = base64.urlsafe_b64encode(bytes(range(32))).decode("ascii").rstrip("=")
ACTIVATION = "00112233445566778899aabbccddeeff"
REQUEST_ID = "ffeeddccbbaa99887766554433221100"


class StatusProtocolTests(unittest.TestCase):
    def test_fixed_request_and_response_vectors_use_distinct_domains(self):
        request = build_request(
            device_id=DEVICE,
            activation_id=ACTIVATION,
            key=KEY,
            now=NOW,
            request_id=REQUEST_ID,
        )
        self.assertEqual(
            request["signature"],
            "MiZYQJqNveNq1i11Bo7RB2ZRwRdOb-tUaEJcJGtSzR0",
        )
        state, temp = self._activated_state()
        self.addCleanup(temp.cleanup)
        response = handle_status_request(state, json.dumps(request), now=NOW + 1)
        self.assertEqual(
            response["signature"],
            "cr-nzS8YWLrbd-MlUGXMwCutbEWtYtfpf8E8pCpYG3I",
        )
        verified = verify_response(
            json.dumps(response),
            key=KEY,
            expected_device_id=DEVICE,
            expected_request_id=REQUEST_ID,
            now=NOW + 2,
        )
        self.assertEqual(verified["status"], "ok")
        self.assertNotEqual(REQUEST_DOMAIN, RESPONSE_DOMAIN)

    def test_strict_json_rejects_duplicate_keys(self):
        with self.assertRaisesRegex(ProtocolError, "duplicate"):
            parse_strict_json('{"payload":{},"payload":{},"signature":"x"}')

    def test_request_validation_rejects_tamper_wrong_key_fields_types_and_time(self):
        state, temp = self._activated_state()
        self.addCleanup(temp.cleanup)
        valid = build_request(DEVICE, ACTIVATION, KEY, NOW, request_id=REQUEST_ID)
        mutations = []
        for field, value in (
            ("kind", "device.status.other"),
            ("device_id", "other-device"),
            ("request_id", "A" * 32),
            ("created_at", True),
            ("expires_at", NOW + 61),
        ):
            item = json.loads(json.dumps(valid))
            item["payload"][field] = value
            mutations.append(item)
        unknown = json.loads(json.dumps(valid))
        unknown["payload"]["extra"] = 1
        mutations.append(unknown)
        non_ascii = json.loads(json.dumps(valid))
        non_ascii["payload"]["device_id"] = "pixel-é"
        mutations.append(non_ascii)
        wrong_key = build_request(DEVICE, ACTIVATION, base64.urlsafe_b64encode(b"x" * 32).decode().rstrip("="), NOW, request_id=REQUEST_ID)
        mutations.append(wrong_key)
        bad_signature = json.loads(json.dumps(valid))
        bad_signature["signature"] = "A" * 43
        mutations.append(bad_signature)

        for envelope in mutations:
            with self.subTest(envelope=envelope):
                with self.assertRaises(ProtocolError):
                    handle_status_request(state, json.dumps(envelope), now=NOW)

        expired = build_request(DEVICE, ACTIVATION, KEY, NOW - 61, request_id="0" * 32)
        with self.assertRaisesRegex(ProtocolError, "expired"):
            handle_status_request(state, json.dumps(expired), now=NOW)
        future = build_request(DEVICE, ACTIVATION, KEY, NOW + 31, request_id="1" * 32)
        with self.assertRaisesRegex(ProtocolError, "future"):
            handle_status_request(state, json.dumps(future), now=NOW)

    def test_activation_is_consumed_once_and_later_requests_use_empty_activation(self):
        state, temp = self._activated_state()
        self.addCleanup(temp.cleanup)
        first = build_request(DEVICE, ACTIVATION, KEY, NOW, request_id=REQUEST_ID)
        handle_status_request(state, json.dumps(first), now=NOW)
        with self.assertRaises(ProtocolError):
            handle_status_request(state, json.dumps(first), now=NOW)

        later = build_request(DEVICE, "", KEY, NOW + 1, request_id="1" * 32)
        handle_status_request(state, json.dumps(later), now=NOW + 1)
        stale_activation = build_request(DEVICE, ACTIVATION, KEY, NOW + 2, request_id="2" * 32)
        with self.assertRaisesRegex(ProtocolError, "activation"):
            handle_status_request(state, json.dumps(stale_activation), now=NOW + 2)

    def test_expired_activation_fails_closed(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        state = StatusState(Path(temp.name) / "status.json")
        state.create_activation(DEVICE, ENDPOINT, now=NOW - 61, activation_id=ACTIVATION, key=KEY)
        request = build_request(DEVICE, ACTIVATION, KEY, NOW, request_id=REQUEST_ID)
        with self.assertRaisesRegex(ProtocolError, "activation"):
            handle_status_request(state, json.dumps(request), now=NOW)

    def test_concurrent_identical_request_succeeds_exactly_once_and_survives_restart(self):
        state, temp = self._activated_state()
        self.addCleanup(temp.cleanup)
        body = json.dumps(build_request(DEVICE, ACTIVATION, KEY, NOW, request_id=REQUEST_ID))

        def attempt():
            try:
                handle_status_request(state, body, now=NOW)
                return True
            except ProtocolError:
                return False

        with ThreadPoolExecutor(max_workers=8) as executor:
            results = list(executor.map(lambda _: attempt(), range(8)))
        self.assertEqual(results.count(True), 1)
        restarted = StatusState(state.path)
        with self.assertRaisesRegex(ProtocolError, "replay"):
            handle_status_request(restarted, body, now=NOW)

    def test_state_is_owner_only_validated_and_prunes_expired_replays(self):
        state, temp = self._activated_state()
        self.addCleanup(temp.cleanup)
        first = build_request(DEVICE, ACTIVATION, KEY, NOW, request_id=REQUEST_ID)
        handle_status_request(state, json.dumps(first), now=NOW)
        self.assertEqual(os.stat(state.path).st_mode & 0o777, 0o600)
        state.consume_request(DEVICE, "1" * 32, NOW + 122, now=NOW + 62)
        persisted = json.loads(state.path.read_text())
        self.assertNotIn(REQUEST_ID, {item["request_id"] for item in persisted["replays"]})
        os.chmod(state.path, 0o644)
        with self.assertRaisesRegex(ValueError, "owner-only"):
            state.validate()

    def _activated_state(self):
        temp = tempfile.TemporaryDirectory()
        state = StatusState(Path(temp.name) / "status.json")
        activation = state.create_activation(
            DEVICE,
            ENDPOINT,
            now=NOW,
            activation_id=ACTIVATION,
            key=KEY,
        )
        self.assertEqual(activation["activation_id"], ACTIVATION)
        self.assertEqual(activation["expires_at"], NOW + 60)
        return state, temp


if __name__ == "__main__":
    unittest.main()
