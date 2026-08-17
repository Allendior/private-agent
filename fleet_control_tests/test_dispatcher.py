import base64
import hashlib
import hmac
import json
from pathlib import Path
import tempfile
import time
import unittest

from fleet_control.dispatcher import dispatch
from fleet_control.registry import DeviceRegistry


class DispatcherTests(unittest.TestCase):
    def setUp(self):
        self.temp_directory = tempfile.TemporaryDirectory()
        self.registry = DeviceRegistry(Path(self.temp_directory.name) / "devices.json")
        self.device, _ = self.registry.pair("pixel-test", ["com.example.calendar"])

    def tearDown(self):
        self.temp_directory.cleanup()

    def test_creates_signed_expiring_envelope_for_allowlisted_open_app(self):
        result = dispatch(
            self.registry,
            {"device_id": "pixel-test", "actions": [{"type": "open_app", "package": "com.example.calendar"}]},
            now=1_700_000_000,
        )

        self.assertTrue(result.accepted)
        self.assertEqual(result.code, "OK")
        self.assertIsNotNone(result.envelope)
        envelope = result.envelope
        self.assertIsNotNone(envelope)
        assert envelope is not None
        self.assertEqual(envelope["payload"]["device_id"], "pixel-test")
        self.assertEqual(envelope["payload"]["expires_at"], 1_700_000_300)
        self.assertIn("job_id", envelope["payload"])
        self.assertTrue(envelope["signature"])
        base64.urlsafe_b64decode(envelope["signature"] + "===")
        canonical_payload = json.dumps(
            envelope["payload"], sort_keys=True, separators=(",", ":"), ensure_ascii=True
        ).encode("utf-8")
        expected_signature = base64.urlsafe_b64encode(
            hmac.new(
                self.device.signing_key.encode("utf-8"),
                canonical_payload,
                hashlib.sha256,
            ).digest()
        ).decode("ascii").rstrip("=")
        self.assertEqual(envelope["signature"], expected_signature)

    def test_rejects_package_outside_device_allowlist(self):
        result = dispatch(
            self.registry,
            {"device_id": "pixel-test", "actions": [{"type": "open_app", "package": "com.example.mail"}]},
        )

        self.assertFalse(result.accepted)
        self.assertEqual(result.code, "PACKAGE_NOT_ALLOWED")

    def test_dispatches_status_probe_without_app_allowlist(self):
        result = dispatch(
            self.registry,
            {"device_id": "pixel-test", "actions": [{"type": "device.status.get"}]},
            now=1_700_000_000,
        )

        self.assertTrue(result.accepted)
        envelope = result.envelope
        self.assertIsNotNone(envelope)
        assert envelope is not None
        self.assertEqual(envelope["payload"]["actions"], [{"type": "device.status.get"}])

    def test_rejects_unpaired_device(self):
        result = dispatch(
            self.registry,
            {"device_id": "unknown-phone", "actions": [{"type": "read_current_screen"}]},
        )

        self.assertFalse(result.accepted)
        self.assertEqual(result.code, "DEVICE_NOT_PAIRED")


if __name__ == "__main__":
    unittest.main()
