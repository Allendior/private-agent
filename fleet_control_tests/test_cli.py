import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


class FleetControlCliTests(unittest.TestCase):
    def setUp(self):
        self.temp_directory = tempfile.TemporaryDirectory()
        self.state_path = Path(self.temp_directory.name) / "devices.json"

    def tearDown(self):
        self.temp_directory.cleanup()

    def test_pair_prints_token_once_and_dispatch_refuses_unsafe_action(self):
        pair = subprocess.run(
            [
                sys.executable,
                "-m",
                "fleet_control",
                "--state-file",
                str(self.state_path),
                "pair",
                "pixel-test",
                "--allow-package",
                "com.example.calendar",
            ],
            capture_output=True,
            check=False,
            text=True,
        )
        self.assertEqual(pair.returncode, 0, pair.stderr)
        paired = json.loads(pair.stdout)
        self.assertEqual(paired["device_id"], "pixel-test")
        self.assertTrue(paired["pairing_token"])

        unsafe_job = Path(self.temp_directory.name) / "unsafe.json"
        unsafe_job.write_text(
            json.dumps(
                {"device_id": "pixel-test", "actions": [{"type": "send_message"}]}
            )
        )
        dispatch = subprocess.run(
            [
                sys.executable,
                "-m",
                "fleet_control",
                "--state-file",
                str(self.state_path),
                "dispatch",
                str(unsafe_job),
            ],
            capture_output=True,
            check=False,
            text=True,
        )
        self.assertEqual(dispatch.returncode, 2)
        self.assertEqual(json.loads(dispatch.stdout)["code"], "ACTION_NOT_ALLOWED")


if __name__ == "__main__":
    unittest.main()
