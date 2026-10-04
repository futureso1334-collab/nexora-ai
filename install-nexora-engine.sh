#!/usr/bin/env bash
# NEXORA Engine V1 installer (Stages 1-4). Adds backend/ only; never touches the frontend source.
#   bash install-nexora-engine.sh               # write files, create venv, install, test, lint+build frontend
#   bash install-nexora-engine.sh --files-only  # just write files (no venv / pip / tests / npm)
# Run from the project root (~/nexora-ai). Does not commit anything.
set -e

FILES_ONLY=0; [ "$1" = "--files-only" ] && FILES_ONLY=1

if [ ! -f package.json ] || ! grep -q '"next"' package.json; then
  echo "ERROR: run from the NEXORA project root (package.json with next)."; exit 1
fi
if [ -e backend/app ]; then
  echo "ERROR: backend/app already exists. Refusing to overwrite. Move it away first."; exit 1
fi
command -v python3 >/dev/null || { echo "ERROR: python3 not found."; exit 1; }
echo "Python: $(python3 --version)"
echo "Git status before install:"; git status --short 2>/dev/null || true; echo "(end)"

mkdir -p backend/app/{routes,agent,tools,services,security} backend/tests
for d in app app/routes app/agent app/tools app/services app/security; do : > backend/$d/__init__.py; done
echo '__version__ = "0.1.0"' > backend/app/__init__.py

# =====================================================================
# Packaging / config files
# =====================================================================
cat > backend/requirements.txt <<'EOF'
# Runtime. Deliberately minimal: no uvicorn[standard] (avoids native uvloop/httptools builds on Termux).
fastapi>=0.115
uvicorn>=0.30
EOF
cat > backend/requirements-dev.txt <<'EOF'
-r requirements.txt
pytest>=8
httpx>=0.27
EOF
cat > backend/pytest.ini <<'EOF'
[pytest]
testpaths = tests
pythonpath = .
addopts = -q
EOF
cat > backend/.env.example <<'EOF'
# Copy to .env (never commit .env). All values optional.
# Directory the agent may touch. Defaults to <repo>/workspace. Must not be / or your home directory.
NEXORA_WORKSPACE_ROOT=
NEXORA_CORS_ORIGINS=http://localhost:3000,http://127.0.0.1:3000
# Programs eligible for command.run (deny-list and per-program rules still apply)
NEXORA_ALLOWED_PROGRAMS=python,python3,pytest,npm,npx,node,git
NEXORA_COMMAND_TIMEOUT_S=300
NEXORA_LOG_LEVEL=INFO
EOF

# =====================================================================
# app/config.py
# =====================================================================
cat > backend/app/config.py <<'EOF'
"""Runtime configuration from environment variables. No secrets are hardcoded or required."""
from __future__ import annotations

import logging
import os
from dataclasses import dataclass
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]  # backend/app/config.py -> repo root
DEFAULT_PROGRAMS = ("python", "python3", "pytest", "npm", "npx", "node", "git")
DEFAULT_ORIGINS = ("http://localhost:3000", "http://127.0.0.1:3000")


def _csv(value: str | None, default: tuple[str, ...]) -> tuple[str, ...]:
    if not value:
        return default
    return tuple(p.strip() for p in value.split(",") if p.strip())


@dataclass(frozen=True)
class Settings:
    workspace_root: Path
    cors_origins: tuple[str, ...] = DEFAULT_ORIGINS
    allowed_programs: frozenset[str] = frozenset(DEFAULT_PROGRAMS)
    command_timeout_s: float = 300.0
    max_output_bytes: int = 100_000
    max_file_bytes: int = 1_000_000
    approval_ttl_s: int = 600
    log_level: str = "INFO"

    @classmethod
    def from_env(cls, env: dict[str, str] | None = None) -> "Settings":
        env = dict(os.environ) if env is None else env
        root = Path(env.get("NEXORA_WORKSPACE_ROOT") or REPO_ROOT / "workspace").expanduser()
        root.mkdir(parents=True, exist_ok=True)
        root = root.resolve()
        # SECURITY: refuse roots that would expose the whole device or the whole home directory.
        if root == Path(root.anchor) or root == Path.home().resolve():
            raise ValueError("NEXORA_WORKSPACE_ROOT must be a dedicated directory (not / or $HOME)")
        return cls(
            workspace_root=root,
            cors_origins=_csv(env.get("NEXORA_CORS_ORIGINS"), DEFAULT_ORIGINS),
            allowed_programs=frozenset(p.lower() for p in _csv(env.get("NEXORA_ALLOWED_PROGRAMS"), DEFAULT_PROGRAMS)),
            command_timeout_s=float(env.get("NEXORA_COMMAND_TIMEOUT_S", 300)),
            log_level=env.get("NEXORA_LOG_LEVEL", "INFO").upper(),
        )


def configure_logging(level: str = "INFO") -> None:
    logging.basicConfig(level=getattr(logging, level, logging.INFO),
                        format="%(asctime)s %(levelname)s %(name)s: %(message)s")
EOF

# =====================================================================
# security/
# =====================================================================
cat > backend/app/security/path_guard.py <<'EOF'
"""Workspace path validation. SECURITY-CRITICAL: every filesystem path goes through PathGuard.

Defenses: absolute/home paths rejected, '..' traversal rejected (final resolved path must be
inside the root), symlinks are resolved before the check so links pointing outside are rejected,
secret-looking files are blocked, and .git is write-protected.
Limitation: a race (TOCTOU) between check and use is possible if another process swaps a path
for a symlink concurrently. The workspace should not be writable by untrusted processes.
"""
from __future__ import annotations

import os
from pathlib import Path


class PathGuardError(Exception):
    """Base class: the path was refused."""


class PathEscapeError(PathGuardError):
    pass


class SecretPathError(PathGuardError):
    pass


SECRET_NAMES = frozenset({"id_rsa", "id_ed25519", "id_ecdsa", ".npmrc", ".netrc", ".pypirc", "credentials"})
SECRET_SUFFIXES = (".pem", ".key", ".p12", ".pfx")
ENV_EXAMPLES = frozenset({".env.example", ".env.sample", ".env.template"})


def is_secret_path(p: Path) -> bool:
    n = p.name.lower()
    if n in SECRET_NAMES:
        return True
    if n.startswith(".env") and n not in ENV_EXAMPLES:
        return True
    return n.endswith(SECRET_SUFFIXES)


class PathGuard:
    def __init__(self, root: Path):
        self.root = Path(root).resolve(strict=True)

    def resolve(self, rel: str, *, for_write: bool = False, allow_secret: bool = False) -> Path:
        """Turn a user-supplied relative path into a safe absolute path inside the root."""
        if not isinstance(rel, str) or "\x00" in rel:
            raise PathGuardError("invalid path")
        rel = rel.strip() or "."
        if rel.startswith(("/", "\\", "~")) or os.path.isabs(rel) or (len(rel) > 1 and rel[1] == ":"):
            raise PathEscapeError(f"absolute paths are not allowed: {rel}")
        resolved = (self.root / rel).resolve(strict=False)  # follows symlinks that exist
        return self._validate(resolved, rel, for_write, allow_secret)

    def check_inside(self, path: Path, *, label: str | None = None, allow_secret: bool = False) -> Path:
        resolved = Path(path).resolve(strict=False)
        return self._validate(resolved, label or path.name, False, allow_secret)

    def _validate(self, resolved: Path, label: str, for_write: bool, allow_secret: bool) -> Path:
        if not resolved.is_relative_to(self.root):
            raise PathEscapeError(f"path escapes the workspace: {label}")
        if not allow_secret and is_secret_path(resolved):
            raise SecretPathError(f"access to secret files is blocked: {label}")
        if for_write and ".git" in resolved.relative_to(self.root).parts:
            raise PathGuardError(f".git is write-protected: {label}")
        return resolved

    def rel(self, p: Path) -> str:
        return p.relative_to(self.root).as_posix()
EOF

cat > backend/app/security/permissions.py <<'EOF'
"""Permission categories, static policy, and the human-approval store.

The agent can REQUEST approval but has no code path that grants it. Approvals are granted only
through the approvals API (a person/frontend), are bound to the exact tool + arguments, expire,
and are single-use.
"""
from __future__ import annotations

import hashlib
import json
import secrets
import threading
import time
from dataclasses import dataclass
from enum import Enum
from typing import Any


class Permission(str, Enum):
    READ = "read"
    WRITE = "write"
    DELETE = "delete"
    EXECUTE = "execute"
    NETWORK = "network"
    DEPLOY = "deploy"
    SECRET_ACCESS = "secret_access"


class Decision(str, Enum):
    ALLOW = "allow"
    REQUIRE_APPROVAL = "require_approval"
    DENY = "deny"


@dataclass(frozen=True)
class Verdict:
    decision: Decision
    reason: str = ""


class PolicyDenied(Exception):
    """An operation was refused by policy."""


class ApprovalError(Exception):
    def __init__(self, message: str, not_found: bool = False):
        super().__init__(message)
        self.not_found = not_found


_STATIC = {
    Permission.READ: Verdict(Decision.ALLOW),
    Permission.WRITE: Verdict(Decision.ALLOW, "allowed inside the workspace (enforced by PathGuard)"),
    Permission.DELETE: Verdict(Decision.REQUIRE_APPROVAL, "Deleting requires approval"),
    # EXECUTE has no blanket allow: only tools that supply their own command-policy assessment run.
    Permission.EXECUTE: Verdict(Decision.DENY, "Execution is only allowed through the command policy"),
    Permission.NETWORK: Verdict(Decision.DENY, "Network access is not available to tools in Engine V1"),
    Permission.DEPLOY: Verdict(Decision.REQUIRE_APPROVAL, "Deployment requires approval"),
    Permission.SECRET_ACCESS: Verdict(Decision.DENY, "Secret access is blocked"),
}


def static_verdict(permission: Permission) -> Verdict:
    return _STATIC[permission]


def args_digest(tool: str, args: dict[str, Any]) -> str:
    blob = json.dumps({"tool": tool, "args": args}, sort_keys=True, default=str)
    return hashlib.sha256(blob.encode()).hexdigest()


@dataclass
class Approval:
    id: str
    tool: str
    digest: str
    reason: str
    summary: dict[str, Any]
    status: str  # pending | approved | denied | used
    created_at: float
    expires_at: float

    def public(self) -> dict[str, Any]:
        expired = time.time() > self.expires_at
        return {"id": self.id, "tool": self.tool, "reason": self.reason, "summary": self.summary,
                "status": "expired" if expired and self.status in ("pending", "approved") else self.status,
                "expires_at": self.expires_at}


