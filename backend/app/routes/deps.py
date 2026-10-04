from fastapi import Request
from fastapi.responses import JSONResponse

from ..services.container import Container
from ..tools.base import ToolResult

# HTTP mapping: denied -> 403, approval_required -> 428 (frontend shows "Approval required"),
# tool error -> 400, but a command that ran and exited non-zero is a normal 200 with exit_code.
_STATUS = {"success": 200, "error": 400, "denied": 403, "approval_required": 428}


def get_container(request: Request) -> Container:
    return request.app.state.container


def respond(result: ToolResult) -> JSONResponse:
    code = _STATUS[result.status]
    if result.status == "error" and result.exit_code is not None:
        code = 200
    return JSONResponse(status_code=code, content=result.model_dump(mode="json"))
