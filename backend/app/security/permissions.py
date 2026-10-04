"""Permission categories, static policy, and the human-approval store.

The agent can REQUEST approval but has no code path that grants it. Approvals are granted only
through the approvals API (a person/frontend), are bound to the exact tool + arguments, expire,
and are single-use.
"""
from __future__ import annotations

import hashlib
import json
import secrets
import threading
import time
from dataclasses import dataclass
from enum import Enum
from typing import Any


class Permission(str, Enum):
    READ = "read"
    WRITE = "write"
    DELETE = "delete"
    EXECUTE = "execute"
    NETWORK = "network"
    DEPLOY = "deploy"
    SECRET_ACCESS = "secret_access"


class Decision(str, Enum):
    ALLOW = "allow"
    REQUIRE_APPROVAL = "require_approval"
    DENY = "deny"


@dataclass(frozen=True)
class Verdict:
    decision: Decision
    reason: str = ""


class PolicyDenied(Exception):
    """An operation was refused by policy."""


class ApprovalError(Exception):
    def __init__(self, message: str, not_found: bool = False):
        super().__init__(message)
        self.not_found = not_found


_STATIC = {
    Permission.READ: Verdict(Decision.ALLOW),
    Permission.WRITE: Verdict(Decision.ALLOW, "allowed inside the workspace (enforced by PathGuard)"),
    Permission.DELETE: Verdict(Decision.REQUIRE_APPROVAL, "Deleting requires approval"),
    # EXECUTE has no blanket allow: only tools that supply their own command-policy assessment run.
    Permission.EXECUTE: Verdict(Decision.DENY, "Execution is only allowed through the command policy"),
    Permission.NETWORK: Verdict(Decision.DENY, "Network access is not available to tools in Engine V1"),
    Permission.DEPLOY: Verdict(Decision.REQUIRE_APPROVAL, "Deployment requires approval"),
    Permission.SECRET_ACCESS: Verdict(Decision.DENY, "Secret access is blocked"),
}


def static_verdict(permission: Permission) -> Verdict:
    return _STATIC[permission]


def args_digest(tool: str, args: dict[str, Any]) -> str:
    blob = json.dumps({"tool": tool, "args": args}, sort_keys=True, default=str)
    return hashlib.sha256(blob.encode()).hexdigest()


@dataclass
class Approval:
    id: str
    tool: str
    digest: str
    reason: str
    summary: dict[str, Any]
    status: str  # pending | approved | denied | used
    created_at: float
    expires_at: float

    def public(self) -> dict[str, Any]:
        expired = time.time() > self.expires_at
        return {"id": self.id, "tool": self.tool, "reason": self.reason, "summary": self.summary,
                "status": "expired" if expired and self.status in ("pending", "approved") else self.status,
                "expires_at": self.expires_at}


class ApprovalStore:
    def __init__(self, ttl_s: int = 600):
        self._ttl = ttl_s
        self._items: dict[str, Approval] = {}
        self._lock = threading.Lock()

    def request(self, tool: str, args: dict[str, Any], reason: str, summary: dict[str, Any] | None = None) -> Approval:
        digest, now = args_digest(tool, args), time.time()
        with self._lock:
            for a in self._items.values():
                if a.digest == digest and a.status == "pending" and a.expires_at > now:
                    return a
            a = Approval("apr_" + secrets.token_hex(6), tool, digest, reason, summary or {}, "pending", now, now + self._ttl)
            self._items[a.id] = a
            if len(self._items) > 500:  # bound memory
                for old in sorted(self._items.values(), key=lambda x: x.created_at)[:100]:
                    del self._items[old.id]
            return a

    def _pending(self, approval_id: str) -> Approval:
        a = self._items.get(approval_id)
        if a is None:
            raise ApprovalError("unknown approval", not_found=True)
        if time.time() > a.expires_at:
            raise ApprovalError("approval expired")
        if a.status != "pending":
            raise ApprovalError(f"approval is already {a.status}")
        return a

    def approve(self, approval_id: str) -> Approval:
        with self._lock:
            a = self._pending(approval_id)
            a.status = "approved"
            return a

    def deny(self, approval_id: str) -> Approval:
        with self._lock:
            a = self._pending(approval_id)
            a.status = "denied"
            return a

    def consume(self, approval_id: str, tool: str, args: dict[str, Any]) -> bool:
        """True only for an approved, unexpired approval for exactly this tool+args. Single use."""
        with self._lock:
            a = self._items.get(approval_id)
            if not a or a.status != "approved" or time.time() > a.expires_at or a.digest != args_digest(tool, args):
                return False
            a.status = "used"
            return True

    def list(self) -> list[dict[str, Any]]:
        with self._lock:
            return [a.public() for a in sorted(self._items.values(), key=lambda x: -x.created_at)[:100]]
