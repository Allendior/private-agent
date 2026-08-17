"""Fail-closed validation for Android fleet job requests.

This module intentionally permits only the read-only v0 action set. It does not
connect to a phone or execute Android accessibility operations.
"""

from dataclasses import dataclass
import re
from typing import Any, Mapping


_PACKAGE_NAME = re.compile(r"^[A-Za-z][A-Za-z0-9_]*(?:\.[A-Za-z][A-Za-z0-9_]*)+$")
_ALLOWED_ACTIONS = frozenset({"open_app", "read_current_screen"})


@dataclass(frozen=True)
class ValidationResult:
    accepted: bool
    code: str
    detail: str = ""


def validate_job(job: Any) -> ValidationResult:
    """Validate a v0 job without coercion or implicit permission expansion."""
    if not isinstance(job, Mapping):
        return ValidationResult(False, "INVALID_JOB", "job must be an object")
    device_id = job.get("device_id")
    if not isinstance(device_id, str) or not device_id.strip():
        return ValidationResult(False, "INVALID_DEVICE_ID", "device_id is required")

    actions = job.get("actions")
    if not isinstance(actions, list) or not actions:
        return ValidationResult(False, "INVALID_ACTIONS", "actions must be a non-empty list")

    for action in actions:
        if not isinstance(action, Mapping):
            return ValidationResult(False, "INVALID_ACTION", "each action must be an object")
        action_type = action.get("type")
        if not isinstance(action_type, str):
            return ValidationResult(False, "INVALID_ACTION", "action type must be a string")
        if action_type not in _ALLOWED_ACTIONS:
            return ValidationResult(False, "ACTION_NOT_ALLOWED", str(action_type))
        if action_type == "open_app":
            package = action.get("package")
            if (
                set(action) != {"type", "package"}
                or not isinstance(package, str)
                or not _PACKAGE_NAME.fullmatch(package)
            ):
                return ValidationResult(False, "INVALID_ACTION", "open_app needs only a package name")
        elif set(action) != {"type"}:
            return ValidationResult(False, "INVALID_ACTION", "read_current_screen has no arguments")

    return ValidationResult(True, "OK")
