from typing import Any

from pydantic import BaseModel, Field


class PathRequest(BaseModel):
    path: str = Field(min_length=1, max_length=1024)


class WriteRequest(BaseModel):
    path: str = Field(min_length=1, max_length=1024)
    content: str
    overwrite: bool = False


class SearchRequest(BaseModel):
    query: str = Field(min_length=1, max_length=200)
    path: str = "."
    max_results: int = Field(50, ge=1, le=500)


class ToolExecuteRequest(BaseModel):
    tool: str
    arguments: dict[str, Any] = Field(default_factory=dict)
    approval_id: str | None = None


class ResumeRequest(BaseModel):
    approval_id: str
