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
