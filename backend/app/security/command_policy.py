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
