"""Bounded dispatch-envelope creation; transport is intentionally absent."""

import base64
from dataclasses import dataclass
import hashlib
import hmac
import json
import time
from typing import Any, Dict, Mapping, Optional
from uuid import uuid4

from .policy import validate_job
from .registry import DeviceRegistry


@dataclass(frozen=True)
class DispatchResult:
    accepted: bool
    code: str
    envelope: Optional[Dict[str, Any]] = None


def dispatch(
    registry: DeviceRegistry,
    job: Mapping[str, Any],
    now: Optional[int] = None,
) -> DispatchResult:
    """Validate and sign a 5-minute device-specific job envelope.

    The caller remains responsible for any future authenticated transport.
    """
    validation = validate_job(job)
    if not validation.accepted:
        return DispatchResult(False, validation.code)

    device_id = job["device_id"]
    device = registry.get(device_id)
    if device is None:
        return DispatchResult(False, "DEVICE_NOT_PAIRED")

    for action in job["actions"]:
        if action["type"] == "open_app" and action["package"] not in device.allowed_packages:
            return DispatchResult(False, "PACKAGE_NOT_ALLOWED")

    created_at = int(time.time()) if now is None else int(now)
    payload = {
        "version": 1,
        "job_id": str(uuid4()),
        "device_id": device_id,
        "actions": [dict(action) for action in job["actions"]],
        "created_at": created_at,
        "expires_at": created_at + 300,
    }
    encoded_payload = json.dumps(
        payload, sort_keys=True, separators=(",", ":"), ensure_ascii=True
    ).encode("utf-8")
    signature = hmac.new(
        device.signing_key.encode("utf-8"), encoded_payload, hashlib.sha256
    ).digest()
    return DispatchResult(
        True,
        "OK",
        {
            "payload": payload,
            "signature": base64.urlsafe_b64encode(signature).decode("ascii").rstrip("="),
        },
    )
