from ..tools.base import ToolResult
from .models import VerificationResult


class Verifier:
    def interpret(self, result: ToolResult) -> VerificationResult:
        rows = result.data.get("results", []) if result.data else []
        checks = [{"check": r["check"], "passed": r["passed"], "exit_code": r["exit_code"]} for r in rows]
        if not checks:
            return VerificationResult(passed=None, checks=[], summary=result.error or "No verification commands were available.")
        failed = [c["check"] for c in checks if not c["passed"]]
        return VerificationResult(passed=not failed, checks=checks,
                                  summary="All checks passed." if not failed else "Failed: " + ", ".join(failed))
