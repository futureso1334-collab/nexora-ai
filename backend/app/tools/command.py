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
