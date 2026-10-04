#!/usr/bin/env python3
"""Read or toggle Voxtype's built-in Whisper translation setting."""
from __future__ import annotations

import json
import subprocess
import sys


KEY = "whisper.translate"


def run(*args: str) -> str:
    result = subprocess.run(args, check=False, capture_output=True, text=True, timeout=120)
    if result.returncode != 0:
        message = result.stderr.strip() or result.stdout.strip() or f"{args[0]} exited {result.returncode}"
        raise RuntimeError(message)
    return result.stdout.strip()


def current_setting() -> bool:
    data = json.loads(run("voxtype", "config", "get", "--json", KEY))
    value = data.get("value")
    if not isinstance(value, bool):
        raise RuntimeError(f"Voxtype returned an invalid value for {KEY}")
    return value


def main() -> int:
    if len(sys.argv) == 2 and sys.argv[1] == "get":
        print(json.dumps({"enabled": current_setting()}))
        return 0

    if len(sys.argv) == 3 and sys.argv[1] == "set" and sys.argv[2] in ("true", "false"):
        enabled = sys.argv[2] == "true"
        if current_setting() != enabled:
            run("voxtype", "config", "set", KEY, sys.argv[2])
            run("systemctl", "--user", "restart", "voxtype")
        print(json.dumps({"enabled": enabled}))
        return 0

    print("usage: hud-translation.py get | set true|false", file=sys.stderr)
    return 2


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError, subprocess.SubprocessError, json.JSONDecodeError) as error:
        print(str(error), file=sys.stderr)
        raise SystemExit(1)
