#!/usr/bin/env python3
"""Parse every GDScript and run all deterministic tests/demos without network services."""
import os
from pathlib import Path
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
godot = os.environ.get("GODOT", "godot")
scripts = sorted(root.glob("addons/**/*.gd"))
commands = [
    [godot, "--headless", "--path", str(root), "--check-only", "--script", str(path)]
    for path in scripts
]
commands += [
    [godot, "--headless", "--path", str(root), "--script", str(path)]
    for folder in ("tests", "examples")
    for path in sorted((root / folder).glob("*.gd"))
]
for command in commands:
    try:
        result = subprocess.run(command, text=True, capture_output=True, timeout=30)
    except subprocess.TimeoutExpired:
        print("FAIL timeout:", Path(command[-1]).relative_to(root))
        sys.exit(1)
    output = result.stdout + result.stderr
    if result.returncode or "SCRIPT ERROR" in output or "ERROR:" in output:
        print(output)
        print("FAIL:", Path(command[-1]).relative_to(root))
        sys.exit(1)
    print("PASS:", Path(command[-1]).relative_to(root))
print(f"Verified {len(scripts)} library scripts and {len(commands) - len(scripts)} tests/examples.")
