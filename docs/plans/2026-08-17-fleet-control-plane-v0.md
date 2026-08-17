# Android Fleet Control Plane v0 Implementation Plan

> **For Hermes:** Use subagent-driven-development skill to implement this plan task-by-task.

**Goal:** Build a local, testable reference control-plane core that accepts only paired-device, typed, read-only Android jobs and creates a safe execution envelope for a future PrivateAgent companion.

**Architecture:** A dependency-free Python package lives beside the Flutter app so it can be tested on this Mac without Flutter or a connected phone. It owns device pairing records, capability allowlists, job validation, and short-lived signed dispatch envelopes. It deliberately does **not** open a network listener, invoke Android accessibility, process raw natural-language commands, or permit external-effect actions.

**Tech Stack:** Python 3 standard library, `unittest`, JSON state file with owner-only permissions.

---

### Task 1: Define protocol value objects and rejection rules

**Objective:** Model a paired device, two permitted read-only action types, and explicit rejection of unsafe/malformed jobs.

**Files:**
- Create: `fleet_control/models.py`
- Create: `fleet_control/policy.py`
- Test: `fleet_control_tests/test_policy.py`

**Step 1: Write failing test**

```python
from fleet_control.policy import validate_job

def test_rejects_external_effect_action():
    result = validate_job({"device_id": "pixel", "actions": [{"type": "send_message"}]})
    self.assertFalse(result.accepted)
    self.assertEqual(result.code, "ACTION_NOT_ALLOWED")
```

**Step 2: Run test to verify failure**

Run: `python3 -m unittest fleet_control_tests.test_policy -v`
Expected: FAIL — module `fleet_control` does not yet exist.

**Step 3: Write minimal implementation**

Implement `validate_job` with only `open_app` and `read_current_screen`, rejecting all other action names, malformed app package names, missing device IDs, and empty action lists.

**Step 4: Run test to verify pass**

Run: `python3 -m unittest fleet_control_tests.test_policy -v`
Expected: PASS.

### Task 2: Add paired-device registry with local secret storage

**Objective:** Create and authenticate a named device without storing its raw token.

**Files:**
- Create: `fleet_control/registry.py`
- Test: `fleet_control_tests/test_registry.py`

**Step 1: Write failing test**

Test that pairing returns a one-time raw token, the persisted registry excludes that raw token, valid credentials authenticate, and wrong credentials fail.

**Step 2: Run test to verify failure**

Run: `python3 -m unittest fleet_control_tests.test_registry -v`
Expected: FAIL — registry module missing.

**Step 3: Write minimal implementation**

Use `secrets.token_urlsafe`, SHA-256 token hashing, `hmac.compare_digest`, atomic file replacement, and `0600` permissions. Reject duplicate device IDs.

**Step 4: Run test to verify pass**

Run: `python3 -m unittest fleet_control_tests.test_registry -v`
Expected: PASS.

### Task 3: Produce signed, capability-checked dispatch envelopes

**Objective:** Turn a valid job for an authenticated paired device into a bounded, expiring envelope that the future Android companion can verify.

**Files:**
- Create: `fleet_control/dispatcher.py`
- Test: `fleet_control_tests/test_dispatcher.py`

**Step 1: Write failing test**

Test acceptance for `open_app` only when its package is in the paired device’s allowlist; test rejection for an unpaired device and a package outside the allowlist; assert that the created envelope expires and has an HMAC signature.

**Step 2: Run test to verify failure**

Run: `python3 -m unittest fleet_control_tests.test_dispatcher -v`
Expected: FAIL — dispatcher module missing.

**Step 3: Write minimal implementation**

Create a canonical JSON payload with UUID job ID and 5-minute expiry. Sign it with the local device secret. No transport/network behavior is introduced.

**Step 4: Run test to verify pass**

Run: `python3 -m unittest fleet_control_tests.test_dispatcher -v`
Expected: PASS.

### Task 4: Add a CLI and protocol documentation

**Objective:** Make pairing and safe dispatch demonstrable locally, with explicit non-goals.

**Files:**
- Create: `fleet_control/__main__.py`
- Create: `docs/FLEET-CONTROL-PROTOCOL.md`
- Test: `fleet_control_tests/test_cli.py`

**Step 1: Write failing test**

Test `pair` prints a raw token only once and `dispatch` refuses an unsafe job. Do not test or implement live network/device control.

**Step 2: Run test to verify failure**

Run: `python3 -m unittest fleet_control_tests.test_cli -v`
Expected: FAIL — CLI missing.

**Step 3: Write minimal implementation**

Use `argparse`, require a state-file path, and provide `pair` plus `dispatch` subcommands. Write protocol documentation that marks Android transport and execution as future work.

**Step 4: Run full suite**

Run: `python3 -m unittest discover -s fleet_control_tests -v`
Expected: all tests pass.

### Task 5: Verify and commit

**Objective:** Capture exact host-only verification and a clean source change.

**Files:**
- Modify: `docs/HERMES-INTEGRATION.md`

**Steps:**
1. Run full Python test suite.
2. Run `git diff --check` and `git status --short`.
3. Document that no Flutter build, APK audit, network listener, or real-device test occurred.
4. Commit only the reviewed source/tests/docs; do not add state files or credentials.