class ApprovalStore:
    def __init__(self, ttl_s: int = 600):
        self._ttl = ttl_s
        self._items: dict[str, Approval] = {}
        self._lock = threading.Lock()

    def request(self, tool: str, args: dict[str, Any], reason: str, summary: dict[str, Any] | None = None) -> Approval:
        digest, now = args_digest(tool, args), time.time()
        with self._lock:
            for a in self._items.values():
                if a.digest == digest and a.status == "pending" and a.expires_at > now:
                    return a
            a = Approval("apr_" + secrets.token_hex(6), tool, digest, reason, summary or {}, "pending", now, now + self._ttl)
            self._items[a.id] = a
            if len(self._items) > 500:  # bound memory
                for old in sorted(self._items.values(), key=lambda x: x.created_at)[:100]:
                    del self._items[old.id]
            return a

    def _pending(self, approval_id: str) -> Approval:
        a = self._items.get(approval_id)
        if a is None:
            raise ApprovalError("unknown approval", not_found=True)
        if time.time() > a.expires_at:
            raise ApprovalError("approval expired")
        if a.status != "pending":
            raise ApprovalError(f"approval is already {a.status}")
        return a

    def approve(self, approval_id: str) -> Approval:
        with self._lock:
            a = self._pending(approval_id)
            a.status = "approved"
            return a

    def deny(self, approval_id: str) -> Approval:
        with self._lock:
            a = self._pending(approval_id)
            a.status = "denied"
            return a

    def consume(self, approval_id: str, tool: str, args: dict[str, Any]) -> bool:
        """True only for an approved, unexpired approval for exactly this tool+args. Single use."""
        with self._lock:
            a = self._items.get(approval_id)
            if not a or a.status != "approved" or time.time() > a.expires_at or a.digest != args_digest(tool, args):
                return False
            a.status = "used"
            return True

    def list(self) -> list[dict[str, Any]]:
        with self._lock:
            return [a.public() for a in sorted(self._items.values(), key=lambda x: -x.created_at)[:100]]
EOF

cat > backend/app/security/command_policy.py <<'EOF'
"""Structured command policy. SECURITY-CRITICAL.

Commands are {program, args[]} and are NEVER passed through a shell, so pipes, redirects,
'&&', '$(...)' etc. have no meaning. Policy layers (all must pass):
  1. program must be a bare name (no path), not in ALWAYS_DENIED (wins even if allowlisted),
     and in the configured allowlist;
  2. every path-like argument must stay inside the workspace (no absolute, ~, or '..' escapes);
  3. a per-program rule decides ALLOW / REQUIRE_APPROVAL / DENY by subcommand.
"""
from __future__ import annotations

import re
from pathlib import Path

from .path_guard import PathGuard, PathGuardError
from .permissions import Decision, Verdict

ALLOW = Verdict(Decision.ALLOW)


def deny(reason: str) -> Verdict:
    return Verdict(Decision.DENY, reason)


def approve(reason: str) -> Verdict:
    return Verdict(Decision.REQUIRE_APPROVAL, reason)


ALWAYS_DENIED = frozenset({
    "rm", "rmdir", "shutdown", "reboot", "poweroff", "halt", "mkfs", "dd", "chmod", "chown", "chgrp",
    "sudo", "su", "doas", "sh", "bash", "zsh", "dash", "fish", "ksh", "csh", "eval", "exec", "env", "xargs",
    "curl", "wget", "nc", "ncat", "ssh", "scp", "sftp", "ftp", "telnet", "kill", "killall", "pkill",
    "mount", "umount", "fdisk", "ln", "mv", "cp", "tee", "su-exec", "busybox", "termux-open", "am", "pm",
})
_PROGRAM_RE = re.compile(r"^[A-Za-z0-9._+-]{1,64}$")
MAX_ARGS, MAX_ARG_LEN = 64, 1024
SAFE_NPM_SCRIPTS = frozenset({"build", "lint", "test", "typecheck", "type-check"})
BLOCKED_OPTIONS = frozenset({"-g", "--global", "--userconfig", "--globalconfig"})
NODE_BLOCKED = frozenset({"-e", "--eval", "-p", "--print", "-r", "--require", "--import", "--loader", "-i", "--interactive"})
GIT_READ = frozenset({"status", "diff", "log", "show", "rev-parse", "ls-files"})
GIT_APPROVAL = frozenset({"add", "commit", "checkout", "switch", "restore", "stash", "tag"})
GIT_BRANCH_READ_FLAGS = frozenset({"--show-current", "-a", "-r", "--list", "-v", "-vv"})


def _looks_like_path(v: str) -> bool:
    return "/" in v or v.startswith((".", "~"))


def _check_args(args: list[str], guard: PathGuard, cwd: Path) -> str | None:
    if len(args) > MAX_ARGS:
        return "too many arguments"
    for a in args:
        if not isinstance(a, str) or "\x00" in a or len(a) > MAX_ARG_LEN:
            return "invalid argument"
        if a in BLOCKED_OPTIONS:
            return f"option {a} is not allowed"
        if a.startswith("-"):
            value = a.split("=", 1)[1] if "=" in a else None  # --opt=value: check the value
        else:
            value = a
        if value and _looks_like_path(value):
            if value.startswith(("/", "~")):
                return f"absolute or home paths are not allowed: {value}"
            try:
                guard.check_inside(cwd / value, label=value)
            except PathGuardError as exc:
                return str(exc)
    return None


def _python(a: list[str]) -> Verdict:
    if a in (["--version"], ["-V"]):
        return ALLOW
    if a[:1] == ["-m"] and len(a) >= 2:
        if a[1] in ("pytest", "compileall", "unittest"):
            return ALLOW
        return deny(f"python -m {a[1]} is not allowed")
    if not a:
        return deny("interactive python is not allowed")
    if a[0].startswith("-"):
        return deny(f"python option {a[0]} is not allowed")
    return approve("running a Python script executes workspace code")


def _pytest(a: list[str]) -> Verdict:
    return ALLOW


def _node(a: list[str]) -> Verdict:
    if a in (["--version"], ["-v"]):
        return ALLOW
    if any(x in NODE_BLOCKED for x in a):
        return deny("inline/eval/preload node options are not allowed")
    if a and not a[0].startswith("-"):
        return approve("running a Node script executes workspace code")
    return deny("interactive node is not allowed")


def _npm(a: list[str]) -> Verdict:
    if not a:
        return deny("npm needs a subcommand")
    sub, rest = a[0], a[1:]
    if sub in ("--version", "-v", "test", "t", "ls", "list"):
        return ALLOW
    if sub in ("run", "run-script"):
        script = next((x for x in rest if not x.startswith("-")), None)
        if script in SAFE_NPM_SCRIPTS:
            return ALLOW
        return approve(f"npm script '{script}' runs project-defined code")
    if sub in ("install", "i", "ci", "add", "update", "up", "uninstall", "remove", "rm"):
        return approve("changes dependencies and uses the network")
    return deny(f"npm {sub} is not allowed")


def _npx(a: list[str]) -> Verdict:
    if len(a) >= 2 and a[0] == "--no-install" and a[1] in ("tsc", "eslint", "next"):
        return ALLOW
    return approve("npx may download and execute packages")


def _git(a: list[str]) -> Verdict:
    if a == ["--version"]:
        return ALLOW
    if not a or a[0].startswith("-"):
        return deny("git global options (-c, -C, --git-dir, ...) are not allowed")
    sub, rest = a[0], a[1:]
    if any(x.startswith(("--output", "--upload-pack", "--receive-pack", "--exec")) for x in rest):
        return deny("git option not allowed")
    if sub in GIT_READ:
        return ALLOW
    if sub == "branch":
        return ALLOW if all(x in GIT_BRANCH_READ_FLAGS for x in rest) else approve("git branch modifies the repository")
    if sub in GIT_APPROVAL:
        return approve(f"git {sub} modifies the repository")
    return deny(f"git {sub} is not allowed (network and destructive subcommands are blocked)")


_RULES = {"python": _python, "pytest": _pytest, "node": _node, "npm": _npm, "npx": _npx, "git": _git}
_ALIASES = {"python3": "python"}


def evaluate(program: str, args: list[str], *, allowed: frozenset[str] | set[str], guard: PathGuard, cwd: Path) -> Verdict:
    if not isinstance(program, str) or not _PROGRAM_RE.match(program):
        return deny("program must be a bare executable name (no paths)")
    name = program.lower()
    if name in ALWAYS_DENIED:
        return deny(f"'{program}' is blocked by policy")
    if name not in allowed:
        return deny(f"'{program}' is not in the command allowlist")
    bad = _check_args(list(args), guard, cwd)
    if bad:
        return deny(bad)
    rule = _RULES.get(_ALIASES.get(name, name))
    if rule is None:
        return approve(f"no built-in rule for '{program}'; approval required")
    return rule(list(args))
EOF

# =====================================================================
# services/
# =====================================================================
cat > backend/app/services/process.py <<'EOF'
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
EOF

cat > backend/app/services/activity.py <<'EOF'
"""In-memory activity log: structured events the frontend activity panel can read later."""
from __future__ import annotations

import threading
from collections import deque
from typing import Any


class ActivityLog:
    def __init__(self, maxlen: int = 500):
        self._events: deque[dict[str, Any]] = deque(maxlen=maxlen)
        self._lock = threading.Lock()
        self._seq = 0

    def record(self, event: dict[str, Any]) -> None:
        with self._lock:
            self._seq += 1
            self._events.append({"id": self._seq, **event})

    def recent(self, limit: int = 100) -> list[dict[str, Any]]:
        with self._lock:
            return list(self._events)[-limit:]
EOF

# =====================================================================
# tools/
# =====================================================================
cat > backend/app/tools/base.py <<'EOF'
"""Tool abstractions shared by every tool and by the agent."""
from dataclasses import dataclass
from typing import Any, Callable, Literal

from pydantic import BaseModel, Field

from ..config import Settings
from ..security.path_guard import PathGuard
from ..security.permissions import ApprovalStore, Permission, Verdict


class ToolResult(BaseModel):
    tool: str = ""
    success: bool = False
    status: Literal["success", "error", "denied", "approval_required"] = "error"
    data: dict[str, Any] = Field(default_factory=dict)
    error: str | None = None
    exit_code: int | None = None
    stdout: str = ""
    stderr: str = ""
    duration_ms: int = 0
    timestamp: str = ""
    approval_id: str | None = None


class ToolError(Exception):
    """Expected, user-facing failure (bad input, missing file, ...)."""


def ok(data: dict[str, Any] | None = None) -> ToolResult:
    return ToolResult(success=True, status="success", data=data or {})


@dataclass
class ToolContext:
    settings: Settings
    guard: PathGuard
    approvals: ApprovalStore


@dataclass
class Tool:
    name: str
    description: str
    permission: Permission
    input_model: type[BaseModel]
    output: dict[str, str]  # description of ToolResult.data keys
    handler: Callable[[ToolContext, Any], ToolResult]
    assess: Callable[[ToolContext, Any], Verdict] | None = None  # dynamic policy (e.g. commands)

    def spec(self) -> dict[str, Any]:
        return {"name": self.name, "description": self.description, "permission": self.permission.value,
                "input_schema": self.input_model.model_json_schema(), "output_schema": self.output}
EOF

cat > backend/app/tools/filesystem.py <<'EOF'
"""Filesystem tools. Every path goes through ctx.guard (workspace-confined)."""
import os
from pathlib import Path

from pydantic import BaseModel, Field

from ..security.path_guard import PathGuardError
from ..security.permissions import Permission
from .base import Tool, ToolContext, ToolError, ToolResult, ok

