from fastapi import APIRouter, Depends

from ..errors import ConflictError, NotFoundError
from ..security.permissions import ApprovalError
from ..services.container import Container
from .deps import get_container

router = APIRouter()


@router.get("")
def list_approvals(c: Container = Depends(get_container)):
    return {"approvals": c.approvals.list()}


def _decide(c: Container, approval_id: str, approve: bool) -> dict:
    try:
        a = c.approvals.approve(approval_id) if approve else c.approvals.deny(approval_id)
    except ApprovalError as exc:
        raise (NotFoundError if exc.not_found else ConflictError)(str(exc))
    return a.public()


# NOTE: these endpoints are the human decision point. The agent has no code path that calls them.
# Engine V1 has no authentication: keep the server bound to 127.0.0.1.
@router.post("/{approval_id}/approve")
def approve(approval_id: str, c: Container = Depends(get_container)):
    return _decide(c, approval_id, True)


@router.post("/{approval_id}/deny")
def deny(approval_id: str, c: Container = Depends(get_container)):
    return _decide(c, approval_id, False)
