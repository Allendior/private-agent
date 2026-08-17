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

    def test_dispatch_reports_invalid_non_string_action_type_as_json(self):
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
        malformed_job = Path(self.temp_directory.name) / "malformed.json"
        malformed_job.write_text(
            json.dumps({"device_id": "pixel-test", "actions": [{"type": []}]})
        )

        dispatch = subprocess.run(
            [
                sys.executable,
                "-m",
                "fleet_control",
                "--state-file",
                str(self.state_path),
                "dispatch",
                str(malformed_job),
            ],
            capture_output=True,
            check=False,
            text=True,
        )

        self.assertEqual(dispatch.returncode, 2)
        self.assertEqual(json.loads(dispatch.stdout)["code"], "INVALID_ACTION")

    def test_status_activation_and_revoke_manage_separate_owner_only_state(self):
        status_path = Path(self.temp_directory.name) / "status.json"
        activate = subprocess.run(
            [
                sys.executable,
                "-m",
                "fleet_control",
                "--status-state-file",
                str(status_path),
                "status-activate",
                "pixel-test",
            ],
            capture_output=True,
            check=False,
            text=True,
        )
        self.assertEqual(activate.returncode, 0, activate.stderr)
        payload = json.loads(activate.stdout)
        self.assertEqual(set(payload), {"version", "activation_id", "device_id", "shared_key", "endpoint", "expires_at"})
        self.assertEqual(payload["device_id"], "pixel-test")
        self.assertEqual(len(payload["activation_id"]), 32)
        self.assertEqual(len(payload["shared_key"]), 43)

        revoke = subprocess.run(
            [
                sys.executable,
                "-m",
                "fleet_control",
                "--status-state-file",
                str(status_path),
                "status-revoke",
                "pixel-test",
            ],
            capture_output=True,
            check=False,
            text=True,
        )
        self.assertEqual(revoke.returncode, 0, revoke.stderr)
        self.assertEqual(json.loads(revoke.stdout), {"revoked": False})


if __name__ == "__main__":
    unittest.main()