SKIP_DIRS = frozenset({".git", "node_modules", ".venv", ".next", "__pycache__", ".pytest_cache", "dist", "build"})


class PathIn(BaseModel):
    path: str = Field(min_length=1, max_length=1024)


class ListIn(BaseModel):
    path: str = "."
    max_entries: int = Field(500, ge=1, le=2000)


class SearchIn(BaseModel):
    query: str = Field(min_length=1, max_length=200)
    path: str = "."
    content: bool = True
    max_results: int = Field(50, ge=1, le=500)


class WriteIn(BaseModel):
    path: str = Field(min_length=1, max_length=1024)
    content: str = Field(max_length=2_000_000)
    overwrite: bool = False


class EditIn(BaseModel):
    path: str = Field(min_length=1, max_length=1024)
    old: str = Field(min_length=1, max_length=200_000)
    new: str = Field(max_length=200_000)
    replace_all: bool = False


def read_file(ctx: ToolContext, a: PathIn) -> ToolResult:
    p = ctx.guard.resolve(a.path)
    if not p.is_file():
        raise ToolError("file not found")
    size = p.stat().st_size
    if size > ctx.settings.max_file_bytes:
        raise ToolError(f"file too large ({size} bytes)")
    try:
        text = p.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        raise ToolError("file is not valid UTF-8 text")
    return ok({"path": ctx.guard.rel(p), "content": text, "size_bytes": size})


def list_dir(ctx: ToolContext, a: ListIn) -> ToolResult:
    p = ctx.guard.resolve(a.path)
    if not p.is_dir():
        raise ToolError("directory not found")
    entries = []
    for e in sorted(p.iterdir(), key=lambda x: (not x.is_dir(), x.name.lower())):
        if len(entries) >= a.max_entries:
            break
        entries.append({"name": e.name, "type": "dir" if e.is_dir() else "file",
                        "size_bytes": e.stat().st_size if e.is_file() else None})
    return ok({"path": ctx.guard.rel(p), "entries": entries})


def search_files(ctx: ToolContext, a: SearchIn) -> ToolResult:
    base = ctx.guard.resolve(a.path)
    if not base.is_dir():
        raise ToolError("search path is not a directory")
    q = a.query.lower()
    matches: list[dict] = []
    full = False
    for dirpath, dirnames, filenames in os.walk(base):  # followlinks=False
        dirnames[:] = sorted(d for d in dirnames if d not in SKIP_DIRS)
        for fn in sorted(filenames):
            try:
                fp = ctx.guard.check_inside(Path(dirpath) / fn, label=fn)
            except PathGuardError:
                continue  # secret file or symlink pointing outside: skipped silently
            rel = ctx.guard.rel(fp)
            if q in rel.lower():
                matches.append({"path": rel, "line": None, "text": None})
            if a.content and fp.is_file() and fp.stat().st_size <= 512_000:
                try:
                    lines = fp.read_text(encoding="utf-8").splitlines()
                except (UnicodeDecodeError, OSError):
                    lines = []
                for n, line in enumerate(lines, 1):
                    if q in line.lower():
                        matches.append({"path": rel, "line": n, "text": line.strip()[:200]})
                        if len(matches) >= a.max_results:
                            break
            if len(matches) >= a.max_results:
                full = True
                break
        if full:
            break
    return ok({"query": a.query, "matches": matches[: a.max_results], "truncated": full})


def write_file(ctx: ToolContext, a: WriteIn) -> ToolResult:
    if len(a.content.encode()) > ctx.settings.max_file_bytes:
        raise ToolError("content too large")
    p = ctx.guard.resolve(a.path, for_write=True)
    if p == ctx.guard.root or p.is_dir():
        raise ToolError("path is a directory")
    existed = p.exists()
    if existed and not a.overwrite:
        raise ToolError("file exists; use filesystem.edit or set overwrite=true")
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(a.content, encoding="utf-8")
    return ok({"path": ctx.guard.rel(p), "created": not existed, "size_bytes": p.stat().st_size})


def edit_file(ctx: ToolContext, a: EditIn) -> ToolResult:
    p = ctx.guard.resolve(a.path, for_write=True)
    if not p.is_file():
        raise ToolError("file not found")
    try:
        text = p.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        raise ToolError("file is not valid UTF-8 text")
    count = text.count(a.old)
    if count == 0:
        raise ToolError("text to replace was not found")
    if count > 1 and not a.replace_all:
        raise ToolError(f"text occurs {count} times; make it unique or set replace_all=true")
    new_text = text.replace(a.old, a.new) if a.replace_all else text.replace(a.old, a.new, 1)
    if len(new_text.encode()) > ctx.settings.max_file_bytes:
        raise ToolError("result too large")
    p.write_text(new_text, encoding="utf-8")
    return ok({"path": ctx.guard.rel(p), "replacements": count if a.replace_all else 1})


def delete_path(ctx: ToolContext, a: PathIn) -> ToolResult:
    # The registry has already required approval (Permission.DELETE) before this runs.
    p = ctx.guard.resolve(a.path, for_write=True)
    if p == ctx.guard.root:
        raise ToolError("cannot delete the workspace root")
    if not p.exists() and not p.is_symlink():
        raise ToolError("path not found")
    if p.is_dir() and not p.is_symlink():
        if any(p.iterdir()):
            raise ToolError("directory not empty (recursive delete is not supported)")
        p.rmdir()
    else:
        p.unlink()
    return ok({"path": a.path, "deleted": True})


def make_dir(ctx: ToolContext, a: PathIn) -> ToolResult:
    p = ctx.guard.resolve(a.path, for_write=True)
    p.mkdir(parents=True, exist_ok=True)
    return ok({"path": ctx.guard.rel(p)})


TOOLS = [
    Tool("filesystem.read", "Read a UTF-8 text file inside the workspace.", Permission.READ, PathIn,
         {"path": "str", "content": "str", "size_bytes": "int"}, read_file),
    Tool("filesystem.list", "List a directory inside the workspace.", Permission.READ, ListIn,
         {"path": "str", "entries": "list[{name,type,size_bytes}]"}, list_dir),
    Tool("filesystem.search", "Search file names and contents (case-insensitive substring).", Permission.READ, SearchIn,
         {"matches": "list[{path,line,text}]", "truncated": "bool"}, search_files),
    Tool("filesystem.write", "Create a file (fails if it exists unless overwrite=true).", Permission.WRITE, WriteIn,
         {"path": "str", "created": "bool", "size_bytes": "int"}, write_file),
    Tool("filesystem.edit", "Replace exact text in an existing file.", Permission.WRITE, EditIn,
         {"path": "str", "replacements": "int"}, edit_file),
    Tool("filesystem.mkdir", "Create a directory (and parents).", Permission.WRITE, PathIn,
         {"path": "str"}, make_dir),
    Tool("filesystem.delete", "Delete a file or empty directory. REQUIRES APPROVAL.", Permission.DELETE, PathIn,
         {"path": "str", "deleted": "bool"}, delete_path),
]
EOF

cat > backend/app/tools/project.py <<'EOF'
"""Project inspection and type detection."""
import json
from pathlib import Path
from typing import Any

from pydantic import BaseModel, Field

from ..security.path_guard import is_secret_path
from ..security.permissions import Permission
from .base import Tool, ToolContext, ToolError, ToolResult, ok
from .filesystem import SKIP_DIRS


class InspectIn(BaseModel):
    path: str = "."
    max_depth: int = Field(2, ge=0, le=5)
    max_entries: int = Field(200, ge=1, le=1000)


def load_package_json(d: Path) -> dict[str, Any] | None:
    f = d / "package.json"
    try:
        if f.is_file() and f.stat().st_size < 1_000_000:
            data = json.loads(f.read_text(encoding="utf-8"))
            return data if isinstance(data, dict) else None
    except (OSError, ValueError):
        pass
    return None


def detect_types(d: Path) -> list[str]:
    """Detect common project types. Returns ['generic'] if nothing matches."""
    types: list[str] = []
    pkg = load_package_json(d)
    if pkg is not None:
        deps: dict[str, Any] = {}
        for key in ("dependencies", "devDependencies"):
            if isinstance(pkg.get(key), dict):
                deps.update(pkg[key])
        if "next" in deps:
            types.append("nextjs")
        if "react" in deps:
            types.append("react")
        types.append("nodejs")
    py_text = ""
    for name in ("requirements.txt", "pyproject.toml"):
        f = d / name
        if f.is_file():
            py_text += f.read_text(encoding="utf-8", errors="ignore").lower()
    if py_text or (d / "setup.py").is_file():
        if "fastapi" in py_text:
            types.append("fastapi")
        types.append("python")
    return types or ["generic"]


def _tree(base: Path, max_depth: int, max_entries: int) -> list[str]:
    out: list[str] = []

    def walk(d: Path, depth: int) -> None:
        for e in sorted(d.iterdir(), key=lambda x: (not x.is_dir(), x.name.lower())):
            if len(out) >= max_entries:
                return
            if e.name in SKIP_DIRS or is_secret_path(e):
                continue
            rel = e.relative_to(base).as_posix()
            if e.is_symlink():
                out.append(rel + "@")  # shown, never followed
            elif e.is_dir():
                out.append(rel + "/")
                if depth < max_depth:
                    walk(e, depth + 1)
            else:
                out.append(rel)

    walk(base, 0)
    return out


def inspect_project(ctx: ToolContext, a: InspectIn) -> ToolResult:
    d = ctx.guard.resolve(a.path)
    if not d.is_dir():
        raise ToolError("project path is not a directory")
    pkg = load_package_json(d)
    scripts = pkg.get("scripts") if pkg and isinstance(pkg.get("scripts"), dict) else {}
    return ok({"path": ctx.guard.rel(d), "types": detect_types(d), "scripts": scripts,
               "tree": _tree(d, a.max_depth, a.max_entries)})


TOOLS = [
    Tool("project.inspect", "Inspect project structure, detect type (Next.js, React, Node, Python, FastAPI, generic).",
         Permission.READ, InspectIn, {"types": "list[str]", "scripts": "dict", "tree": "list[str]"}, inspect_project),
]
EOF

cat > backend/app/tools/command.py <<'EOF'
"""Controlled command execution. Structured {program, args[]} only; never a shell string."""
from pydantic import BaseModel, Field

from ..security import command_policy
from ..security.path_guard import PathGuardError
from ..security.permissions import Decision, Permission, PolicyDenied, Verdict
from ..services.process import resolve_executable, run_process
from .base import Tool, ToolContext, ToolError, ToolResult


class CommandIn(BaseModel):
    program: str = Field(min_length=1, max_length=64)
    args: list[str] = Field(default_factory=list, max_length=64)
    cwd: str = "."
    timeout_s: float | None = Field(default=None, gt=0, le=3600)


def assess(ctx: ToolContext, a: CommandIn) -> Verdict:
    try:
        cwd = ctx.guard.resolve(a.cwd)
    except PathGuardError as exc:
        return Verdict(Decision.DENY, str(exc))
    return command_policy.evaluate(a.program, a.args, allowed=ctx.settings.allowed_programs, guard=ctx.guard, cwd=cwd)


