"""NEXORA Engine entrypoint. Run with:  uvicorn app.main:create_app --factory --host 127.0.0.1 --port 8000"""
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from . import __version__
from .errors import register_error_handlers
from .routes import agent, approvals, project, tools
from .services.container import Container


def create_app(container: Container | None = None) -> FastAPI:
    container = container or Container.from_env()
    app = FastAPI(title="NEXORA Engine", version=__version__)
    app.state.container = container
    app.add_middleware(CORSMiddleware, allow_origins=list(container.settings.cors_origins),
                       allow_methods=["GET", "POST"], allow_headers=["Content-Type"])
    register_error_handlers(app)

    @app.get("/health")
    def health() -> dict:
        return {"status": "ok", "service": "nexora-engine", "version": __version__}

    app.include_router(project.router, prefix="/api/v1/project")
    app.include_router(agent.router, prefix="/api/v1/agent")
    app.include_router(approvals.router, prefix="/api/v1/approvals")
    app.include_router(tools.router, prefix="/api/v1")
    return app
