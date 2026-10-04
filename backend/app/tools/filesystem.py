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