def run_command(ctx: ToolContext, program: str, args: list[str], cwd: str = ".", timeout_s: float | None = None) -> ToolResult:
    """Runs a command. Re-evaluates the policy (defense in depth). Approval, if the verdict needs
    it, is enforced by the registry before the tool handler is reached."""
    cwd_path = ctx.guard.resolve(cwd)
    if not cwd_path.is_dir():
        raise ToolError("cwd is not a directory")
    verdict = command_policy.evaluate(program, args, allowed=ctx.settings.allowed_programs, guard=ctx.guard, cwd=cwd_path)
    if verdict.decision is Decision.DENY:
        raise PolicyDenied(verdict.reason)
    exe = resolve_executable(program)
    if exe is None:
        raise ToolError(f"program not found: {program}")
    limit = min(timeout_s or ctx.settings.command_timeout_s, ctx.settings.command_timeout_s)
    out = run_process([exe, *args], cwd_path, limit, ctx.settings.max_output_bytes)
    success = out.exit_code == 0 and not out.timed_out
    error = None if success else (f"timed out after {limit:g}s" if out.timed_out else
                                  f"exit code {out.exit_code}" if out.exit_code is not None else out.stderr)
    return ToolResult(success=success, status="success" if success else "error", error=error,
                      exit_code=out.exit_code, stdout=out.stdout, stderr=out.stderr, duration_ms=out.duration_ms,
                      data={"program": program, "args": args, "cwd": ctx.guard.rel(cwd_path),
                            "timed_out": out.timed_out, "truncated": out.truncated})


def handler(ctx: ToolContext, a: CommandIn) -> ToolResult:
    return run_command(ctx, a.program, a.args, a.cwd, a.timeout_s)


TOOLS = [
    Tool("command.run", "Run an allowlisted program with structured args inside the workspace (no shell).",
         Permission.EXECUTE, CommandIn,
         {"exit_code": "int|null", "stdout": "str", "stderr": "str", "duration_ms": "int", "timed_out": "bool"},
         handler, assess),
]
EOF

cat > backend/app/tools/testrunner.py <<'EOF'
"""Verification runner: detect project -> choose commands -> run via command policy -> collect output."""
from pathlib import Path
from typing import Literal

from pydantic import BaseModel

from ..security.permissions import Decision, Permission, PolicyDenied, Verdict
from .base import Tool, ToolContext, ToolError, ToolResult
from .command import run_command
from .project import detect_types, load_package_json

Check = Literal["test", "lint", "build"]


class VerifyIn(BaseModel):
    path: str = "."
    checks: list[Check] | None = None


def _has_pytest_tests(d: Path) -> bool:
    if (d / "tests").is_dir() or (d / "pytest.ini").is_file():
        return True
    return any(d.glob("test_*.py")) or any(d.glob("*_test.py"))


def select_commands(d: Path, requested: list[str] | None):
    cmds: list[tuple[str, str, list[str]]] = []
    skipped: list[dict] = []
    pkg = load_package_json(d)
    if pkg is not None:
        scripts = pkg.get("scripts") if isinstance(pkg.get("scripts"), dict) else {}
        for check in requested or ["test", "lint", "build"]:
            if check not in scripts:
                skipped.append({"check": check, "reason": f"no '{check}' script in package.json"})
            else:
                cmds.append((check, "npm", ["test"] if check == "test" else ["run", check]))
    if _has_pytest_tests(d) and (requested is None or "test" in requested) and not any(c[0] == "test" for c in cmds):
        cmds.append(("test", "python", ["-m", "pytest", "-q"]))
    return cmds, skipped


def run_verification(ctx: ToolContext, a: VerifyIn) -> ToolResult:
    d = ctx.guard.resolve(a.path)
    if not d.is_dir():
        raise ToolError("project path is not a directory")
    cmds, skipped = select_commands(d, list(a.checks) if a.checks else None)
    rel = ctx.guard.rel(d)
    results = []
    for check, program, args in cmds:
        try:
            r = run_command(ctx, program, args, cwd=rel)
        except (PolicyDenied, ToolError) as exc:
            results.append({"check": check, "command": [program, *args], "passed": False, "exit_code": None,
                            "duration_ms": 0, "stdout_tail": "", "stderr_tail": str(exc)})
            continue
        results.append({"check": check, "command": [program, *args], "passed": r.success, "exit_code": r.exit_code,
                        "duration_ms": r.duration_ms, "stdout_tail": r.stdout[-2000:], "stderr_tail": r.stderr[-2000:]})
    data = {"path": rel, "project_types": detect_types(d), "results": results, "skipped": skipped,
            "passed": all(x["passed"] for x in results) if results else None}
    if not results:
        return ToolResult(status="error", success=False, error="no verification commands found for this project", data=data)
    ok_all = bool(data["passed"])
    return ToolResult(success=ok_all, status="success" if ok_all else "error",
                      error=None if ok_all else "one or more checks failed", data=data)


TOOLS = [
    Tool("test.run", "Detect the project and run its available test/lint/build checks through the command policy.",
         Permission.EXECUTE, VerifyIn, {"results": "list[check results]", "skipped": "list", "passed": "bool|null"},
         run_verification, lambda ctx, a: Verdict(Decision.ALLOW, "commands are individually policy-checked")),
]
EOF

cat > backend/app/tools/registry.py <<'EOF'
"""Tool registry: the ONLY way the agent and the API invoke tools.

Order of operations for every call: validate input -> decide (policy) -> approval gate ->
handler -> structured result -> activity event. Handlers are never reached on DENY, or on
REQUIRE_APPROVAL without a matching approved approval.
"""
import logging
import time
from datetime import datetime, timezone
from typing import Any

from pydantic import ValidationError

from ..security.path_guard import PathGuardError
from ..security.permissions import Decision, PolicyDenied, Verdict, static_verdict
from ..services.activity import ActivityLog
from . import command, filesystem, project, testrunner
from .base import Tool, ToolContext, ToolError, ToolResult

log = logging.getLogger("nexora.tools")
SUMMARY_KEYS = ("path", "program", "args", "query", "cwd", "checks")  # never log file contents


def _summary(args: dict[str, Any]) -> dict[str, Any]:
    return {k: args[k] for k in SUMMARY_KEYS if k in args}


class ToolRegistry:
    def __init__(self, ctx: ToolContext, activity: ActivityLog):
        self.ctx = ctx
        self.activity = activity
        self._tools: dict[str, Tool] = {}

    def register(self, tool: Tool) -> None:
        self._tools[tool.name] = tool

    def specs(self) -> list[dict[str, Any]]:
        return [t.spec() for t in self._tools.values()]

    def _verdict(self, tool: Tool, parsed: Any) -> Verdict:
        return tool.assess(self.ctx, parsed) if tool.assess else static_verdict(tool.permission)

    def execute(self, name: str, arguments: dict[str, Any] | None, approval_id: str | None = None) -> ToolResult:
        t0 = time.perf_counter()
        tool = self._tools.get(name)
        if tool is None:
            return self._finish(ToolResult(status="error", error=f"unknown tool: {name}"), name, None, t0, {})
        try:
            parsed = tool.input_model.model_validate(arguments or {})
        except ValidationError as exc:
            msg = "; ".join(f"{'.'.join(map(str, e['loc']))}: {e['msg']}" for e in exc.errors()[:5])
            return self._finish(ToolResult(status="error", error="invalid arguments: " + msg), name, tool, t0, {})
        args = parsed.model_dump(mode="json")
        try:
            verdict = self._verdict(tool, parsed)
            if verdict.decision is Decision.DENY:
                result = ToolResult(status="denied", error=verdict.reason)
            elif verdict.decision is Decision.REQUIRE_APPROVAL and not (
                    approval_id and self.ctx.approvals.consume(approval_id, name, args)):
                appr = self.ctx.approvals.request(name, args, verdict.reason, _summary(args))
                result = ToolResult(status="approval_required", error=verdict.reason, approval_id=appr.id)
            else:
                result = tool.handler(self.ctx, parsed)
        except (PathGuardError, PolicyDenied) as exc:
            result = ToolResult(status="denied", error=str(exc))
        except ToolError as exc:
            result = ToolResult(status="error", error=str(exc))
        except OSError as exc:
            result = ToolResult(status="error", error=f"{type(exc).__name__}: {exc.strerror or 'os error'}")
        except Exception:  # never leak internals to the caller
            log.exception("tool %s crashed", name)
            result = ToolResult(status="error", error="internal tool error")
        return self._finish(result, name, tool, t0, args)

    def _finish(self, result: ToolResult, name: str, tool: Tool | None, t0: float, args: dict[str, Any]) -> ToolResult:
        result.tool = name
        result.timestamp = datetime.now(timezone.utc).isoformat()
        if not result.duration_ms:
            result.duration_ms = int((time.perf_counter() - t0) * 1000)
        if result.status != "success":
            result.success = False
        self.activity.record({"tool": name, "status": result.status, "timestamp": result.timestamp,
                              "duration_ms": result.duration_ms,
                              "permission": tool.permission.value if tool else None, "summary": _summary(args)})
        level = logging.WARNING if result.status in ("denied", "approval_required") else logging.INFO
        log.log(level, "tool=%s status=%s duration_ms=%d", name, result.status, result.duration_ms)
        return result


def build_registry(ctx: ToolContext, activity: ActivityLog) -> ToolRegistry:
    reg = ToolRegistry(ctx, activity)
    for module in (filesystem, project, command, testrunner):
        for tool in module.TOOLS:
            reg.register(tool)
    return reg
EOF

# =====================================================================
# agent/
# =====================================================================
cat > backend/app/agent/models.py <<'EOF'
from enum import Enum
from typing import Any, Literal

from pydantic import BaseModel, Field

from ..tools.base import ToolResult


class AgentStatus(str, Enum):
    idle = "idle"
    planning = "planning"
    executing = "executing"
    observing = "observing"
    verifying = "verifying"
    waiting_for_approval = "waiting_for_approval"
    completed = "completed"
    failed = "failed"


class StepStatus(str, Enum):
    pending = "pending"
    running = "running"
    completed = "completed"
    skipped = "skipped"
    failed = "failed"
    waiting_for_approval = "waiting_for_approval"


class ToolCall(BaseModel):
    tool: str
    arguments: dict[str, Any] = Field(default_factory=dict)
    result: ToolResult | None = None


class AgentRequest(BaseModel):
    request: str = Field(min_length=1, max_length=4000)
    project_path: str = "."
    verify: bool = True


class AgentStep(BaseModel):
    index: int
    id: str
    title: str
    description: str = ""
    kind: Literal["tool", "analysis", "unsupported"]
    tool_call: ToolCall | None = None
    status: StepStatus = StepStatus.pending
    note: str = ""


class AgentPlan(BaseModel):
    request: str
    project_types: list[str]
    planner: str = "deterministic"
    steps: list[AgentStep]
    notes: list[str] = Field(default_factory=list)


class VerificationResult(BaseModel):
    passed: bool | None  # None = nothing could be verified
    checks: list[dict[str, Any]] = Field(default_factory=list)
    summary: str = ""


class Observation(BaseModel):
    step_index: int
    tool: str | None
    success: bool
    summary: str


