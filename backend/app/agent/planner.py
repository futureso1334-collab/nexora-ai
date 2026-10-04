"""LLM planner for NEXORA using LangChain + FreeLLMAPI."""
import json
import re

from .models import AgentPlan, AgentRequest, AgentStep, ToolCall
from .provider import ModelProvider


class Planner:
    def __init__(self, provider: ModelProvider):
        self.provider = provider

    def plan(self, req: AgentRequest, project_types: list[str]) -> AgentPlan:
        raise NotImplementedError


class DeterministicPlanner(Planner):
    def plan(self, req: AgentRequest, project_types: list[str]) -> AgentPlan:
        p = req.project_path
        steps = [
            AgentStep(
                index=0,
                id="inspect",
                title="Inspect project",
                description="Read structure and scripts.",
                kind="tool",
                tool_call=ToolCall(tool="project.inspect", arguments={"path": p}),
            ),
            AgentStep(
                index=1,
                id="identify",
                title="Identify framework",
                description="Derive project type from the inspection.",
                kind="analysis",
            ),
            AgentStep(
                index=2,
                id="explore",
                title="Inspect relevant files",
                description="Look for files related to the request.",
                kind="tool",
                tool_call=ToolCall(tool="filesystem.list", arguments={"path": p}),
            ),
            AgentStep(
                index=3,
                id="plan_changes",
                title="Plan changes",
                description="Decide which files to create or edit.",
                kind="unsupported",
                note="Needs a model provider; the deterministic planner cannot design changes.",
            ),
            AgentStep(
                index=4,
                id="apply",
                title="Apply changes",
                description="Create or edit files via filesystem tools.",
                kind="unsupported",
                note="Code generation is unavailable until a model provider is connected.",
            ),
            AgentStep(
                index=5,
                id="verify",
                title="Run verification",
                description="Run the project's test/lint/build checks.",
                kind="tool" if req.verify else "unsupported",
                tool_call=ToolCall(tool="test.run", arguments={"path": p}) if req.verify else None,
                note="" if req.verify else "Verification disabled for this request.",
            ),
            AgentStep(
                index=6,
                id="report",
                title="Report result",
                description="Summarise what happened.",
                kind="analysis",
            ),
        ]
        return AgentPlan(
            request=req.request,
            project_types=project_types,
            planner="deterministic",
            steps=steps,
            notes=["Engine V1 deterministic planner."],
        )


class LLMPlanner(Planner):
    """Ask the connected model to create a safe NEXORA execution plan."""

    def plan(self, req: AgentRequest, project_types: list[str]) -> AgentPlan:
        system = """You are the planning engine for NEXORA AI.
Create a concise execution plan for the user's software request.
Return ONLY valid JSON with this shape:
{
  "steps": [
    {
      "id": "short_id",
      "title": "title",
      "description": "description",
      "kind": "tool" or "analysis",
      "tool": null or "project.inspect" or "filesystem.list" or "filesystem.search" or "test.run",
      "arguments": {}
    }
  ],
  "notes": ["note"]
}
Only use the listed tools. Do not invent tools.
Do not write code. Planning only.
"""

        prompt = (
            f"User request: {req.request}\n"
            f"Project path: {req.project_path}\n"
            f"Detected project types: {', '.join(project_types) or 'unknown'}\n"
            f"Verification requested: {req.verify}"
        )

        raw = self.provider.generate(prompt, system=system, max_tokens=1800)
        data = self._parse_json(raw)

        if not data or not isinstance(data.get("steps"), list):
            return self._fallback(req, project_types, "Model returned an invalid plan; used safe fallback.")

        steps = []
        allowed = {"project.inspect", "filesystem.read", "filesystem.list", "filesystem.search", "test.run"}

        for i, item in enumerate(data["steps"][:12]):
            if not isinstance(item, dict):
                continue

            kind = item.get("kind", "analysis")
            tool = item.get("tool")
            arguments = item.get("arguments") or {}

            if kind == "tool":
                if tool not in allowed:
                    kind = "analysis"
                    tool = None
                    arguments = {}
                else:
                    arguments = dict(arguments)
                    if tool in {"project.inspect", "filesystem.list", "filesystem.search", "test.run"}:
                        arguments.setdefault("path", req.project_path)
                    if tool == "filesystem.read":
                        arguments.setdefault("path", req.project_path)
                    if tool == "filesystem.search":
                        arguments.setdefault("query", req.request[:100])
                        arguments.setdefault("max_results", 20)

            steps.append(
                AgentStep(
                    index=i,
                    id=str(item.get("id") or f"step_{i}"),
                    title=str(item.get("title") or "Plan step"),
                    description=str(item.get("description") or ""),
                    kind=kind,
                    tool_call=ToolCall(tool=tool, arguments=arguments) if tool else None,
                )
            )

        if not steps:
            return self._fallback(req, project_types, "Model returned no usable steps; used safe fallback.")

        if req.verify and not any(s.tool_call and s.tool_call.tool == "test.run" for s in steps):
            steps.append(
                AgentStep(
                    index=len(steps),
                    id="verify",
                    title="Run verification",
                    description="Run the project's verification checks.",
                    kind="tool",
                    tool_call=ToolCall(tool="test.run", arguments={"path": req.project_path}),
                )
            )

        return AgentPlan(
            request=req.request,
            project_types=project_types,
            planner="llm",
            steps=steps,
            notes=list(data.get("notes") or []) + [
                "LLM planning is enabled through LangChain and FreeLLMAPI."
            ],
        )

    @staticmethod
    def _parse_json(raw: str) -> dict | None:
        text = raw.strip()
        text = re.sub(r"^```(?:json)?\s*", "", text, flags=re.I)
        text = re.sub(r"\s*```$", "", text)
        try:
            value = json.loads(text)
            return value if isinstance(value, dict) else None
        except json.JSONDecodeError:
            match = re.search(r"\{.*\}", text, flags=re.S)
            if not match:
                return None
            try:
                value = json.loads(match.group(0))
                return value if isinstance(value, dict) else None
            except json.JSONDecodeError:
                return None

    @staticmethod
    def _fallback(req: AgentRequest, project_types: list[str], note: str) -> AgentPlan:
        steps = [
            AgentStep(
                index=0,
                id="inspect",
                title="Inspect project",
                description="Read project structure and scripts.",
                kind="tool",
                tool_call=ToolCall(tool="project.inspect", arguments={"path": req.project_path}),
            ),
            AgentStep(
                index=1,
                id="explore",
                title="Explore project",
                description="Inspect the project files.",
                kind="tool",
                tool_call=ToolCall(tool="filesystem.list", arguments={"path": req.project_path}),
            ),
        ]
        if req.verify:
            steps.append(
                AgentStep(
                    index=2,
                    id="verify",
                    title="Run verification",
                    description="Run available verification checks.",
                    kind="tool",
                    tool_call=ToolCall(tool="test.run", arguments={"path": req.project_path}),
                )
            )
        return AgentPlan(
            request=req.request,
            project_types=project_types,
            planner="llm-fallback",
            steps=steps,
            notes=[note],
        )
