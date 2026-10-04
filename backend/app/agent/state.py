"""In-memory run store (bounded). Shaped so a persistence layer can replace it later."""
import threading
import uuid
from collections import OrderedDict
from datetime import datetime, timezone

from .models import AgentPlan, AgentRequest, AgentState, AgentStatus


def _now() -> str:
    return datetime.now(timezone.utc).isoformat()


class RunStore:
    def __init__(self, max_runs: int = 100):
        self._runs: OrderedDict[str, AgentState] = OrderedDict()
        self._lock = threading.Lock()
        self._max = max_runs

    def create(self, req: AgentRequest, plan: AgentPlan) -> AgentState:
        now = _now()
        state = AgentState(run_id=uuid.uuid4().hex[:12], project_root=req.project_path, user_request=req.request,
                           status=AgentStatus.planning, current_plan=plan, created_at=now, updated_at=now)
        self.save(state)
        return state

    def save(self, state: AgentState) -> None:
        state.updated_at = _now()
        with self._lock:
            self._runs[state.run_id] = state
            while len(self._runs) > self._max:
                self._runs.popitem(last=False)

    def get(self, run_id: str) -> AgentState | None:
        with self._lock:
            return self._runs.get(run_id)
