"""Structured error handling: every error body is {"error": {"code", "message"}}."""
import logging

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse

from .security.path_guard import PathGuardError

log = logging.getLogger("nexora.errors")


class NexoraError(Exception):
    status_code = 400
    code = "bad_request"

    def __init__(self, message: str):
        super().__init__(message)
        self.message = message


class NotFoundError(NexoraError):
    status_code = 404
    code = "not_found"


class ConflictError(NexoraError):
    status_code = 409
    code = "conflict"


def _body(code: str, message: str) -> dict:
    return {"error": {"code": code, "message": message}}


def register_error_handlers(app: FastAPI) -> None:
    @app.exception_handler(NexoraError)
    async def _nexora(request: Request, exc: NexoraError):
        return JSONResponse(status_code=exc.status_code, content=_body(exc.code, exc.message))

    @app.exception_handler(PathGuardError)
    async def _path(request: Request, exc: PathGuardError):
        return JSONResponse(status_code=403, content=_body("path_denied", str(exc)))

    @app.exception_handler(Exception)
    async def _unhandled(request: Request, exc: Exception):
        log.exception("unhandled error on %s", request.url.path)
        return JSONResponse(status_code=500, content=_body("internal_error", "Internal server error"))
