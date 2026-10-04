from fastapi import APIRouter, Depends

from ..schemas import PathRequest, SearchRequest, WriteRequest
from ..services.container import Container
from .deps import get_container, respond

router = APIRouter()


@router.get("/inspect")
def inspect(path: str = ".", max_depth: int = 2, c: Container = Depends(get_container)):
    return respond(c.registry.execute("project.inspect", {"path": path, "max_depth": max_depth}))


@router.post("/read")
def read(body: PathRequest, c: Container = Depends(get_container)):
    return respond(c.registry.execute("filesystem.read", body.model_dump()))


@router.post("/write")
def write(body: WriteRequest, c: Container = Depends(get_container)):
    return respond(c.registry.execute("filesystem.write", body.model_dump()))


@router.post("/search")
def search(body: SearchRequest, c: Container = Depends(get_container)):
    return respond(c.registry.execute("filesystem.search", body.model_dump()))
