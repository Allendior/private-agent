"""CLI for the local-only Android fleet control-plane reference implementation."""

import argparse
import json
from pathlib import Path
from typing import Optional, Sequence

from .dispatcher import dispatch
from .registry import DeviceRegistry


def _print(value: object) -> None:
    print(json.dumps(value, sort_keys=True, separators=(",", ":")))


def main(argv: Optional[Sequence[str]] = None) -> int:
    parser = argparse.ArgumentParser(description="Local Android fleet control-plane core")
    parser.add_argument("--state-file", type=Path, required=True)
    subcommands = parser.add_subparsers(dest="command", required=True)

    pair_parser = subcommands.add_parser("pair", help="create a local paired-device record")
    pair_parser.add_argument("device_id")
    pair_parser.add_argument("--allow-package", action="append", required=True)

    dispatch_parser = subcommands.add_parser("dispatch", help="validate and sign a local envelope")
    dispatch_parser.add_argument("job_file", type=Path)

    arguments = parser.parse_args(argv)
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

    result = dispatch(registry, job)
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
