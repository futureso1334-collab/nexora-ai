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
