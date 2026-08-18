"""Fail-closed validation for Android fleet job requests.

This module permits only the typed v0/v1 action set. It does not connect to a
phone or execute Android accessibility operations.
"""

from dataclasses import dataclass
import re
from typing import Any, Mapping


_PACKAGE_NAME = re.compile(r"^[A-Za-z][A-Za-z0-9_]*(?:\.[A-Za-z][A-Za-z0-9_]*)+$")
_ALLOWED_ACTIONS = frozenset({
    "open_app",
    "read_current_screen",
    "device.status.get",
    "tap_label",
    "tap_xy",
    "press_back",
    "press_home",
    "type_text",
})


@dataclass(frozen=True)
class ValidationResult:
    accepted: bool
    code: str
    detail: str = ""


def _is_int(value: Any) -> bool:
    return isinstance(value, int) and not isinstance(value, bool)


def validate_job(job: Any) -> ValidationResult:
    """Validate a typed job without coercion or implicit permission expansion."""
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
        elif action_type == "tap_label":
            label = action.get("label")
            if (
                set(action) != {"type", "label"}
                or not isinstance(label, str)
                or not label.strip()
                or len(label) > 80
                or "\n" in label
            ):
                return ValidationResult(False, "INVALID_ACTION", "tap_label needs only a label")
        elif action_type == "tap_xy":
            x = action.get("x")
            y = action.get("y")
            if set(action) != {"type", "x", "y"} or not _is_int(x) or not _is_int(y):
                return ValidationResult(False, "INVALID_ACTION", "tap_xy needs integer x,y")
            x_int = int(x)
            y_int = int(y)
            if not (0 <= x_int <= 10000) or not (0 <= y_int <= 10000):
                return ValidationResult(False, "INVALID_ACTION", "tap_xy needs integer x,y")
        elif action_type == "type_text":
            text = action.get("text")
            if (
                set(action) != {"type", "text"}
                or not isinstance(text, str)
                or text == ""
                or len(text) > 500
            ):
                return ValidationResult(False, "INVALID_ACTION", "type_text needs text")
        elif set(action) != {"type"}:
            return ValidationResult(False, "INVALID_ACTION", f"{action_type} has no arguments")

    return ValidationResult(True, "OK")
