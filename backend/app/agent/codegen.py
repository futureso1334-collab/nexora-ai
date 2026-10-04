"""Structured code-change generation for NEXORA."""
import json
import re
from dataclasses import dataclass

from .provider import ModelProvider


@dataclass
class FileChange:
    path: str
    content: str
    overwrite: bool = False


class CodeGenerator:
    """Generate structured file changes from the user's request and read context."""

    def __init__(self, provider: ModelProvider):
        self.provider = provider

    def generate(
        self,
        request: str,
        project_types: list[str],
        context: list[dict],
    ) -> list[FileChange]:
        system = """You are the code-generation engine for NEXORA AI.

Generate the actual file changes needed to fulfill the user's request.

Return ONLY valid JSON:
{
  "changes": [
    {
      "path": "relative/path/to/file",
      "content": "complete UTF-8 file contents",
      "overwrite": false
    }
  ],
  "notes": ["short note"]
}

Rules:
- Return complete file contents, not patches.
- Use only relative workspace paths.
- Never use absolute paths.
- Never include paths containing "..".
- Only change files needed for the request.
- If an existing file must be replaced, set overwrite=true.
- Do not invent files that are unnecessary.
- Preserve existing project conventions when context is provided.
- Do not include markdown fences around the JSON.
"""

        context_text = json.dumps(context[-30:], ensure_ascii=False)
        prompt = (
            f"User request:\n{request}\n\n"
            f"Detected project types: {', '.join(project_types) or 'unknown'}\n\n"
            f"Read project context:\n{context_text}"
        )

        raw = self.provider.generate(
            prompt,
            system=system,
            max_tokens=12000,
        )
        data = self._parse_json(raw)

        if not data or not isinstance(data.get("changes"), list):
            return []

        changes: list[FileChange] = []

        for item in data["changes"][:20]:
            if not isinstance(item, dict):
                continue

            path = str(item.get("path") or item.get("filePath") or "").strip()
            content = item.get("content")
            overwrite = bool(item.get("overwrite", False))

            if not path or not isinstance(content, str):
                continue

            # Defense-in-depth: the filesystem guard is still the final authority.
            if path.startswith("/") or path.startswith("\\"):
                continue
            if ".." in path.replace("\\", "/").split("/"):
                continue
            if len(content) > 2_000_000:
                continue

            changes.append(
                FileChange(
                    path=path,
                    content=content,
                    overwrite=overwrite,
                )
            )

        return changes

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
