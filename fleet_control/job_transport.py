"""Job dispatch transport: signed job queue, poll endpoint, and result storage.

Uses the same HMAC envelope protocol as the status transport. Jobs are
validated by the policy layer, signed by the dispatcher, stored in the
status state file, and polled by the companion device.
"""

from typing import Optional
import time

from .status_transport import (
    StatusState, ProtocolError, parse_strict_json, _validate_envelope,
    _signature, RESPONSE_DOMAIN, REQUEST_DOMAIN, _validate_times,
    _HEX_128, _DEVICE_ID, _validate_ascii_strings,
)

JOB_POLL_KIND = "device.job.poll"
JOB_RESPONSE_KIND = "host.job.response"


def handle_job_poll(state: StatusState, body: str, now: Optional[int] = None) -> dict:
    """Handle a signed job poll request from a paired device.

    Returns pending jobs and any stored results for the device.
    """
    now = int(time.time()) if now is None else now
    envelope = parse_strict_json(body)
    payload, signature = _validate_envelope(envelope)

    # Validate the poll request payload (same schema as heartbeat but different kind)
    _validate_poll_payload(payload, now)

    # Authenticate the device and consume the request ID for replay protection
    key = state.authenticate_job_poll(payload, signature, now)

    # Get pending jobs and results
    jobs = state.pending_jobs(payload["device_id"], now=now)
    results = state.pending_results(payload["device_id"], now=now)

    # Build the response
    response_payload = {
        "version": 1,
        "kind": JOB_RESPONSE_KIND,
        "request_id": payload["request_id"],
        "device_id": payload["device_id"],
        "status": "ok",
        "jobs": jobs,
        "results": results,
        "created_at": now,
        "expires_at": now + 60,
    }
    return {"payload": response_payload, "signature": _signature(response_payload, key, RESPONSE_DOMAIN)}


def _validate_poll_payload(payload: dict, now: int) -> None:
    """Validate a job poll request payload."""
    expected_keys = {"version", "kind", "request_id", "device_id", "activation_id", "created_at", "expires_at"}
    if not isinstance(payload, dict) or set(payload) != expected_keys:
        raise ProtocolError("invalid poll schema")
    _validate_ascii_strings(payload)
    if payload["version"] != 1 or type(payload["version"]) is not int:
        raise ProtocolError("invalid version")
    if payload["kind"] != JOB_POLL_KIND:
        raise ProtocolError("invalid request kind")
    if not isinstance(payload["request_id"], str) or not _HEX_128.fullmatch(payload["request_id"]):
        raise ProtocolError("invalid request ID")
    if not isinstance(payload["device_id"], str) or not _DEVICE_ID.fullmatch(payload["device_id"]):
        raise ProtocolError("invalid device ID")
    activation = payload["activation_id"]
    if not isinstance(activation, str) or (activation != "" and not _HEX_128.fullmatch(activation)):
        raise ProtocolError("invalid activation ID")
    _validate_times(payload, now)


def handle_job_result(state: StatusState, body: str, now: Optional[int] = None) -> dict:
    """Handle a signed job result report from a paired device.

    The device reports the outcome of a previously-delivered job.
    """
    now = int(time.time()) if now is None else now
    envelope = parse_strict_json(body)
    payload, signature = _validate_envelope(envelope)

    # Validate the result report payload
    _validate_result_payload(payload, now)

    # Authenticate and store the result
    key = state.authenticate_job_result(payload, signature, now)
    state.store_result(payload["device_id"], payload["job_id"], payload["result"], now=now)
    state.mark_job_delivered(payload["device_id"], payload["job_id"])

    response_payload = {
        "version": 1,
        "kind": "host.job.ack",
        "request_id": payload["request_id"],
        "device_id": payload["device_id"],
        "status": "ok",
        "created_at": now,
        "expires_at": now + 60,
    }
    return {"payload": response_payload, "signature": _signature(response_payload, key, RESPONSE_DOMAIN)}


def _validate_result_payload(payload: dict, now: int) -> None:
    """Validate a job result report payload."""
    expected_keys = {"version", "kind", "request_id", "device_id", "activation_id",
                     "job_id", "result", "created_at", "expires_at"}
    if not isinstance(payload, dict) or set(payload) != expected_keys:
        raise ProtocolError("invalid result schema")
    _validate_ascii_strings(payload)
    if payload["version"] != 1 or type(payload["version"]) is not int:
        raise ProtocolError("invalid version")
    if payload["kind"] != "device.job.result":
        raise ProtocolError("invalid request kind")
    if not isinstance(payload["request_id"], str) or not _HEX_128.fullmatch(payload["request_id"]):
        raise ProtocolError("invalid request ID")
    if not isinstance(payload["device_id"], str) or not _DEVICE_ID.fullmatch(payload["device_id"]):
        raise ProtocolError("invalid device ID")
    if not isinstance(payload["job_id"], str) or len(payload["job_id"]) > 128:
        raise ProtocolError("invalid job ID")
    if not isinstance(payload["result"], dict):
        raise ProtocolError("invalid result")
    activation = payload["activation_id"]
    if not isinstance(activation, str) or (activation != "" and not _HEX_128.fullmatch(activation)):
        raise ProtocolError("invalid activation ID")
    _validate_times(payload, now)
