import json
import os
from pathlib import Path
import tempfile
import unittest

from fleet_control.registry import DeviceRegistry


class DeviceRegistryTests(unittest.TestCase):
    def setUp(self):
        self.temp_directory = tempfile.TemporaryDirectory()
        self.state_path = Path(self.temp_directory.name) / "devices.json"
        self.registry = DeviceRegistry(self.state_path)

    def tearDown(self):
        self.temp_directory.cleanup()

    def test_pairing_persists_hash_not_raw_token_and_authenticates(self):
        device, raw_token = self.registry.pair(
            device_id="pixel-test",
            allowed_packages=["com.example.calendar"],
        )

        persisted = json.loads(self.state_path.read_text())
        self.assertEqual(device.device_id, "pixel-test")
        self.assertNotIn(raw_token, self.state_path.read_text())
        self.assertIn("token_hash", persisted["devices"]["pixel-test"])
        self.assertTrue(self.registry.authenticate("pixel-test", raw_token))
        self.assertFalse(self.registry.authenticate("pixel-test", "wrong-token"))
        self.assertEqual(os.stat(self.state_path).st_mode & 0o777, 0o600)

    def test_rejects_duplicate_device_id(self):
        self.registry.pair("pixel-test", ["com.example.calendar"])

        with self.assertRaisesRegex(ValueError, "already paired"):
            self.registry.pair("pixel-test", ["com.example.calendar"])


if __name__ == "__main__":
    unittest.main()
