import json
from pathlib import Path
import tempfile
import threading
import unittest
from urllib.error import HTTPError
from urllib.request import Request, urlopen

from fleet_control.status_server import create_server
from fleet_control.status_transport import STATUS_ENDPOINT, StatusState, build_request


class StatusServerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.state = StatusState(Path(self.temp.name) / "status.json")
        self.activation = self.state.create_activation("pixel-test", STATUS_ENDPOINT)
        self.server = create_server(self.state, port=0)
        self.addCleanup(self.server.server_close)
        self.thread = threading.Thread(target=self.server.serve_forever)
        self.thread.start()
        self.addCleanup(self._stop)
        self.base = f"http://127.0.0.1:{self.server.server_address[1]}"

    def _stop(self):
        self.server.shutdown()
        self.thread.join(timeout=2)

    def test_binds_loopback_and_accepts_only_status_post(self):
        self.assertEqual(self.server.server_address[0], "127.0.0.1")
        envelope = build_request(
            "pixel-test",
            self.activation["activation_id"],
            self.activation["shared_key"],
            int(self.activation["expires_at"]) - 60,
        )
        request = Request(
            self.base + "/v1/status",
            data=json.dumps(envelope).encode(),
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        with urlopen(request, timeout=2) as response:
            self.assertEqual(response.status, 200)
            self.assertEqual(response.headers["Content-Type"], "application/json")
            self.assertEqual(json.loads(response.read())["payload"]["status"], "ok")

        for request in (
            Request(self.base + "/v1/status", method="GET"),
            Request(self.base + "/other", data=b"{}", method="POST"),
        ):
            with self.assertRaises(HTTPError) as caught:
                urlopen(request, timeout=2)
            self.assertIn(caught.exception.code, (404, 405))

    def test_rejects_non_json_and_oversized_bodies(self):
        for data, content_type in ((b"{}", "text/plain"), (b"x" * 65537, "application/json")):
            request = Request(
                self.base + "/v1/status",
                data=data,
                headers={"Content-Type": content_type},
                method="POST",
            )
            with self.assertRaises(HTTPError) as caught:
                urlopen(request, timeout=2)
            self.assertEqual(caught.exception.code, 400)


if __name__ == "__main__":
    unittest.main()