class AgentState(BaseModel):
    run_id: str
    project_root: str
    user_request: str
    status: AgentStatus = AgentStatus.idle
    current_plan: AgentPlan | None = None
    current_step: int | None = None
    completed_steps: list[int] = Field(default_factory=list)
    tool_calls: list[ToolCall] = Field(default_factory=list)
    observations: list[Observation] = Field(default_factory=list)
    errors: list[str] = Field(default_factory=list)
    verification_results: list[VerificationResult] = Field(default_factory=list)
    pending_approval: dict[str, Any] | None = None
    summary: str = ""
    created_at: str
    updated_at: str
EOF

cat > backend/app/agent/provider.py <<'EOF'
"""Model provider interface. FreeLLMAPI will be added later as another ModelProvider
implementation (server-side only). Nothing here calls any external service."""
from abc import ABC, abstractmethod


class ModelProvider(ABC):
    name: str = "base"

    @abstractmethod
    def generate(self, prompt: str, *, system: str | None = None, max_tokens: int = 1024) -> str:
        """Return model text for a prompt."""


class MockProvider(ModelProvider):
    """Local placeholder. It does no reasoning; it only reports that no model is connected."""

    name = "mock"

    def generate(self, prompt: str, *, system: str | None = None, max_tokens: int = 1024) -> str:
        return f"[mock provider] no language model is connected (received {len(prompt)} characters)."
EOF

cat > backend/app/agent/planner.py <<'EOF'
"""Deterministic planner. It is rule-based, NOT an LLM. A future LLMPlanner can subclass
Planner and use ModelProvider.generate() to produce the same AgentPlan structure."""
import re

from .models import AgentPlan, AgentRequest, AgentStep, ToolCall
from .provider import ModelProvider

STOP = {"create", "build", "make", "add", "the", "for", "with", "and", "that", "this", "please", "new",
        "app", "application", "project", "using", "use", "from", "into", "want", "need", "write"}


def keywords(text: str) -> list[str]:
    words = re.findall(r"[A-Za-z][A-Za-z0-9_-]{3,}", text.lower())
    return [w for w in words if w not in STOP][:1]


class Planner:
    def __init__(self, provider: ModelProvider):
        self.provider = provider  # unused by the deterministic planner; kept for the LLM upgrade path

    def plan(self, req: AgentRequest, project_types: list[str]) -> AgentPlan:
        raise NotImplementedError


class DeterministicPlanner(Planner):
    def plan(self, req: AgentRequest, project_types: list[str]) -> AgentPlan:
        p = req.project_path
        kw = keywords(req.request)
        explore = (ToolCall(tool="filesystem.search", arguments={"query": kw[0], "path": p, "max_results": 20})
                   if kw else ToolCall(tool="filesystem.list", arguments={"path": p}))
        verify = req.verify
        rows = [
            ("inspect", "Inspect project", "Read structure and scripts.", "tool", ToolCall(tool="project.inspect", arguments={"path": p}), ""),
            ("identify", "Identify framework", "Derive project type from the inspection.", "analysis", None, ""),
            ("explore", "Inspect relevant files", "Look for files related to the request.", "tool", explore, ""),
            ("plan_changes", "Plan changes", "Decide which files to create or edit.", "unsupported", None,
             "Needs a model provider; the deterministic planner cannot design changes."),
            ("apply", "Apply changes", "Create or edit files via filesystem tools.", "unsupported", None,
             "Code generation is unavailable until a model provider is connected."),
            ("verify", "Run verification", "Run the project's test/lint/build checks.",
             "tool" if verify else "unsupported", ToolCall(tool="test.run", arguments={"path": p}) if verify else None,
             "" if verify else "Verification disabled for this request."),
            ("report", "Report result", "Summarise what happened.", "analysis", None, ""),
        ]
        steps = [AgentStep(index=i, id=r[0], title=r[1], description=r[2], kind=r[3], tool_call=r[4], note=r[5])
                 for i, r in enumerate(rows)]
        return AgentPlan(request=req.request, project_types=project_types, steps=steps, notes=[
            "Engine V1: planning is rule-based. Fixing errors and checkpoints are not implemented yet."])
EOF

cat > backend/app/agent/observer.py <<'EOF'
from ..tools.base import ToolResult
from .models import AgentStep, Observation


def observe(step: AgentStep, result: ToolResult) -> Observation:
    tool = step.tool_call.tool if step.tool_call else None
    if result.status == "success":
        summary = f"{tool} succeeded in {result.duration_ms} ms"
    else:
        summary = f"{tool} {result.status}: {(result.error or 'no details')[:200]}"
    return Observation(step_index=step.index, tool=tool, success=result.success, summary=summary)
EOF

cat > backend/app/agent/verifier.py <<'EOF'
from ..tools.base import ToolResult
from .models import VerificationResult


class Verifier:
    def interpret(self, result: ToolResult) -> VerificationResult:
        rows = result.data.get("results", []) if result.data else []
        checks = [{"check": r["check"], "passed": r["passed"], "exit_code": r["exit_code"]} for r in rows]
        if not checks:
            return VerificationResult(passed=None, checks=[], summary=result.error or "No verification commands were available.")
        failed = [c["check"] for c in checks if not c["passed"]]
        return VerificationResult(passed=not failed, checks=checks,
                                  summary="All checks passed." if not failed else "Failed: " + ", ".join(failed))
EOF

cat > backend/app/agent/executor.py <<'EOF'
from ..tools.base import ToolResult
from ..tools.registry import ToolRegistry
from .models import AgentState, AgentStep


class StepExecutor:
    """Runs a step's tool call through the registry (the only path to tools)."""

    def __init__(self, registry: ToolRegistry):
        self.registry = registry

    def run(self, state: AgentState, step: AgentStep, approval_id: str | None = None) -> ToolResult:
        call = step.tool_call.model_copy(deep=True)
        state.tool_calls.append(call)
        call.result = self.registry.execute(call.tool, call.arguments, approval_id)
        return call.result
EOF

cat > backend/app/agent/state.py <<'EOF'
"""In-memory run store (bounded). Shaped so a persistence layer can replace it later."""
import threading
import uuid
from collections import OrderedDict
from datetime import datetime, timezone

from .models import AgentPlan, AgentRequest, AgentState, AgentStatus


def _now() -> str:
    return datetime.now(timezone.utc).isoformat()


class RunStore:
    def __init__(self, max_runs: int = 100):
        self._runs: OrderedDict[str, AgentState] = OrderedDict()
        self._lock = threading.Lock()
        self._max = max_runs

    def create(self, req: AgentRequest, plan: AgentPlan) -> AgentState:
        now = _now()
        state = AgentState(run_id=uuid.uuid4().hex[:12], project_root=req.project_path, user_request=req.request,
                           status=AgentStatus.planning, current_plan=plan, created_at=now, updated_at=now)
        self.save(state)
        return state

    def save(self, state: AgentState) -> None:
        state.updated_at = _now()
        with self._lock:
            self._runs[state.run_id] = state
            while len(self._runs) > self._max:
                self._runs.popitem(last=False)

    def get(self, run_id: str) -> AgentState | None:
        with self._lock:
            return self._runs.get(run_id)
EOF

cat > backend/app/agent/agent.py <<'EOF'
"""NEXORA agent core: plan -> execute -> observe -> verify -> result.

Engine V1 honesty: the agent can inspect, search and run verification through tools. It does NOT
generate code, fix errors, create checkpoints or call any language model yet. Those steps are
reported as skipped, never faked.
"""
import logging

from ..errors import NotFoundError
from ..security.path_guard import PathGuard
from ..tools.project import detect_types
from ..tools.registry import ToolRegistry
from .executor import StepExecutor
from .models import AgentPlan, AgentRequest, AgentState, AgentStatus, AgentStep, StepStatus
from .observer import observe
from .planner import DeterministicPlanner
from .provider import ModelProvider
from .state import RunStore
from .verifier import Verifier

log = logging.getLogger("nexora.agent")


class Agent:
    def __init__(self, registry: ToolRegistry, guard: PathGuard, provider: ModelProvider, store: RunStore):
        self.registry, self.guard, self.provider, self.store = registry, guard, provider, store
        self.planner = DeterministicPlanner(provider)
        self.executor = StepExecutor(registry)
        self.verifier = Verifier()

    def plan(self, req: AgentRequest) -> AgentPlan:
        base = self.guard.resolve(req.project_path)
        if not base.is_dir():
            raise NotFoundError("project_path is not a directory")
        return self.planner.plan(req, detect_types(base))

    def run(self, req: AgentRequest) -> AgentState:
        state = self.store.create(req, self.plan(req))
        return self._execute(state, 0, None)

    def resume(self, run_id: str, approval_id: str) -> AgentState:
        state = self.store.get(run_id)
        if state is None:
            raise NotFoundError("unknown run")
        if state.status is not AgentStatus.waiting_for_approval or not state.pending_approval:
            raise NotFoundError("run is not waiting for approval")
        return self._execute(state, int(state.pending_approval["step"]), approval_id)

    # ---- internals -------------------------------------------------
    def _execute(self, state: AgentState, start: int, approval_id: str | None) -> AgentState:
        state.status, state.pending_approval = AgentStatus.executing, None
        for step in state.current_plan.steps[start:]:
            state.current_step = step.index
            if step.kind == "unsupported":
                step.status = StepStatus.skipped
                continue
            if step.kind == "analysis":
                if step.id == "identify":
                    step.note = "Detected project type(s): " + ", ".join(state.current_plan.project_types)
                self._done(state, step)
                continue
            is_verify = step.tool_call.tool == "test.run"
            state.status = AgentStatus.verifying if is_verify else AgentStatus.executing
            step.status = StepStatus.running
            result = self.executor.run(state, step, approval_id if step.index == start else None)
            state.status = AgentStatus.observing
            state.observations.append(observe(step, result))
            if result.status == "approval_required":
                step.status = StepStatus.waiting_for_approval
                state.status = AgentStatus.waiting_for_approval
                state.pending_approval = {"approval_id": result.approval_id, "step": step.index,
                                          "tool": step.tool_call.tool, "reason": result.error}
                self.store.save(state)
                return state
            if is_verify:
                v = self.verifier.interpret(result)
                state.verification_results.append(v)
                if v.passed is None:
                    step.status, step.note = StepStatus.skipped, v.summary
                    continue
                if not v.passed:
                    return self._fail(state, step, f"Verification failed ({v.summary}). Automatic fixing is not implemented in Engine V1.")
                self._done(state, step)
            elif result.success:
                self._done(state, step)
            else:
                return self._fail(state, step, f"{step.title}: {result.error}")
        return self._finish(state, AgentStatus.completed)

    def _done(self, state: AgentState, step: AgentStep) -> None:
        step.status = StepStatus.completed
        state.completed_steps.append(step.index)

    def _fail(self, state: AgentState, step: AgentStep, message: str) -> AgentState:
        step.status = StepStatus.failed
        state.errors.append(message)
        return self._finish(state, AgentStatus.failed)

    def _finish(self, state: AgentState, status: AgentStatus) -> AgentState:
        steps = state.current_plan.steps
        skipped = [s.title for s in steps if s.status is StepStatus.skipped]
        state.status = status
        state.summary = (f"{len(state.completed_steps)}/{len(steps)} steps completed. Skipped: {', '.join(skipped) or 'none'}. "
                         "Engine V1 does not generate code, fix errors or create checkpoints; the agent made no file edits.")
        self.store.save(state)
        log.info("run=%s status=%s", state.run_id, status.value)
        return state
