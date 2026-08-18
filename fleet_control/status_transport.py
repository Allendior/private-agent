"""Authenticated, replay-safe status-only transport primitives."""

from contextlib import contextmanager
import base64
import binascii
import fcntl
import hashlib
import hmac
import json
import os
from pathlib import Path
import re
import secrets
import stat
import tempfile
import threading
import time
from typing import Iterator, Optional, cast

REQUEST_DOMAIN = b"private-agent/status-request/v1\n"
RESPONSE_DOMAIN = b"private-agent/status-response/v1\n"
STATUS_ENDPOINT = "http://192.168.0.196:8787/v1/status"
_REQUEST_KEYS = {"version", "kind", "request_id", "device_id", "activation_id", "created_at", "expires_at"}
_RESPONSE_KEYS = {"version", "kind", "request_id", "device_id", "status", "created_at", "expires_at"}
_ENVELOPE_KEYS = {"payload", "signature"}
_HEX_128 = re.compile(r"^[0-9a-f]{32}$")
_DEVICE_ID = re.compile(r"^[a-z][a-z0-9-]{2,63}$")
_SIGNATURE = re.compile(r"^[A-Za-z0-9_-]{43}$")


class ProtocolError(ValueError):
    """A fail-closed protocol validation error safe to map to HTTP 400/401/409."""


