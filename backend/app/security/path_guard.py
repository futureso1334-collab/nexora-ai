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