EOF

# =====================================================================
# errors, container, schemas, routes, main
# =====================================================================
cat > backend/app/errors.py <<'EOF'
"""Structured error handling: every error body is {"error": {"code", "message"}}."""
import logging

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse

from .security.path_guard import PathGuardError

log = logging.getLogger("nexora.errors")


class NexoraError(Exception):
    status_code = 400
    code = "bad_request"

    def __init__(self, message: str):
        super().__init__(message)
        self.message = message


class NotFoundError(NexoraError):
    status_code = 404
    code = "not_found"


class ConflictError(NexoraError):
    status_code = 409
    code = "conflict"


def _body(code: str, message: str) -> dict:
    return {"error": {"code": code, "message": message}}


def register_error_handlers(app: FastAPI) -> None:
    @app.exception_handler(NexoraError)
    async def _nexora(request: Request, exc: NexoraError):
        return JSONResponse(status_code=exc.status_code, content=_body(exc.code, exc.message))

    @app.exception_handler(PathGuardError)
    async def _path(request: Request, exc: PathGuardError):
        return JSONResponse(status_code=403, content=_body("path_denied", str(exc)))

    @app.exception_handler(Exception)
    async def _unhandled(request: Request, exc: Exception):
        log.exception("unhandled error on %s", request.url.path)
        return JSONResponse(status_code=500, content=_body("internal_error", "Internal server error"))
EOF

cat > backend/app/services/container.py <<'EOF'
"""Wires settings, guard, approvals, registry and agent together (one place, easy to test)."""
from dataclasses import dataclass

from ..agent.agent import Agent
from ..agent.provider import MockProvider, ModelProvider
from ..agent.state import RunStore
from ..config import Settings, configure_logging
from ..security.path_guard import PathGuard
from ..security.permissions import ApprovalStore
from ..tools.base import ToolContext
from ..tools.registry import ToolRegistry, build_registry
from .activity import ActivityLog


@dataclass
class Container:
    settings: Settings
    guard: PathGuard
    approvals: ApprovalStore
    activity: ActivityLog
    registry: ToolRegistry
    provider: ModelProvider
    store: RunStore
    agent: Agent

    @classmethod
    def build(cls, settings: Settings) -> "Container":
        guard = PathGuard(settings.workspace_root)
        approvals = ApprovalStore(settings.approval_ttl_s)
        activity = ActivityLog()
        registry = build_registry(ToolContext(settings, guard, approvals), activity)
        provider, store = MockProvider(), RunStore()
        return cls(settings, guard, approvals, activity, registry, provider, store, Agent(registry, guard, provider, store))

    @classmethod
    def from_env(cls) -> "Container":
        settings = Settings.from_env()
        configure_logging(settings.log_level)
        return cls.build(settings)
EOF

cat > backend/app/schemas.py <<'EOF'
from typing import Any

from pydantic import BaseModel, Field


class PathRequest(BaseModel):
    path: str = Field(min_length=1, max_length=1024)


class WriteRequest(BaseModel):
    path: str = Field(min_length=1, max_length=1024)
    content: str
    overwrite: bool = False


class SearchRequest(BaseModel):
    query: str = Field(min_length=1, max_length=200)
    path: str = "."
    max_results: int = Field(50, ge=1, le=500)


class ToolExecuteRequest(BaseModel):
    tool: str
    arguments: dict[str, Any] = Field(default_factory=dict)
    approval_id: str | None = None


class ResumeRequest(BaseModel):
    approval_id: str
EOF

cat > backend/app/routes/deps.py <<'EOF'
from fastapi import Request
from fastapi.responses import JSONResponse

from ..services.container import Container
from ..tools.base import ToolResult

# HTTP mapping: denied -> 403, approval_required -> 428 (frontend shows "Approval required"),
# tool error -> 400, but a command that ran and exited non-zero is a normal 200 with exit_code.
_STATUS = {"success": 200, "error": 400, "denied": 403, "approval_required": 428}


def get_container(request: Request) -> Container:
    return request.app.state.container


def respond(result: ToolResult) -> JSONResponse:
    code = _STATUS[result.status]
    if result.status == "error" and result.exit_code is not None:
        code = 200
    return JSONResponse(status_code=code, content=result.model_dump(mode="json"))
EOF

cat > backend/app/routes/project.py <<'EOF'
from fastapi import APIRouter, Depends

from ..schemas import PathRequest, SearchRequest, WriteRequest
from ..services.container import Container
from .deps import get_container, respond

router = APIRouter()


@router.get("/inspect")
def inspect(path: str = ".", max_depth: int = 2, c: Container = Depends(get_container)):
    return respond(c.registry.execute("project.inspect", {"path": path, "max_depth": max_depth}))


@router.post("/read")
def read(body: PathRequest, c: Container = Depends(get_container)):
    return respond(c.registry.execute("filesystem.read", body.model_dump()))


@router.post("/write")
def write(body: WriteRequest, c: Container = Depends(get_container)):
    return respond(c.registry.execute("filesystem.write", body.model_dump()))


@router.post("/search")
def search(body: SearchRequest, c: Container = Depends(get_container)):
    return respond(c.registry.execute("filesystem.search", body.model_dump()))
EOF

cat > backend/app/routes/tools.py <<'EOF'
from fastapi import APIRouter, Depends

from ..schemas import ToolExecuteRequest
from ..services.container import Container
from .deps import get_container, respond

router = APIRouter()


@router.get("/tools")
def list_tools(c: Container = Depends(get_container)):
    return {"tools": c.registry.specs()}


@router.post("/tools/execute")
def execute(body: ToolExecuteRequest, c: Container = Depends(get_container)):
    # Goes through the registry: input validation, permission policy, approval gate, command policy.
    return respond(c.registry.execute(body.tool, body.arguments, body.approval_id))


@router.get("/activity")
def activity(limit: int = 100, c: Container = Depends(get_container)):
    return {"events": c.activity.recent(max(1, min(limit, 500)))}
EOF

cat > backend/app/routes/approvals.py <<'EOF'
from fastapi import APIRouter, Depends

from ..errors import ConflictError, NotFoundError
from ..security.permissions import ApprovalError
from ..services.container import Container
from .deps import get_container

router = APIRouter()


@router.get("")
def list_approvals(c: Container = Depends(get_container)):
    return {"approvals": c.approvals.list()}


def _decide(c: Container, approval_id: str, approve: bool) -> dict:
    try:
        a = c.approvals.approve(approval_id) if approve else c.approvals.deny(approval_id)
    except ApprovalError as exc:
        raise (NotFoundError if exc.not_found else ConflictError)(str(exc))
    return a.public()


# NOTE: these endpoints are the human decision point. The agent has no code path that calls them.
# Engine V1 has no authentication: keep the server bound to 127.0.0.1.
@router.post("/{approval_id}/approve")
def approve(approval_id: str, c: Container = Depends(get_container)):
    return _decide(c, approval_id, True)


@router.post("/{approval_id}/deny")
def deny(approval_id: str, c: Container = Depends(get_container)):
    return _decide(c, approval_id, False)
EOF

cat > backend/app/routes/agent.py <<'EOF'
from fastapi import APIRouter, Depends

from ..agent.models import AgentPlan, AgentRequest, AgentState
from ..errors import NotFoundError
from ..schemas import ResumeRequest
from ..services.container import Container
from .deps import get_container

router = APIRouter()


@router.post("/plan")
def plan(body: AgentRequest, c: Container = Depends(get_container)) -> AgentPlan:
    return c.agent.plan(body)


@router.post("/run")
def run(body: AgentRequest, c: Container = Depends(get_container)) -> AgentState:
    return c.agent.run(body)


@router.get("/runs/{run_id}")
def get_run(run_id: str, c: Container = Depends(get_container)) -> AgentState:
    state = c.store.get(run_id)
    if state is None:
        raise NotFoundError("unknown run")
    return state


@router.post("/runs/{run_id}/resume")
def resume(run_id: str, body: ResumeRequest, c: Container = Depends(get_container)) -> AgentState:
    return c.agent.resume(run_id, body.approval_id)
EOF

cat > backend/app/main.py <<'EOF'
"""NEXORA Engine entrypoint. Run with:  uvicorn app.main:create_app --factory --host 127.0.0.1 --port 8000"""
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from . import __version__
from .errors import register_error_handlers
from .routes import agent, approvals, project, tools
from .services.container import Container


def create_app(container: Container | None = None) -> FastAPI:
    container = container or Container.from_env()
    app = FastAPI(title="NEXORA Engine", version=__version__)
    app.state.container = container
    app.add_middleware(CORSMiddleware, allow_origins=list(container.settings.cors_origins),
                       allow_methods=["GET", "POST"], allow_headers=["Content-Type"])
    register_error_handlers(app)

    @app.get("/health")
    def health() -> dict:
        return {"status": "ok", "service": "nexora-engine", "version": __version__}

    app.include_router(project.router, prefix="/api/v1/project")
    app.include_router(agent.router, prefix="/api/v1/agent")
    app.include_router(approvals.router, prefix="/api/v1/approvals")
    app.include_router(tools.router, prefix="/api/v1")
    return app
EOF

# =====================================================================
# tests
# =====================================================================
cat > backend/tests/conftest.py <<'EOF'
import pytest
from fastapi.testclient import TestClient

from app.config import DEFAULT_PROGRAMS, Settings
from app.main import create_app
from app.services.container import Container


@pytest.fixture
def settings(tmp_path):
    ws = tmp_path / "ws"
    ws.mkdir()
    return Settings(workspace_root=ws.resolve(), allowed_programs=frozenset(DEFAULT_PROGRAMS),
                    command_timeout_s=2.0, max_output_bytes=20_000, max_file_bytes=200_000,
                    approval_ttl_s=60, log_level="WARNING")


@pytest.fixture
def container(settings):
    return Container.build(settings)


@pytest.fixture
def client(container):
    return TestClient(create_app(container))


@pytest.fixture
def ws(settings):
    return settings.workspace_root
EOF

cat > backend/tests/test_security.py <<'EOF'
"""Pure-stdlib security tests (no FastAPI needed)."""
import os
import sys
import time

from app.config import DEFAULT_PROGRAMS
from app.security.command_policy import evaluate
from app.security.path_guard import PathEscapeError, PathGuard, PathGuardError, SecretPathError
from app.security.permissions import ApprovalError, ApprovalStore, Decision
from app.services.process import run_process, safe_env

ALLOWED = frozenset(DEFAULT_PROGRAMS) | {"rm", "sudo", "curl", "sh", "bash", "dd", "chmod", "shutdown", "reboot", "mkfs"}


def _ev(tmp_path, program, *args):
    guard = PathGuard(tmp_path)
    return evaluate(program, list(args), allowed=ALLOWED, guard=guard, cwd=guard.root)


