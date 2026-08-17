"""Local paired-device registry for the v0 fleet control plane."""

from dataclasses import dataclass
import hashlib
import hmac
import json
import os
from pathlib import Path
import secrets
import tempfile
from typing import Iterable, Optional


@dataclass(frozen=True)
class Device:
    device_id: str
    allowed_packages: tuple[str, ...]
    signing_key: str


class DeviceRegistry:
    def __init__(self, state_path: Path):
        self._state_path = Path(state_path)

    def pair(self, device_id: str, allowed_packages: Iterable[str]) -> tuple[Device, str]:
        if not isinstance(device_id, str) or not device_id.strip():
            raise ValueError("device_id is required")
        packages = tuple(allowed_packages)
        if not packages or not all(isinstance(package, str) and package for package in packages):
            raise ValueError("at least one allowed package is required")

        state = self._read_state()
        if device_id in state["devices"]:
            raise ValueError(f"device {device_id!r} is already paired")

        raw_token = secrets.token_urlsafe(32)
        token_hash = hashlib.sha256(raw_token.encode("utf-8")).hexdigest()
        device = Device(device_id, packages, secrets.token_urlsafe(32))
        state["devices"][device_id] = {
            "allowed_packages": list(packages),
            "token_hash": token_hash,
            "signing_key": device.signing_key,
        }
        self._write_state(state)
        return device, raw_token

    def authenticate(self, device_id: str, raw_token: str) -> bool:
        record = self._read_state()["devices"].get(device_id)
        if record is None or not isinstance(raw_token, str):
            return False
        supplied_hash = hashlib.sha256(raw_token.encode("utf-8")).hexdigest()
        return hmac.compare_digest(record["token_hash"], supplied_hash)

    def get(self, device_id: str) -> Optional[Device]:
        record = self._read_state()["devices"].get(device_id)
        if record is None:
            return None
        return Device(
            device_id=device_id,
            allowed_packages=tuple(record["allowed_packages"]),
            signing_key=record["signing_key"],
        )

    def _read_state(self) -> dict:
        if not self._state_path.exists():
            return {"devices": {}}
        with self._state_path.open(encoding="utf-8") as state_file:
            state = json.load(state_file)
        if not isinstance(state, dict) or not isinstance(state.get("devices"), dict):
            raise ValueError("registry state is malformed")
        return state

    def _write_state(self, state: dict) -> None:
        self._state_path.parent.mkdir(parents=True, exist_ok=True)
        descriptor, temporary_path = tempfile.mkstemp(
            dir=self._state_path.parent,
            prefix=f".{self._state_path.name}.",
            text=True,
        )
        try:
            with os.fdopen(descriptor, "w", encoding="utf-8") as temporary_file:
                json.dump(state, temporary_file, sort_keys=True, separators=(",", ":"))
                temporary_file.flush()
                os.fsync(temporary_file.fileno())
            os.chmod(temporary_path, 0o600)
            os.replace(temporary_path, self._state_path)
            os.chmod(self._state_path, 0o600)
        finally:
            if os.path.exists(temporary_path):
                os.unlink(temporary_path)
