#!/usr/bin/env python3
"""Import a clean copy of this project and run the headless scripts that ship here.

Godot 4.5.1 stable is the measured editor. 4.7.2 fails import with
`Parameter "singleton" is null`. conformance_test.gd is intentionally absent:
its live fixture is not in this repository.
"""

from __future__ import annotations

import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
PINNED_VERSION = "4.5.1"
STAGES = (
    ("protocol", ["--script", "protocol_test.gd"], "HAIVEN_TEST_PASS protocol 13"),
    ("session", ["--script", "session_test.gd"], "HAIVEN_TEST_PASS session 15"),
    ("handoff", ["--script", "handoff_test.gd"], "HAIVEN_TEST_PASS handoff 34"),
)


def enforce_version(version: str, expected: str) -> None:
    if version.startswith(expected + ".stable."):
        return
    raise RuntimeError(f"expected Godot {expected} stable, got {version}")


def run_stage(engine: str, project: Path, logs: Path, name: str, args: list[str], marker: str | None = None) -> None:
    log = logs / f"{name}.log"
    with log.open("w") as output:
        try:
            result = subprocess.run(
                [engine, "--headless", "--path", str(project), *args],
                stdout=output,
                stderr=subprocess.STDOUT,
                timeout=float(os.environ.get("GODOT_TIMEOUT_SECONDS", "120")),
                env={**os.environ, "NO_COLOR": "1"},
                check=False,
            )
        except subprocess.TimeoutExpired as error:
            raise RuntimeError(f"{name} timed out; see {log}") from error
    text = log.read_text(encoding="utf-8", errors="replace")
    print(text, end="", flush=True)
    if result.returncode != 0 or re.search(r"(?:SCRIPT ERROR:|ERROR:|^FAIL\b)", text, re.M):
        raise RuntimeError(f"{name} failed; see {log}")
    if marker and text.splitlines().count(marker) != 1:
        raise RuntimeError(f"{name} did not complete the expected assertions; see {log}")


def ignore_checkout(directory: str, names: list[str]) -> set[str]:
    ignored = {".git", ".godot"}
    if Path(directory) == ROOT:
        ignored.update({"build", ".release-deps"})
    return ignored & set(names)


def main() -> None:
    logs = Path(os.environ.get("GODOT_LOG_DIR", ROOT / "build/godot-results")).resolve()
    logs.mkdir(parents=True, exist_ok=True)
    engine = shutil.which(os.environ.get("GODOT_BIN", "godot"))
    if not engine:
        raise RuntimeError("Godot editor is required; set GODOT_BIN or install godot")
    version = subprocess.check_output([engine, "--version"], text=True, timeout=15).strip()
    (logs / "engine.log").write_text(version + "\n", encoding="utf-8")
    expected = os.environ.get("GODOT_EXPECTED_VERSION", PINNED_VERSION)
    enforce_version(version, expected)
    with tempfile.TemporaryDirectory(prefix="haiven-godot-") as temporary:
        project = Path(temporary) / "project"
        shutil.copytree(ROOT, project, ignore=ignore_checkout)
        run_stage(engine, project, logs, "import", ["--import"])
        cache = project / ".godot/global_script_class_cache.cfg"
        if not cache.is_file():
            raise RuntimeError("editor import did not produce the script class cache")
        for name, args, marker in STAGES:
            run_stage(engine, project, logs, name, args, marker)
    print("ok   Godot 4.5.1 headless checks", flush=True)


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, OSError, subprocess.SubprocessError) as error:
        raise SystemExit(str(error)) from error
