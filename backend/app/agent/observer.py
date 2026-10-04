from ..tools.base import ToolResult
from .models import AgentStep, Observation


def observe(step: AgentStep, result: ToolResult) -> Observation:
    tool = step.tool_call.tool if step.tool_call else None
    if result.status == "success":
        summary = f"{tool} succeeded in {result.duration_ms} ms"
    else:
        summary = f"{tool} {result.status}: {(result.error or 'no details')[:200]}"
    return Observation(step_index=step.index, tool=tool, success=result.success, summary=summary)
