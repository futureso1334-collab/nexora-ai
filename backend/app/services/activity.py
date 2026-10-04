"""In-memory activity log: structured events the frontend activity panel can read later."""
from __future__ import annotations

import threading
from collections import deque
from typing import Any


class ActivityLog:
    def __init__(self, maxlen: int = 500):
        self._events: deque[dict[str, Any]] = deque(maxlen=maxlen)
        self._lock = threading.Lock()
        self._seq = 0

    def record(self, event: dict[str, Any]) -> None:
        with self._lock:
            self._seq += 1
            self._events.append({"id": self._seq, **event})

    def recent(self, limit: int = 100) -> list[dict[str, Any]]:
        with self._lock:
            return list(self._events)[-limit:]
