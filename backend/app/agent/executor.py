from ..tools.base import ToolResult
from ..tools.registry import ToolRegistry
from .models import AgentState, AgentStep


class StepExecutor:
    """Runs a step's tool call through the registry (the only path to tools)."""

    def __init__(self, registry: ToolRegistry):
        self.registry = registry

    def run(self, state: AgentState, step: AgentStep, approval_id: str | None = None) -> ToolResult:
        call = step.tool_call.model_copy(deep=True)
        state.tool_calls.append(call)
        call.result = self.registry.execute(call.tool, call.arguments, approval_id)
        return call.result
