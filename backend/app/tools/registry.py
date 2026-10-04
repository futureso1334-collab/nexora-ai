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
