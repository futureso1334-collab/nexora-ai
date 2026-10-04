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
    notes: list[str] = Field(default_factory=list)
    verification_results: list[VerificationResult] = Field(default_factory=list)
    pending_approval: dict[str, Any] | None = None
    summary: str = ""
    created_at: str
    updated_at: str
