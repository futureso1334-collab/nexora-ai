from fastapi import APIRouter, Depends

from ..schemas import ToolExecuteRequest
from ..services.container import Container
from .deps import get_container, respond

router = APIRouter()


@router.get("/tools")
def list_tools(c: Container = Depends(get_container)):
    return {"tools": c.registry.specs()}


@router.post("/tools/execute")
def execute(body: ToolExecuteRequest, c: Container = Depends(get_container)):
    # Goes through the registry: input validation, permission policy, approval gate, command policy.
    return respond(c.registry.execute(body.tool, body.arguments, body.approval_id))


@router.get("/activity")
def activity(limit: int = 100, c: Container = Depends(get_container)):
    return {"events": c.activity.recent(max(1, min(limit, 500)))}
