"""Local paired-device registry for the v0 fleet control plane."""

from contextlib import contextmanager
from dataclasses import dataclass
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
from typing import Iterable, Iterator, Optional


_PACKAGE_NAME = re.compile(r"^[A-Za-z][A-Za-z0-9_]*(?:\.[A-Za-z][A-Za-z0-9_]*)+$")
_TOKEN_HASH = re.compile(r"^[0-9a-f]{64}$")


@dataclass(frozen=True)
class Device:
    device_id: str
    allowed_packages: tuple[str, ...]
    signing_key: str


class DeviceRegistry:
    def __init__(self, state_path: Path):
        self._state_path = Path(state_path)
        self._lock_path = self._state_path.with_name(f".{self._state_path.name}.lock")

    def pair(self, device_id: str, allowed_packages: Iterable[str]) -> tuple[Device, str]:
        if not isinstance(device_id, str) or not device_id.strip():
            raise ValueError("device_id is required")
        packages = tuple(allowed_packages)
        if (
            not packages
            or len(packages) > 64
            or len(set(packages)) != len(packages)
            or not all(isinstance(package, str) and _PACKAGE_NAME.fullmatch(package) for package in packages)
        ):
            raise ValueError("allowed packages must be unique Android package names")

        with self._exclusive_lock():
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

    @contextmanager
    def _exclusive_lock(self) -> Iterator[None]:
        self._state_path.parent.mkdir(parents=True, exist_ok=True)
        descriptor = os.open(self._lock_path, os.O_CREAT | os.O_RDWR, 0o600)
        try:
            fcntl.flock(descriptor, fcntl.LOCK_EX)
            yield
        finally:
            fcntl.flock(descriptor, fcntl.LOCK_UN)
            os.close(descriptor)

    def _read_state(self) -> dict:
        if not self._state_path.exists():
            return {"devices": {}}
        mode = stat.S_IMODE(self._state_path.stat().st_mode)
        if mode != 0o600:
            raise ValueError("registry state must be owner-only (0600)")
        try:
            with self._state_path.open(encoding="utf-8") as state_file:
                state = json.load(state_file)
        except (OSError, json.JSONDecodeError) as error:
            raise ValueError("registry state is malformed") from error
        self._validate_state(state)
        return state

    @staticmethod
    def _validate_state(state: object) -> None:
        if not isinstance(state, dict) or set(state) != {"devices"} or not isinstance(state["devices"], dict):
            raise ValueError("registry state is malformed")
        for device_id, record in state["devices"].items():
            if not isinstance(device_id, str) or not device_id.strip() or not isinstance(record, dict):
                raise ValueError("registry state is malformed")
            if set(record) != {"allowed_packages", "token_hash", "signing_key"}:
                raise ValueError("registry state is malformed")
            packages = record["allowed_packages"]
            if (
                not isinstance(packages, list)
                or not packages
                or len(packages) > 64
                or len(set(packages)) != len(packages)
                or not all(isinstance(package, str) and _PACKAGE_NAME.fullmatch(package) for package in packages)
                or not isinstance(record["token_hash"], str)
                or not _TOKEN_HASH.fullmatch(record["token_hash"])
                or not isinstance(record["signing_key"], str)
                or len(record["signing_key"]) < 32
            ):
                raise ValueError("registry state is malformed")

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
            directory_descriptor = os.open(self._state_path.parent, os.O_RDONLY)
            try:
                os.fsync(directory_descriptor)
            finally:
                os.close(directory_descriptor)
        finally:
            if os.path.exists(temporary_path):
                os.unlink(temporary_path)