def _pairs_without_duplicates(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ProtocolError("duplicate JSON key")
        result[key] = value
    return result


def parse_strict_json(value: str) -> object:
    if not isinstance(value, str):
        raise ProtocolError("body must be UTF-8 JSON")
    try:
        return json.loads(value, object_pairs_hook=_pairs_without_duplicates)
    except ProtocolError:
        raise
    except (json.JSONDecodeError, UnicodeError) as error:
        raise ProtocolError("malformed JSON") from error


def canonical_json(value: object) -> bytes:
    try:
        encoded = json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
        encoded.encode("ascii")
    except (TypeError, UnicodeEncodeError) as error:
        raise ProtocolError("protocol values must be ASCII JSON") from error
    return encoded.encode("utf-8")


def _decode_key(key: str) -> bytes:
    if not isinstance(key, str) or not _SIGNATURE.fullmatch(key):
        raise ProtocolError("invalid device key")
    try:
        decoded = base64.urlsafe_b64decode(key + "=")
    except (ValueError, binascii.Error) as error:
        raise ProtocolError("invalid device key") from error
    if len(decoded) != 32 or base64.urlsafe_b64encode(decoded).decode("ascii").rstrip("=") != key:
        raise ProtocolError("invalid device key")
    return decoded


def _signature(payload: dict, key: str, domain: bytes) -> str:
    digest = hmac.new(_decode_key(key), domain + canonical_json(payload), hashlib.sha256).digest()
    return base64.urlsafe_b64encode(digest).decode("ascii").rstrip("=")


def _valid_int(value: object) -> bool:
    return type(value) is int


def _validate_times(payload: dict, now: int) -> None:
    created = payload["created_at"]
    expires = payload["expires_at"]
    if not _valid_int(created) or not _valid_int(expires):
        raise ProtocolError("timestamps must be integer seconds")
    if expires <= created or expires - created > 60:
        raise ProtocolError("TTL exceeds 60 seconds")
    if created > now + 30:
        raise ProtocolError("request is too far in the future")
    if expires <= now:
        raise ProtocolError("message expired")


def _validate_ascii_strings(payload: dict) -> None:
    for value in payload.values():
        if isinstance(value, str):
            try:
                value.encode("ascii")
            except UnicodeEncodeError as error:
                raise ProtocolError("protocol strings must be ASCII") from error


def _validate_envelope(envelope: object) -> tuple[dict, str]:
    if not isinstance(envelope, dict) or set(envelope) != _ENVELOPE_KEYS:
        raise ProtocolError("invalid envelope schema")
    payload = envelope["payload"]
    signature = envelope["signature"]
    if not isinstance(payload, dict) or not isinstance(signature, str) or not _SIGNATURE.fullmatch(signature):
        raise ProtocolError("invalid envelope")
    return payload, signature


def build_request(device_id: str, activation_id: str, key: str, now: int, request_id: Optional[str] = None) -> dict:
    request_id = secrets.token_hex(16) if request_id is None else request_id
    payload = {
        "version": 1,
        "kind": "device.status.heartbeat",
        "request_id": request_id,
        "device_id": device_id,
        "activation_id": activation_id,
        "created_at": now,
        "expires_at": now + 60,
    }
    _validate_request_payload(payload, now)
    return {"payload": payload, "signature": _signature(payload, key, REQUEST_DOMAIN)}


def _validate_request_payload(payload: dict, now: int) -> None:
    if set(payload) != _REQUEST_KEYS:
        raise ProtocolError("invalid request schema")
    _validate_ascii_strings(payload)
    if payload["version"] != 1 or type(payload["version"]) is not int:
        raise ProtocolError("invalid version")
    if payload["kind"] != "device.status.heartbeat":
        raise ProtocolError("invalid request kind")
    if not isinstance(payload["request_id"], str) or not _HEX_128.fullmatch(payload["request_id"]):
        raise ProtocolError("invalid request ID")
    if not isinstance(payload["device_id"], str) or not _DEVICE_ID.fullmatch(payload["device_id"]):
        raise ProtocolError("invalid device ID")
    activation = payload["activation_id"]
    if not isinstance(activation, str) or (activation != "" and not _HEX_128.fullmatch(activation)):
        raise ProtocolError("invalid activation ID")
    _validate_times(payload, now)


def verify_response(body: str, key: str, expected_device_id: str, expected_request_id: str, now: int) -> dict:
    payload, signature = _validate_envelope(parse_strict_json(body))
    if set(payload) != _RESPONSE_KEYS:
        raise ProtocolError("invalid response schema")
    _validate_ascii_strings(payload)
    if payload["version"] != 1 or type(payload["version"]) is not int:
        raise ProtocolError("invalid response version")
    if payload["kind"] != "host.status.response" or payload["status"] != "ok":
        raise ProtocolError("invalid response status")
    if payload["request_id"] != expected_request_id or payload["device_id"] != expected_device_id:
        raise ProtocolError("response identity mismatch")
    if not _HEX_128.fullmatch(expected_request_id) or not _DEVICE_ID.fullmatch(expected_device_id):
        raise ProtocolError("invalid expected identity")
    _validate_times(payload, now)
    expected = _signature(payload, key, RESPONSE_DOMAIN)
    if not hmac.compare_digest(signature, expected):
        raise ProtocolError("invalid response signature")
    return payload


class StatusState:
    """Owner-only atomic activation, registration, and replay state."""

    def __init__(self, path: Path):
        self.path = Path(path)
        self._lock_path = self.path.with_name(f".{self.path.name}.lock")
        self._thread_lock = threading.Lock()

    def validate(self) -> None:
        with self._exclusive_lock():
            self._read()

    def create_activation(self, device_id: str, endpoint: str, now: Optional[int] = None,
                          activation_id: Optional[str] = None, key: Optional[str] = None) -> dict:
        now = int(time.time()) if now is None else now
        activation_id = secrets.token_hex(16) if activation_id is None else activation_id
        key = base64.urlsafe_b64encode(secrets.token_bytes(32)).decode("ascii").rstrip("=") if key is None else key
        if not _DEVICE_ID.fullmatch(device_id) or endpoint != STATUS_ENDPOINT or not _HEX_128.fullmatch(activation_id):
            raise ValueError("invalid activation parameters")
        _decode_key(key)
        with self._exclusive_lock():
            state = self._read()
            if device_id in state["devices"]:
                raise ValueError("device must be revoked before re-pairing")
            state["activations"] = [a for a in state["activations"] if a["expires_at"] > now and a["device_id"] != device_id]
            state["activations"].append({
                "activation_id": activation_id, "device_id": device_id, "key": key,
                "endpoint": endpoint, "expires_at": now + 60, "state": "unused",
            })
            self._write(state)
        return {"version": 1, "activation_id": activation_id, "device_id": device_id,
                "shared_key": key, "endpoint": endpoint, "expires_at": now + 60}

    def revoke(self, device_id: str) -> bool:
        with self._exclusive_lock():
            state = self._read()
            existed = state["devices"].pop(device_id, None) is not None
            state["activations"] = [a for a in state["activations"] if a["device_id"] != device_id]
            state["replays"] = [r for r in state["replays"] if r["device_id"] != device_id]
            self._write(state)
            return existed

    def authenticate_and_consume(self, payload: dict, signature: str, now: int) -> str:
        with self._exclusive_lock():
            state = self._read()
            state["replays"] = [r for r in state["replays"] if r["expires_at"] > now]
            device_id = payload["device_id"]
            activation_id = payload["activation_id"]
            registered = state["devices"].get(device_id)
            if registered is None:
                matches = [a for a in state["activations"] if a["activation_id"] == activation_id and a["device_id"] == device_id]
                if len(matches) != 1 or matches[0]["state"] != "unused" or matches[0]["expires_at"] <= now:
                    raise ProtocolError("invalid or expired activation")
                key = matches[0]["key"]
            else:
                key = registered["key"]
            expected = _signature(payload, key, REQUEST_DOMAIN)
            if not hmac.compare_digest(signature, expected):
                raise ProtocolError("invalid request signature")
            if any(r["device_id"] == device_id and r["request_id"] == payload["request_id"] for r in state["replays"]):
                raise ProtocolError("request replay")
            if registered is not None and activation_id != "":
                raise ProtocolError("activation already consumed")
            if registered is None:
                matches[0]["state"] = "consumed"
                state["devices"][device_id] = {"key": key}
            state["replays"].append({"device_id": device_id, "request_id": payload["request_id"], "expires_at": payload["expires_at"]})
            self._write(state)
            return key

    def consume_request(self, device_id: str, request_id: str, expires_at: int, now: int) -> None:
        with self._exclusive_lock():
            state = self._read()
            state["replays"] = [r for r in state["replays"] if r["expires_at"] > now]
            if any(r["device_id"] == device_id and r["request_id"] == request_id for r in state["replays"]):
                raise ProtocolError("request replay")
            state["replays"].append({"device_id": device_id, "request_id": request_id, "expires_at": expires_at})
            self._write(state)

    @contextmanager
    def _exclusive_lock(self) -> Iterator[None]:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        with self._thread_lock:
            descriptor = os.open(self._lock_path, os.O_CREAT | os.O_RDWR, 0o600)
            try:
                os.chmod(self._lock_path, 0o600)
                fcntl.flock(descriptor, fcntl.LOCK_EX)
                yield
            finally:
                fcntl.flock(descriptor, fcntl.LOCK_UN)
                os.close(descriptor)

    def _read(self) -> dict:
        if not self.path.exists():
            return {"version": 1, "activations": [], "devices": {}, "replays": []}
        if stat.S_IMODE(self.path.stat().st_mode) != 0o600:
            raise ValueError("status state must be owner-only (0600)")
        try:
            state = parse_strict_json(self.path.read_text(encoding="utf-8"))
        except (OSError, ProtocolError) as error:
            raise ValueError("status state is malformed") from error
        self._validate_state(state)
        return cast(dict, state)

    @staticmethod
    def _validate_state(state: object) -> None:
        if not isinstance(state, dict) or set(state) != {"version", "activations", "devices", "replays"} or state["version"] != 1:
            raise ValueError("status state is malformed")
        if not isinstance(state["activations"], list) or not isinstance(state["devices"], dict) or not isinstance(state["replays"], list):
            raise ValueError("status state is malformed")
        for item in state["activations"]:
            if not isinstance(item, dict) or set(item) != {"activation_id", "device_id", "key", "endpoint", "expires_at", "state"}:
                raise ValueError("status state is malformed")
            if not _HEX_128.fullmatch(item["activation_id"]) or not _DEVICE_ID.fullmatch(item["device_id"]) or item["endpoint"] != STATUS_ENDPOINT or type(item["expires_at"]) is not int or item["state"] not in ("unused", "consumed"):
                raise ValueError("status state is malformed")
            _decode_key(item["key"])
        for device_id, item in state["devices"].items():
            if not _DEVICE_ID.fullmatch(device_id) or not isinstance(item, dict) or set(item) != {"key"}:
                raise ValueError("status state is malformed")
            _decode_key(item["key"])
        for item in state["replays"]:
            if not isinstance(item, dict) or set(item) != {"device_id", "request_id", "expires_at"} or not _DEVICE_ID.fullmatch(item["device_id"]) or not _HEX_128.fullmatch(item["request_id"]) or type(item["expires_at"]) is not int:
                raise ValueError("status state is malformed")

    def _write(self, state: dict) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        descriptor, temporary = tempfile.mkstemp(dir=self.path.parent, prefix=f".{self.path.name}.")
        try:
            with os.fdopen(descriptor, "w", encoding="utf-8") as output:
                output.write(canonical_json(state).decode("utf-8"))
                output.flush()
                os.fsync(output.fileno())
            os.chmod(temporary, 0o600)
            os.replace(temporary, self.path)
            os.chmod(self.path, 0o600)
            directory = os.open(self.path.parent, os.O_RDONLY)
            try:
                os.fsync(directory)
            finally:
                os.close(directory)
        finally:
            if os.path.exists(temporary):
                os.unlink(temporary)


def handle_status_request(state: StatusState, body: str, now: Optional[int] = None) -> dict:
    now = int(time.time()) if now is None else now
    payload, signature = _validate_envelope(parse_strict_json(body))
    _validate_request_payload(payload, now)
    key = state.authenticate_and_consume(payload, signature, now)
    response_payload = {
        "version": 1,
        "kind": "host.status.response",
        "request_id": payload["request_id"],
        "device_id": payload["device_id"],
        "status": "ok",
        "created_at": now,
        "expires_at": now + 60,
    }
    return {"payload": response_payload, "signature": _signature(response_payload, key, RESPONSE_DOMAIN)}
