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
