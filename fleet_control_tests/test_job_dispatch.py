"""Tests for the job dispatch and poll transport layer."""

import base64
import hashlib
import hmac
import json
import time
from pathlib import Path
import tempfile

from fleet_control.status_transport import (
    StatusState, STATUS_ENDPOINT,
    build_request, handle_status_request,
    REQUEST_DOMAIN,
    _signature, canonical_json,
)
from fleet_control.job_transport import handle_job_poll
from fleet_control.dispatcher import dispatch
from fleet_control.registry import DeviceRegistry
from fleet_control.policy import validate_job


def _make_state(tmp_path):
    state = StatusState(tmp_path / "status.json")
    state.validate()
    return state


def _pair_device(state, device_id="pixel-4-xl"):
    activation = state.create_activation(device_id, STATUS_ENDPOINT, now=int(time.time()))
    # Consume activation via heartbeat to register the device
    envelope = build_request(
        device_id=device_id,
        activation_id=activation["activation_id"],
        key=activation["shared_key"],
        now=int(time.time()),
    )
    handle_status_request(state, json.dumps(envelope, sort_keys=True, separators=(",", ":")))
    return activation["shared_key"]


def test_job_queue_store_and_retrieve(tmp_path):
    """A signed job can be stored in the queue and retrieved by device_id."""
    state = _make_state(tmp_path)
    key = _pair_device(state)

    job_payload = {
        "version": 1,
        "job_id": "abc123",
        "device_id": "pixel-4-xl",
        "actions": [{"type": "open_app", "package": "com.google.android.youtube"}],
        "created_at": int(time.time()),
        "expires_at": int(time.time()) + 300,
    }
    encoded = json.dumps(job_payload, sort_keys=True, separators=(",", ":")).encode("utf-8")
    sig = base64.urlsafe_b64encode(
        hmac.new(key.encode("utf-8"), encoded, hashlib.sha256).digest()
    ).decode("ascii").rstrip("=")
    envelope = {"payload": job_payload, "signature": sig}

    state.enqueue_job("pixel-4-xl", envelope, now=int(time.time()))

    jobs = state.pending_jobs("pixel-4-xl", now=int(time.time()))
    assert len(jobs) == 1
    assert jobs[0]["payload"]["job_id"] == "abc123"
    assert jobs[0]["payload"]["actions"][0]["package"] == "com.google.android.youtube"


def test_job_queue_expires(tmp_path):
    """Expired jobs are not returned."""
    state = _make_state(tmp_path)
    key = _pair_device(state)

    job_payload = {
        "version": 1,
        "job_id": "expired-job",
        "device_id": "pixel-4-xl",
        "actions": [{"type": "open_app", "package": "com.example.app"}],
        "created_at": int(time.time()) - 400,
        "expires_at": int(time.time()) - 100,
    }
    encoded = json.dumps(job_payload, sort_keys=True, separators=(",", ":")).encode("utf-8")
    sig = base64.urlsafe_b64encode(
        hmac.new(key.encode("utf-8"), encoded, hashlib.sha256).digest()
    ).decode("ascii").rstrip("=")
    envelope = {"payload": job_payload, "signature": sig}

    state.enqueue_job("pixel-4-xl", envelope, now=int(time.time()) - 400)

    jobs = state.pending_jobs("pixel-4-xl", now=int(time.time()))
    assert len(jobs) == 0


def test_job_queue_delivered_removed(tmp_path):
    """Once a job is marked delivered, it's not returned again."""
    state = _make_state(tmp_path)
    key = _pair_device(state)

    job_payload = {
        "version": 1,
        "job_id": "job-to-deliver",
        "device_id": "pixel-4-xl",
        "actions": [{"type": "open_app", "package": "com.example.app"}],
        "created_at": int(time.time()),
        "expires_at": int(time.time()) + 300,
    }
    encoded = json.dumps(job_payload, sort_keys=True, separators=(",", ":")).encode("utf-8")
    sig = base64.urlsafe_b64encode(
        hmac.new(key.encode("utf-8"), encoded, hashlib.sha256).digest()
    ).decode("ascii").rstrip("=")
    envelope = {"payload": job_payload, "signature": sig}

    state.enqueue_job("pixel-4-xl", envelope, now=int(time.time()))
    jobs = state.pending_jobs("pixel-4-xl", now=int(time.time()))
    assert len(jobs) == 1
    state.mark_job_delivered("pixel-4-xl", "job-to-deliver")
    jobs = state.pending_jobs("pixel-4-xl", now=int(time.time()))
    assert len(jobs) == 0


def test_job_result_storage(tmp_path):
    """A job result can be stored and retrieved."""
    state = _make_state(tmp_path)
    key = _pair_device(state)

    state.store_result("pixel-4-xl", "job-1", {"status": "ok", "detail": "app opened"}, now=int(time.time()))
    results = state.pending_results("pixel-4-xl", now=int(time.time()))
    assert len(results) == 1
    assert results[0]["job_id"] == "job-1"
    assert results[0]["result"]["status"] == "ok"


def test_job_poll_request_validated(tmp_path):
    """A job poll request uses the same signed-envelope protocol as heartbeat."""
    state = _make_state(tmp_path)
    key = _pair_device(state)

    # Build a job poll request
    now = int(time.time())
    payload = {
        "version": 1,
        "kind": "device.job.poll",
        "request_id": "a" * 32,
        "device_id": "pixel-4-xl",
        "activation_id": "",
        "created_at": now,
        "expires_at": now + 60,
    }
    envelope = {"payload": payload, "signature": _signature(payload, key, REQUEST_DOMAIN)}
    body = json.dumps(envelope, sort_keys=True, separators=(",", ":"))

    response = handle_job_poll(state, body, now=now)
    assert response["payload"]["status"] == "ok"
    assert "jobs" in response["payload"]
    assert isinstance(response["payload"]["jobs"], list)