def _raises(exc, fn, *a, **k):
    try:
        fn(*a, **k)
    except exc:
        return True
    return False


def test_path_traversal_rejected(tmp_path):
    g = PathGuard(tmp_path)
    for bad in ("../../etc/passwd", "../x", "a/../../x", "a/b/../../../x"):
        assert _raises(PathEscapeError, g.resolve, bad), bad


def test_absolute_and_home_paths_rejected(tmp_path):
    g = PathGuard(tmp_path)
    for bad in ("/etc/passwd", "~/x", "C:\\x"):
        assert _raises(PathEscapeError, g.resolve, bad), bad
    assert _raises(PathGuardError, g.resolve, "a\x00b")


def test_workspace_restriction_allows_inside(tmp_path):
    g = PathGuard(tmp_path)
    p = g.resolve("src/deep/file.txt")
    assert p.is_relative_to(g.root) and g.rel(p) == "src/deep/file.txt"
    assert g.resolve("a/../b.txt") == g.root / "b.txt"  # stays inside after normalisation
    assert g.resolve("") == g.root


def test_symlink_escape_rejected(tmp_path):
    outside = tmp_path / "outside"
    outside.mkdir()
    (outside / "secret.txt").write_text("x")
    root = tmp_path / "ws"
    root.mkdir()
    try:
        os.symlink(outside, root / "link")
    except (OSError, NotImplementedError):
        return  # platform without symlinks
    assert _raises(PathEscapeError, PathGuard(root).resolve, "link/secret.txt")


def test_secret_files_and_git_protected(tmp_path):
    g = PathGuard(tmp_path)
    assert _raises(SecretPathError, g.resolve, ".env")
    assert _raises(SecretPathError, g.resolve, "keys/server.pem")
    assert g.resolve(".env.example")
    assert _raises(PathGuardError, g.resolve, ".git/config", for_write=True)


def test_allowlisted_commands(tmp_path):
    assert _ev(tmp_path, "python", "--version").decision is Decision.ALLOW
    assert _ev(tmp_path, "python", "-m", "pytest", "-q").decision is Decision.ALLOW
    assert _ev(tmp_path, "pytest").decision is Decision.ALLOW
    assert _ev(tmp_path, "npm", "run", "build").decision is Decision.ALLOW
    assert _ev(tmp_path, "npm", "test").decision is Decision.ALLOW
    assert _ev(tmp_path, "git", "status").decision is Decision.ALLOW
    assert _ev(tmp_path, "node", "--version").decision is Decision.ALLOW


def test_approval_required_commands(tmp_path):
    for cmd in (("npm", "install"), ("npm", "run", "deploy"), ("npx", "create-foo"), ("git", "commit", "-m", "x"),
                ("python", "script.py"), ("node", "build.js")):
        assert _ev(tmp_path, *cmd).decision is Decision.REQUIRE_APPROVAL, cmd


def test_dangerous_commands_rejected_even_if_allowlisted(tmp_path):
    for cmd in (("rm", "-rf", "x"), ("sudo", "ls"), ("curl", "http://x"), ("sh", "-c", "x"), ("bash",), ("dd", "if=a"),
                ("chmod", "-R", "777", "."), ("shutdown",), ("reboot",), ("mkfs", "x"), ("/bin/rm", "x")):
        assert _ev(tmp_path, *cmd).decision is Decision.DENY, cmd


def test_dangerous_subcommands_and_options_rejected(tmp_path):
    for cmd in (("python", "-c", "print(1)"), ("python", "-m", "pip", "install", "x"), ("node", "-e", "1"),
                ("git", "push"), ("git", "clone", "x"), ("git", "-c", "a=b", "status"), ("npm", "publish"),
                ("npm", "exec", "x"), ("npm", "run", "build", "-g")):
        assert _ev(tmp_path, *cmd).decision is Decision.DENY, cmd


def test_unlisted_program_rejected(tmp_path):
    assert _ev(tmp_path, "ls").decision is Decision.DENY


def test_argument_path_escapes_rejected(tmp_path):
    for cmd in (("pytest", "/etc/passwd"), ("pytest", "../.."), ("npm", "run", "build", "--prefix=../.."),
                ("pytest", "~/x"), ("pytest", ".env")):
        assert _ev(tmp_path, *cmd).decision is Decision.DENY, cmd
    assert _ev(tmp_path, "pytest", "tests/test_a.py::test_x").decision is Decision.ALLOW


def test_command_timeout_kills_process(tmp_path):
    t0 = time.time()
    out = run_process([sys.executable, "-c", "import time; time.sleep(10)"], tmp_path, 0.5, 1000)
    assert out.timed_out and out.exit_code is None
    assert time.time() - t0 < 5


def test_process_captures_output_and_exit_code(tmp_path):
    out = run_process([sys.executable, "-c", "import sys; print('hi'); sys.stderr.write('e'); sys.exit(3)"], tmp_path, 10, 1000)
    assert (out.exit_code, out.stdout.strip(), out.stderr.strip(), out.timed_out) == (3, "hi", "e", False)
    assert out.duration_ms >= 0


def test_child_env_excludes_secrets():
    os.environ["NEXORA_TEST_SECRET_TOKEN"] = "super-secret-value-123"
    try:
        assert "NEXORA_TEST_SECRET_TOKEN" not in safe_env()
        import tempfile
        from pathlib import Path
        with tempfile.TemporaryDirectory() as d:
            out = run_process([sys.executable, "-c", "print('super-secret-value-123')"], Path(d), 10, 1000)
        assert "super-secret-value-123" not in out.stdout and "[REDACTED]" in out.stdout
    finally:
        del os.environ["NEXORA_TEST_SECRET_TOKEN"]


def test_approval_store_binding_single_use_and_expiry():
    s = ApprovalStore(ttl_s=60)
    a = s.request("filesystem.delete", {"path": "a.txt"}, "needs approval")
    assert not s.consume(a.id, "filesystem.delete", {"path": "a.txt"})  # not approved yet
    s.approve(a.id)
    assert not s.consume(a.id, "filesystem.delete", {"path": "other.txt"})  # different args
    assert s.consume(a.id, "filesystem.delete", {"path": "a.txt"})
    assert not s.consume(a.id, "filesystem.delete", {"path": "a.txt"})  # single use
    expired = ApprovalStore(ttl_s=-1)
    b = expired.request("t", {}, "r")
    assert _raises(ApprovalError, expired.approve, b.id)
    assert _raises(ApprovalError, s.approve, "apr_missing")
EOF

cat > backend/tests/test_api.py <<'EOF'
import json


def tool(client, name, arguments, approval_id=None):
    return client.post("/api/v1/tools/execute", json={"tool": name, "arguments": arguments, "approval_id": approval_id})


def test_health(client):
    r = client.get("/health")
    assert r.status_code == 200
    assert r.json()["status"] == "ok" and r.json()["service"] == "nexora-engine"


def test_file_write_read_roundtrip(client, ws):
    r = client.post("/api/v1/project/write", json={"path": "src/hello.txt", "content": "hi there"})
    assert r.status_code == 200 and r.json()["data"]["created"] is True
    assert (ws / "src" / "hello.txt").read_text() == "hi there"
    r = client.post("/api/v1/project/read", json={"path": "src/hello.txt"})
    assert r.json()["data"]["content"] == "hi there"
    again = client.post("/api/v1/project/write", json={"path": "src/hello.txt", "content": "x"})
    assert again.status_code == 400  # exists, overwrite not requested


def test_edit_file(client, ws):
    (ws / "a.txt").write_text("one two two")
    ambiguous = tool(client, "filesystem.edit", {"path": "a.txt", "old": "two", "new": "2"})
    assert ambiguous.status_code == 400
    r = tool(client, "filesystem.edit", {"path": "a.txt", "old": "one", "new": "1"})
    assert r.status_code == 200 and (ws / "a.txt").read_text() == "1 two two"


def test_directory_listing(client, ws):
    (ws / "d").mkdir()
    (ws / "f.txt").write_text("x")
    r = tool(client, "filesystem.list", {"path": "."})
    assert {(e["name"], e["type"]) for e in r.json()["data"]["entries"]} == {("d", "dir"), ("f.txt", "file")}


def test_file_search(client, ws):
    (ws / "src").mkdir()
    (ws / "src" / "a.py").write_text("x = 1\nneedle = 2\n")
    r = client.post("/api/v1/project/search", json={"query": "needle"})
    m = r.json()["data"]["matches"]
    assert m and m[0]["path"] == "src/a.py" and m[0]["line"] == 2


def test_path_traversal_blocked_via_api(client, ws):
    for bad in ("../../etc/passwd", "/etc/passwd", "..", "a/../../x"):
        r = client.post("/api/v1/project/read", json={"path": bad})
        assert r.status_code == 403 and r.json()["status"] == "denied", bad
    r = client.post("/api/v1/project/write", json={"path": "../evil.txt", "content": "x"})
    assert r.status_code == 403
    assert not (ws.parent / "evil.txt").exists()


def test_secret_files_blocked(client, ws):
    (ws / ".env").write_text("KEY=abc")
    assert client.post("/api/v1/project/read", json={"path": ".env"}).status_code == 403
    assert client.post("/api/v1/project/write", json={"path": ".env", "content": "x", "overwrite": True}).status_code == 403


def test_delete_requires_approval(client, ws):
    f = ws / "victim.txt"
    f.write_text("keep me")
    r = tool(client, "filesystem.delete", {"path": "victim.txt"})
    assert r.status_code == 428 and r.json()["status"] == "approval_required"
    assert f.exists()  # nothing was deleted
    apr = r.json()["approval_id"]
    # wrong approval id / unapproved id must not work
    assert tool(client, "filesystem.delete", {"path": "victim.txt"}, apr).status_code == 428
    assert f.exists()
    assert client.post(f"/api/v1/approvals/{apr}/approve").status_code == 200
    # an approval for victim.txt cannot authorise a different path
    (ws / "other.txt").write_text("x")
    assert tool(client, "filesystem.delete", {"path": "other.txt"}, apr).status_code == 428
    assert (ws / "other.txt").exists()
    assert tool(client, "filesystem.delete", {"path": "victim.txt"}, apr).status_code == 200
    assert not f.exists()
    assert tool(client, "filesystem.delete", {"path": "victim.txt"}, apr).status_code == 428  # single use


def test_command_allowlist_and_rejection_via_api(client):
    r = tool(client, "command.run", {"program": "python", "args": ["--version"]})
    assert r.status_code == 200 and r.json()["exit_code"] == 0 and "Python" in r.json()["stdout"]
    for prog, args in (("rm", ["-rf", "x"]), ("curl", ["http://example.com"]), ("sh", ["-c", "id"]), ("ls", [])):
        r = tool(client, "command.run", {"program": prog, "args": args})
        assert r.status_code == 403 and r.json()["status"] == "denied", prog
    assert tool(client, "command.run", {"program": "npx", "args": ["cowsay"]}).status_code == 428


