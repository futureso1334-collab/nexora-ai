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
