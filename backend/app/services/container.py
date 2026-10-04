"""Wires settings, guard, approvals, registry and agent together (one place, easy to test)."""
from dataclasses import dataclass

from ..agent.agent import Agent
from ..agent.planner import LLMPlanner
from ..agent.provider import FreeLLMAPIProvider, MockProvider, ModelProvider
from ..agent.state import RunStore
from ..config import Settings, configure_logging
from ..security.path_guard import PathGuard
from ..security.permissions import ApprovalStore
from ..tools.base import ToolContext
from ..tools.registry import ToolRegistry, build_registry
from .activity import ActivityLog


@dataclass
class Container:
    settings: Settings
    guard: PathGuard
    approvals: ApprovalStore
    activity: ActivityLog
    registry: ToolRegistry
    provider: ModelProvider
    store: RunStore
    agent: Agent

    @classmethod
    def build(cls, settings: Settings) -> "Container":
        guard = PathGuard(settings.workspace_root)
        approvals = ApprovalStore(settings.approval_ttl_s)
        activity = ActivityLog()
        registry = build_registry(ToolContext(settings, guard, approvals), activity)
        provider, store = MockProvider(), RunStore()
        return cls(settings, guard, approvals, activity, registry, provider, store, Agent(registry, guard, provider, store))

    @classmethod
    def from_env(cls) -> "Container":
        settings = Settings.from_env()
        configure_logging(settings.log_level)
        container = cls.build(settings)
        provider = FreeLLMAPIProvider()
        container.provider = provider
        container.agent.provider = provider
        container.agent.planner = LLMPlanner(provider)
        return container