def test_command_timeout_end_to_end(client, ws):
    (ws / "sleep.py").write_text("import time\ntime.sleep(30)\n")
    r = tool(client, "command.run", {"program": "python", "args": ["sleep.py"]})
    assert r.status_code == 428  # running workspace scripts needs approval
    apr = r.json()["approval_id"]
    client.post(f"/api/v1/approvals/{apr}/approve")
    r = tool(client, "command.run", {"program": "python", "args": ["sleep.py"]}, apr)
    body = r.json()
    assert body["data"]["timed_out"] is True and body["success"] is False and "timed out" in body["error"]


def test_structured_tool_result(client):
    body = tool(client, "command.run", {"program": "python", "args": ["--version"]}).json()
    for key in ("tool", "success", "status", "exit_code", "stdout", "stderr", "duration_ms", "timestamp"):
        assert key in body
    assert body["tool"] == "command.run" and body["status"] == "success"
    assert isinstance(tool(client, "nope.tool", {}).json()["error"], str)
    assert any(t["name"] == "filesystem.read" and t["permission"] == "read" for t in client.get("/api/v1/tools").json()["tools"])


def test_activity_events(client):
    tool(client, "filesystem.list", {"path": "."})
    ev = client.get("/api/v1/activity").json()["events"][-1]
    assert {"tool", "status", "timestamp", "duration_ms"} <= ev.keys() and ev["tool"] == "filesystem.list"


def test_project_inspection(client, ws):
    (ws / "package.json").write_text(json.dumps({"dependencies": {"next": "16", "react": "19"}, "scripts": {"build": "next build --webpack"}}))
    (ws / "app").mkdir()
    (ws / "app" / "page.tsx").write_text("export default function P(){return null}")
    d = client.get("/api/v1/project/inspect").json()["data"]
    assert "nextjs" in d["types"] and "react" in d["types"]
    assert d["scripts"]["build"] == "next build --webpack" and "app/page.tsx" in d["tree"]


def test_inspection_detects_fastapi_and_generic(client, ws):
    assert client.get("/api/v1/project/inspect").json()["data"]["types"] == ["generic"]
    (ws / "requirements.txt").write_text("fastapi\n")
    assert client.get("/api/v1/project/inspect").json()["data"]["types"] == ["fastapi", "python"]


def test_agent_planning(client):
    r = client.post("/api/v1/agent/plan", json={"request": "Create a landing page"})
    assert r.status_code == 200
    plan = r.json()
    assert plan["planner"] == "deterministic" and len(plan["steps"]) >= 7
    assert [s["id"] for s in plan["steps"]][0] == "inspect"
    assert any(s["kind"] == "unsupported" and "model provider" in s["note"] for s in plan["steps"])


def test_agent_plan_rejects_escape(client):
    r = client.post("/api/v1/agent/plan", json={"request": "x", "project_path": "../.."})
    assert r.status_code == 403


def test_agent_run_with_real_verification(client, ws):
    (ws / "tests").mkdir()
    (ws / "tests" / "test_ok.py").write_text("def test_ok():\n    assert 1 + 1 == 2\n")
    r = client.post("/api/v1/agent/run", json={"request": "check this project"})
    state = r.json()
    assert state["status"] == "completed", state
    assert state["verification_results"][0]["passed"] is True
    assert state["tool_calls"] and state["tool_calls"][0]["result"]["tool"] == "project.inspect"
    assert client.get(f"/api/v1/agent/runs/{state['run_id']}").json()["run_id"] == state["run_id"]


def test_agent_run_reports_failed_verification(client, ws):
    (ws / "tests").mkdir()
    (ws / "tests" / "test_bad.py").write_text("def test_bad():\n    assert False\n")
    state = client.post("/api/v1/agent/run", json={"request": "check"}).json()
    assert state["status"] == "failed" and state["verification_results"][0]["passed"] is False
    assert "not implemented" in state["errors"][0]


def test_agent_run_with_nothing_to_verify(client):
    state = client.post("/api/v1/agent/run", json={"request": "hello"}).json()
    assert state["status"] == "completed" and state["verification_results"][0]["passed"] is None
    assert "no file edits" in state["summary"]
EOF

# =====================================================================
# README
# =====================================================================
cat > backend/README.md <<'EOF'
# NEXORA Engine V1 (backend)

A small, security-first FastAPI foundation for the NEXORA software-engineering agent.
**Engine V1 does not call any language model, generate code, fix errors or create checkpoints.**
It provides the safe tool layer, the approval system, a deterministic planner and the agent loop
skeleton (plan, execute, observe, verify) that those features will plug into.

## Architecture
```
routes/ (FastAPI, /api/v1)  ->  Agent (planner, executor, observer, verifier, state)
                                     |
                              ToolRegistry  (validate -> policy -> approval gate -> handler -> activity event)
                                     |
        filesystem.* | project.inspect | command.run | test.run
                                     |
        security/: path_guard · permissions (+ApprovalStore) · command_policy      services/process.py (no shell)
```
The agent only reaches the system through `ToolRegistry.execute`. `ModelProvider` (agent/provider.py) is
the seam for FreeLLMAPI; only a `MockProvider` exists.

## Install (Termux)
```bash
cd backend
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements-dev.txt     # runtime only: requirements.txt
```
Pydantic needs a native extension. If no wheel exists for your Python/Android combination, pip builds it
from source: `pkg install rust binutils` and `export ANDROID_API_LEVEL=$(getprop ro.build.version.sdk)` first.

## Run
```bash
cd backend && source .venv/bin/activate
uvicorn app.main:create_app --factory --host 127.0.0.1 --port 8000
```
Docs: http://127.0.0.1:8000/docs. Keep it on 127.0.0.1: V1 has no authentication.

## Configuration (environment, see `.env.example`)
`NEXORA_WORKSPACE_ROOT` (default `<repo>/workspace`; refuses `/` and `$HOME`), `NEXORA_CORS_ORIGINS`,
`NEXORA_ALLOWED_PROGRAMS`, `NEXORA_COMMAND_TIMEOUT_S`, `NEXORA_LOG_LEVEL`. No API keys are needed or stored.

## Endpoints
`GET /health` · `GET /api/v1/project/inspect` · `POST /api/v1/project/{read,write,search}` ·
`POST /api/v1/agent/plan|run` · `GET /api/v1/agent/runs/{id}` · `POST /api/v1/agent/runs/{id}/resume` ·
`GET /api/v1/tools` · `POST /api/v1/tools/execute` · `GET /api/v1/activity` ·
`GET /api/v1/approvals` · `POST /api/v1/approvals/{id}/approve|deny`

Tool responses share one envelope (`status`: success | error | denied | approval_required, `exit_code`,
`stdout`, `stderr`, `duration_ms`, `timestamp`, `approval_id`). HTTP: denied 403, approval_required 428.

## Security model
- **Workspace confinement:** every path resolves inside the workspace root; `..`, absolute paths, `~`, and
  symlink escapes are rejected; secret files (`.env*`, keys) are blocked; `.git` is write-protected.
- **Permissions:** READ/WRITE allowed in workspace; DELETE and DEPLOY need approval; EXECUTE only via the command
  policy; NETWORK and SECRET_ACCESS are blocked.
- **Commands:** structured `{program, args[]}`, never a shell. Bare program names only; a deny-list (rm, sudo, curl,
  sh, dd, chmod, ...) wins even if allowlisted; path arguments must stay in the workspace; per-program subcommand
  rules (e.g. `git push`, `python -c`, `node -e`, `npm publish` denied; `npm install`, running scripts need approval).
  Timeout kills the whole process group; output is capped; child env is a minimal allowlist; secret values are redacted.
- **Approvals:** bound to the exact tool and arguments, single-use, expiring. Only the approvals API grants them.
  Known limitation: no authentication yet, and running tests/scripts executes workspace code by nature.

## Tests
```bash
cd backend && source .venv/bin/activate && pytest
```

## Next: FreeLLMAPI
Add `FreeLLMAPIProvider(ModelProvider)` that calls your gateway server-side (key from env), then an `LLMPlanner`
returning the same `AgentPlan`, then an apply/fix loop and checkpoints.
EOF

# =====================================================================
# .gitignore (idempotent)
# =====================================================================
touch .gitignore
if ! grep -q "# NEXORA engine" .gitignore; then
cat >> .gitignore <<'EOF'

# NEXORA engine
backend/.venv/
__pycache__/
.pytest_cache/
.env
.env.*
!.env.example
/workspace/
*.log
EOF
fi

echo ""; echo "Backend files written under backend/. Frontend source untouched."
[ "$FILES_ONLY" = "1" ] && { echo "--files-only: skipping venv, install, tests and frontend checks."; exit 0; }

# =====================================================================
# Install, validate backend, validate frontend
# =====================================================================
command -v getprop >/dev/null 2>&1 && export ANDROID_API_LEVEL="$(getprop ro.build.version.sdk)"
echo ""; echo "=== Creating backend/.venv and installing dependencies ==="
python3 -m venv backend/.venv
# shellcheck disable=SC1091
. backend/.venv/bin/activate
if ! pip install -r backend/requirements-dev.txt; then
  echo ""
  echo "pip install FAILED. Likely pydantic-core (native). Try: pkg install rust binutils"
  echo "then re-run:  . backend/.venv/bin/activate && pip install -r backend/requirements-dev.txt"
  echo "Paste the pip error here if it persists. Backend files are in place."
  exit 2
fi
pip list 2>/dev/null | grep -iE '^(fastapi|uvicorn|pydantic|pytest|httpx|starlette) ' || true

BE_COMPILE="ok"; BE_IMPORT="ok"; BE_TESTS="ok"; FE_LINT="ok"; FE_BUILD="ok"
cd backend
echo ""; echo "=== Python compile ==="; python -m compileall -q app tests || BE_COMPILE="FAILED"
echo "=== Backend import / FastAPI validation ==="
python -c "
import tempfile
from app.config import Settings
from app.main import create_app
from app.services.container import Container
d = tempfile.mkdtemp()
app = create_app(Container.build(Settings(workspace_root=__import__('pathlib').Path(d).resolve())))
print('routes:', len(app.routes), 'openapi paths:', len(app.openapi()['paths']))
" || BE_IMPORT="FAILED"
echo "=== pytest ==="; python -m pytest || BE_TESTS="FAILED"
cd ..
deactivate 2>/dev/null || true

echo ""; echo "=== Frontend: npm run lint ==="; npm run lint || FE_LINT="FAILED"
echo "=== Frontend: npm run build ==="; npm run build || FE_BUILD="FAILED"

echo ""; echo "=== SUMMARY ==="
echo "python compile : $BE_COMPILE"; echo "backend import : $BE_IMPORT"; echo "pytest         : $BE_TESTS"
echo "frontend lint  : $FE_LINT";    echo "frontend build : $FE_BUILD"
echo ""; echo "git status:"; git status --short 2>/dev/null || true
echo ""; echo "Run the engine:"
echo "  cd ~/nexora-ai/backend && source .venv/bin/activate && uvicorn app.main:create_app --factory --host 127.0.0.1 --port 8000"
[ "$BE_COMPILE$BE_IMPORT$BE_TESTS$FE_LINT$FE_BUILD" = "okokokokok" ] || exit 1
