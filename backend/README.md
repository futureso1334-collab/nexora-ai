# NEXORA Engine V1 (backend)

A small, security-first FastAPI foundation for the NEXORA software-engineering agent.
**Engine V1 does not call any language model, generate code, fix errors or create checkpoints.**
It provides the safe tool layer, the approval system, a deterministic planner and the agent loop
skeleton (plan, execute, observe, verify) that those features will plug into.

## Architecture
```
routes/ (FastAPI, /api/v1)  ->  Agent (planner, executor, observer, verifier, state)
                                     |
                              ToolRegistry  (validate -> policy -> approval gate -> handler -> activity event)
                                     |
        filesystem.* | project.inspect | command.run | test.run
                                     |
        security/: path_guard · permissions (+ApprovalStore) · command_policy      services/process.py (no shell)
```
The agent only reaches the system through `ToolRegistry.execute`. `ModelProvider` (agent/provider.py) is
the seam for FreeLLMAPI; only a `MockProvider` exists.

## Install (Termux)
```bash
cd backend
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements-dev.txt     # runtime only: requirements.txt
```
Pydantic needs a native extension. If no wheel exists for your Python/Android combination, pip builds it
from source: `pkg install rust binutils` and `export ANDROID_API_LEVEL=$(getprop ro.build.version.sdk)` first.

## Run
```bash
cd backend && source .venv/bin/activate
uvicorn app.main:create_app --factory --host 127.0.0.1 --port 8000
```
Docs: http://127.0.0.1:8000/docs. Keep it on 127.0.0.1: V1 has no authentication.

## Configuration (environment, see `.env.example`)
`NEXORA_WORKSPACE_ROOT` (default `<repo>/workspace`; refuses `/` and `$HOME`), `NEXORA_CORS_ORIGINS`,
`NEXORA_ALLOWED_PROGRAMS`, `NEXORA_COMMAND_TIMEOUT_S`, `NEXORA_LOG_LEVEL`. No API keys are needed or stored.

## Endpoints
`GET /health` · `GET /api/v1/project/inspect` · `POST /api/v1/project/{read,write,search}` ·
`POST /api/v1/agent/plan|run` · `GET /api/v1/agent/runs/{id}` · `POST /api/v1/agent/runs/{id}/resume` ·
`GET /api/v1/tools` · `POST /api/v1/tools/execute` · `GET /api/v1/activity` ·
`GET /api/v1/approvals` · `POST /api/v1/approvals/{id}/approve|deny`

Tool responses share one envelope (`status`: success | error | denied | approval_required, `exit_code`,
`stdout`, `stderr`, `duration_ms`, `timestamp`, `approval_id`). HTTP: denied 403, approval_required 428.

## Security model
- **Workspace confinement:** every path resolves inside the workspace root; `..`, absolute paths, `~`, and
  symlink escapes are rejected; secret files (`.env*`, keys) are blocked; `.git` is write-protected.
- **Permissions:** READ/WRITE allowed in workspace; DELETE and DEPLOY need approval; EXECUTE only via the command
  policy; NETWORK and SECRET_ACCESS are blocked.
- **Commands:** structured `{program, args[]}`, never a shell. Bare program names only; a deny-list (rm, sudo, curl,
  sh, dd, chmod, ...) wins even if allowlisted; path arguments must stay in the workspace; per-program subcommand
  rules (e.g. `git push`, `python -c`, `node -e`, `npm publish` denied; `npm install`, running scripts need approval).
  Timeout kills the whole process group; output is capped; child env is a minimal allowlist; secret values are redacted.
- **Approvals:** bound to the exact tool and arguments, single-use, expiring. Only the approvals API grants them.
  Known limitation: no authentication yet, and running tests/scripts executes workspace code by nature.

## Tests
```bash
cd backend && source .venv/bin/activate && pytest
```

## Next: FreeLLMAPI
Add `FreeLLMAPIProvider(ModelProvider)` that calls your gateway server-side (key from env), then an `LLMPlanner`
returning the same `AgentPlan`, then an apply/fix loop and checkpoints.
