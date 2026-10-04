"""NEXORA model providers.

The FreeLLMAPI provider uses LangChain's OpenAI-compatible client.
Secrets are read from environment variables and never exposed to the frontend.
"""
from abc import ABC, abstractmethod
import os

from dotenv import load_dotenv
from langchain_openai import ChatOpenAI

load_dotenv()


class ModelProvider(ABC):
    name: str = "base"

    @abstractmethod
    def generate(
        self,
        prompt: str,
        *,
        system: str | None = None,
        max_tokens: int = 1024,
    ) -> str:
        """Return model text for a prompt."""


class MockProvider(ModelProvider):
    """Local placeholder used by tests."""

    name = "mock"

    def generate(
        self,
        prompt: str,
        *,
        system: str | None = None,
        max_tokens: int = 1024,
    ) -> str:
        return f"[mock provider] no language model is connected (received {len(prompt)} characters)."


class FreeLLMAPIProvider(ModelProvider):
    """OpenAI-compatible FreeLLMAPI provider used by the real NEXORA runtime."""

    name = "freellmapi"

    def __init__(self) -> None:
        api_key = os.getenv("FREELLMAPI_API_KEY")
        base_url = os.getenv("FREELLMAPI_BASE_URL")

        if not api_key:
            raise RuntimeError("FREELLMAPI_API_KEY is not configured")
        if not base_url:
            raise RuntimeError("FREELLMAPI_BASE_URL is not configured")

        self.model = "qwen3-coder-480b"
        self.client = ChatOpenAI(
            model=self.model,
            api_key=api_key,
            base_url=base_url,
            max_tokens=1024,
        )

    def generate(
        self,
        prompt: str,
        *,
        system: str | None = None,
        max_tokens: int = 1024,
    ) -> str:
        messages = []

        if system:
            messages.append(("system", system))

        messages.append(("human", prompt))

        client = self.client.bind(max_tokens=max_tokens)
        response = client.invoke(messages)

        content = response.content
        text = content if isinstance(content, str) else str(content)

        finish_reason = response.response_metadata.get("finish_reason")
        if finish_reason == "length":
            raise RuntimeError(
                "FreeLLMAPI truncated the response (finish_reason=length). "
                "Retry with a shorter prompt or a route that supports longer outputs."
            )

        if not text.strip():
            raise RuntimeError("FreeLLMAPI returned an empty response.")

        return text
