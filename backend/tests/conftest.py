import pytest
from fastapi.testclient import TestClient

from app.config import DEFAULT_PROGRAMS, Settings
from app.main import create_app
from app.services.container import Container


@pytest.fixture
def settings(tmp_path):
    ws = tmp_path / "ws"
    ws.mkdir()
    return Settings(workspace_root=ws.resolve(), allowed_programs=frozenset(DEFAULT_PROGRAMS),
                    command_timeout_s=5.0, max_output_bytes=20_000, max_file_bytes=200_000,
                    approval_ttl_s=60, log_level="WARNING")


@pytest.fixture
def container(settings):
    return Container.build(settings)


@pytest.fixture
def client(container):
    return TestClient(create_app(container))


@pytest.fixture
def ws(settings):
    return settings.workspace_root
