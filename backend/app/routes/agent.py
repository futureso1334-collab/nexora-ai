from fastapi import APIRouter, Depends

from ..agent.models import AgentPlan, AgentRequest, AgentState
from ..errors import NotFoundError
from ..schemas import ResumeRequest
from ..services.container import Container
from .deps import get_container

router = APIRouter()


@router.post("/plan")
def plan(body: AgentRequest, c: Container = Depends(get_container)) -> AgentPlan:
    return c.agent.plan(body)


@router.post("/run")
def run(body: AgentRequest, c: Container = Depends(get_container)) -> AgentState:
    return c.agent.run(body)


@router.get("/runs/{run_id}")
def get_run(run_id: str, c: Container = Depends(get_container)) -> AgentState:
    state = c.store.get(run_id)
    if state is None:
        raise NotFoundError("unknown run")
    return state


@router.post("/runs/{run_id}/resume")
def resume(run_id: str, body: ResumeRequest, c: Container = Depends(get_container)) -> AgentState:
    return c.agent.resume(run_id, body.approval_id)
