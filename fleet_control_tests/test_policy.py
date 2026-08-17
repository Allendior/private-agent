import unittest

from fleet_control.policy import validate_job


class PolicyValidationTests(unittest.TestCase):
    def test_rejects_external_effect_action(self):
        result = validate_job(
            {"device_id": "pixel-test", "actions": [{"type": "send_message"}]}
        )

        self.assertFalse(result.accepted)
        self.assertEqual(result.code, "ACTION_NOT_ALLOWED")

    def test_accepts_read_only_actions(self):
        result = validate_job(
            {
                "device_id": "pixel-test",
                "actions": [
                    {"type": "open_app", "package": "com.example.calendar"},
                    {"type": "read_current_screen"},
                ],
            }
        )

        self.assertTrue(result.accepted)
        self.assertEqual(result.code, "OK")

    def test_rejects_malformed_package(self):
        result = validate_job(
            {
                "device_id": "pixel-test",
                "actions": [{"type": "open_app", "package": "not a package"}],
            }
        )

        self.assertFalse(result.accepted)
        self.assertEqual(result.code, "INVALID_ACTION")

    def test_rejects_non_object_job_without_throwing(self):
        result = validate_job([])

        self.assertFalse(result.accepted)
        self.assertEqual(result.code, "INVALID_JOB")

    def test_rejects_unexpected_open_app_argument(self):
        result = validate_job(
            {
                "device_id": "pixel-test",
                "actions": [
                    {
                        "type": "open_app",
                        "package": "com.example.calendar",
                        "unexpected": True,
                    }
                ],
            }
        )

        self.assertFalse(result.accepted)
        self.assertEqual(result.code, "INVALID_ACTION")

    def test_rejects_non_string_action_type_without_throwing(self):
        result = validate_job(
            {"device_id": "pixel-test", "actions": [{"type": []}]}
        )

        self.assertFalse(result.accepted)
        self.assertEqual(result.code, "INVALID_ACTION")


if __name__ == "__main__":
    unittest.main()
