"""CLI for the local-only Android fleet control-plane reference implementation."""

import argparse
import json
from pathlib import Path
from typing import Optional, Sequence

from .dispatcher import dispatch
from .registry import DeviceRegistry
from .status_server import create_server
from .status_transport import STATUS_ENDPOINT, StatusState


def _print(value: object) -> None:
    print(json.dumps(value, sort_keys=True, separators=(",", ":")))


def main(argv: Optional[Sequence[str]] = None) -> int:
    parser = argparse.ArgumentParser(description="Local Android fleet control-plane core")
    parser.add_argument("--state-file", type=Path)
    parser.add_argument("--status-state-file", type=Path)
    subcommands = parser.add_subparsers(dest="command", required=True)

    pair_parser = subcommands.add_parser("pair", help="create a local paired-device record")
    pair_parser.add_argument("device_id")
    pair_parser.add_argument("--allow-package", action="append", required=True)

    dispatch_parser = subcommands.add_parser("dispatch", help="validate and sign a local envelope")
    dispatch_parser.add_argument("job_file", type=Path)

    activate_parser = subcommands.add_parser(
        "status-activate", help="create a 60-second one-time status activation"
    )
    activate_parser.add_argument("device_id")

    revoke_parser = subcommands.add_parser(
        "status-revoke", help="revoke a status device and pending activation"
    )
    revoke_parser.add_argument("device_id")

    serve_parser = subcommands.add_parser(
        "status-serve", help="run the loopback-only status backend"
    )
    serve_parser.add_argument("--port", type=int, default=8787)
    serve_parser.add_argument("--bind", type=str, default="127.0.0.1",
                              help="address to bind (default: loopback; use 0.0.0.0 for LAN)")

    arguments = parser.parse_args(argv)
    if arguments.command.startswith("status-"):
        if arguments.status_state_file is None:
            parser.error("--status-state-file is required for status commands")
        status_state = StatusState(arguments.status_state_file)
        if arguments.command == "status-activate":
            try:
                _print(status_state.create_activation(arguments.device_id, STATUS_ENDPOINT))
            except ValueError as error:
                _print({"accepted": False, "code": "ACTIVATION_REJECTED", "detail": str(error)})
                return 2
            return 0
        if arguments.command == "status-revoke":
            try:
                revoked = status_state.revoke(arguments.device_id)
            except ValueError as error:
                _print({"accepted": False, "code": "REVOCATION_REJECTED", "detail": str(error)})
                return 2
            _print({"revoked": revoked})
            return 0
        try:
            server = create_server(status_state, port=arguments.port, bind=arguments.bind)
        except (OSError, ValueError) as error:
            _print({"accepted": False, "code": "SERVER_REJECTED", "detail": str(error)})
            return 2
        try:
            server.serve_forever()
        except KeyboardInterrupt:
            pass
        finally:
            server.server_close()
        return 0

    if arguments.state_file is None:
        parser.error("--state-file is required for pair and dispatch")
    registry = DeviceRegistry(arguments.state_file)

    if arguments.command == "pair":
        try:
            device, pairing_token = registry.pair(
                arguments.device_id, arguments.allow_package
            )
        except ValueError as error:
            _print({"accepted": False, "code": "PAIRING_REJECTED", "detail": str(error)})
            return 2
        _print(
            {
                "accepted": True,
                "device_id": device.device_id,
                "pairing_token": pairing_token,
                "warning": "Record this token now; it is never stored by the controller.",
            }
        )
        return 0

    try:
        with arguments.job_file.open(encoding="utf-8") as job_file:
            job = json.load(job_file)
    except (OSError, json.JSONDecodeError) as error:
        _print({"accepted": False, "code": "INVALID_JOB_FILE", "detail": str(error)})
        return 2

    try:
        result = dispatch(registry, job)
    except ValueError as error:
        _print({"accepted": False, "code": "REGISTRY_ERROR", "detail": str(error)})
        return 2
    _print(
        {
            "accepted": result.accepted,
            "code": result.code,
            **({"envelope": result.envelope} if result.envelope else {}),
        }
    )
    return 0 if result.accepted else 2


if __name__ == "__main__":
    raise SystemExit(main())
