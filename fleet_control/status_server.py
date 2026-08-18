"""Loopback-only HTTP backend for the private status transport."""

from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
from typing import cast

from .status_transport import ProtocolError, StatusState, handle_status_request

_MAX_BODY = 65_536


class _LoopbackStatusServer(ThreadingHTTPServer):
    allow_reuse_address = False
    daemon_threads = True

    def __init__(self, address, handler, state: StatusState):
        self.status_state = state
        super().__init__(address, handler)


class _StatusHandler(BaseHTTPRequestHandler):
    def do_GET(self) -> None:
        self._empty_error(405)

    def do_HEAD(self) -> None:
        self._empty_error(405)

    def do_PUT(self) -> None:
        self._empty_error(405)

    def do_DELETE(self) -> None:
        self._empty_error(405)

    def do_PATCH(self) -> None:
        self._empty_error(405)

    def do_POST(self) -> None:
        ct = self.headers.get("Content-Type", "")
        import sys
        print(f"[DEBUG] POST path={self.path} ct={ct!r} cl={self.headers.get('Content-Length')}", file=sys.stderr, flush=True)
        if self.path != "/v1/status":
            self._empty_error(404)
            return
        if self.headers.get("Content-Type", "").split(";", 1)[0].strip().lower() != "application/json":
            self._empty_error(400)
            return
        try:
            length = int(self.headers.get("Content-Length", "-1"))
        except ValueError:
            self._empty_error(400)
            return
        if length < 1 or length > _MAX_BODY:
            self._empty_error(400)
            return
        try:
            body = self.rfile.read(length).decode("utf-8", errors="strict")
            server = cast(_LoopbackStatusServer, self.server)
            response = handle_status_request(server.status_state, body)
        except (UnicodeError, ProtocolError, ValueError):
            self._empty_error(400)
            return
        encoded = json.dumps(response, sort_keys=True, separators=(",", ":")).encode("ascii")
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(encoded)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.end_headers()
        self.wfile.write(encoded)

    def _empty_error(self, status: int) -> None:
        self.send_response(status)
        self.send_header("Content-Length", "0")
        self.send_header("Cache-Control", "no-store")
        self.end_headers()

    def log_message(self, format: str, *args: object) -> None:
        # Requests carry credentials. Do not emit paths, bodies, or headers.
        return


def create_server(state: StatusState, port: int = 8787, bind: str = "127.0.0.1") -> ThreadingHTTPServer:
    """Validate owner-only state, then create (but do not start) a server.

    By default binds to loopback only. Pass ``bind="0.0.0.0"`` or a LAN
    address to allow local-network connections. The HMAC signed-envelope
    protocol provides authentication, replay protection, and integrity
    independent of transport-layer encryption.
    """
    state.validate()
    return _LoopbackStatusServer((bind, port), _StatusHandler, state)
