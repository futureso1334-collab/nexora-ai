"""Subprocess runner. SECURITY-CRITICAL: no shell, minimal env, hard timeout, output cap."""
from __future__ import annotations

import os
import shutil
import signal
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path

# Only these variables reach child processes. LD_PRELOAD/LD_LIBRARY_PATH are loader settings
# needed on Termux (termux-exec); they are copied from the server's own env, never from requests.
PASS_THROUGH = ("PATH", "HOME", "LANG", "LC_ALL", "TERM", "TMPDIR", "TZ", "PREFIX", "USER",
                "LD_LIBRARY_PATH", "LD_PRELOAD", "ANDROID_ROOT", "ANDROID_DATA")
SENSITIVE_MARKERS = ("KEY", "TOKEN", "SECRET", "PASSWORD", "PASSWD", "CREDENTIAL", "AUTH")


@dataclass
class ProcessOutput:
    exit_code: int | None
    stdout: str
    stderr: str
    duration_ms: int
    timed_out: bool
    truncated: bool


def safe_env() -> dict[str, str]:
    env = {k: os.environ[k] for k in PASS_THROUGH if k in os.environ}
    env.update({"CI": "1", "NO_COLOR": "1", "NEXT_TELEMETRY_DISABLED": "1"})
    return env


def redact(text: str) -> str:
    """Best effort: mask values of secret-looking environment variables if they appear in output."""
    for name, val in os.environ.items():
        if len(val) >= 8 and any(m in name.upper() for m in SENSITIVE_MARKERS):
            text = text.replace(val, "[REDACTED]")
    return text


def resolve_executable(program: str) -> str | None:
    if program.lower() in ("python", "python3"):
        return sys.executable  # the interpreter running the backend (the venv)
    return shutil.which(program, path=safe_env().get("PATH"))


def _clip(data: bytes, limit: int) -> tuple[str, bool]:
    truncated = len(data) > limit
    text = data[:limit].decode("utf-8", errors="replace")
    return redact(text) + ("\n...[output truncated]" if truncated else ""), truncated


def _kill_group(proc: subprocess.Popen) -> None:
    try:
        os.killpg(proc.pid, signal.SIGKILL)  # child runs in its own session/process group
    except (ProcessLookupError, PermissionError):
        proc.kill()


def run_process(argv: list[str], cwd: Path, timeout_s: float, max_bytes: int,
                env: dict[str, str] | None = None) -> ProcessOutput:
    t0 = time.perf_counter()
    ms = lambda: int((time.perf_counter() - t0) * 1000)  # noqa: E731
    try:
        proc = subprocess.Popen(argv, cwd=str(cwd), env=env or safe_env(), stdin=subprocess.DEVNULL,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                start_new_session=True, shell=False)
    except OSError as exc:
        return ProcessOutput(None, "", f"could not start process: {exc.strerror or exc}", ms(), False, False)
    timed_out = False
    try:
        out, err = proc.communicate(timeout=timeout_s)
    except subprocess.TimeoutExpired:
        timed_out = True
        _kill_group(proc)
        out, err = proc.communicate()
    so, t1 = _clip(out or b"", max_bytes)
    se, t2 = _clip(err or b"", max_bytes)
    return ProcessOutput(None if timed_out else proc.returncode, so, se, ms(), timed_out, t1 or t2)
