import json


def tool(client, name, arguments, approval_id=None):
    return client.post("/api/v1/tools/execute", json={"tool": name, "arguments": arguments, "approval_id": approval_id})


def test_health(client):
    r = client.get("/health")
    assert r.status_code == 200
    assert r.json()["status"] == "ok" and r.json()["service"] == "nexora-engine"


def test_file_write_read_roundtrip(client, ws):
    r = client.post("/api/v1/project/write", json={"path": "src/hello.txt", "content": "hi there"})
    assert r.status_code == 200 and r.json()["data"]["created"] is True
    assert (ws / "src" / "hello.txt").read_text() == "hi there"
    r = client.post("/api/v1/project/read", json={"path": "src/hello.txt"})
    assert r.json()["data"]["content"] == "hi there"
    again = client.post("/api/v1/project/write", json={"path": "src/hello.txt", "content": "x"})
    assert again.status_code == 400  # exists, overwrite not requested


def test_edit_file(client, ws):
    (ws / "a.txt").write_text("one two two")
    ambiguous = tool(client, "filesystem.edit", {"path": "a.txt", "old": "two", "new": "2"})
    assert ambiguous.status_code == 400
    r = tool(client, "filesystem.edit", {"path": "a.txt", "old": "one", "new": "1"})
    assert r.status_code == 200 and (ws / "a.txt").read_text() == "1 two two"


def test_directory_listing(client, ws):
    (ws / "d").mkdir()
    (ws / "f.txt").write_text("x")
    r = tool(client, "filesystem.list", {"path": "."})
    assert {(e["name"], e["type"]) for e in r.json()["data"]["entries"]} == {("d", "dir"), ("f.txt", "file")}


def test_file_search(client, ws):
    (ws / "src").mkdir()
    (ws / "src" / "a.py").write_text("x = 1\nneedle = 2\n")
    r = client.post("/api/v1/project/search", json={"query": "needle"})
    m = r.json()["data"]["matches"]
    assert m and m[0]["path"] == "src/a.py" and m[0]["line"] == 2


def test_path_traversal_blocked_via_api(client, ws):
    for bad in ("../../etc/passwd", "/etc/passwd", "..", "a/../../x"):
        r = client.post("/api/v1/project/read", json={"path": bad})
        assert r.status_code == 403 and r.json()["status"] == "denied", bad
    r = client.post("/api/v1/project/write", json={"path": "../evil.txt", "content": "x"})
    assert r.status_code == 403
    assert not (ws.parent / "evil.txt").exists()


def test_secret_files_blocked(client, ws):
    (ws / ".env").write_text("KEY=abc")
    assert client.post("/api/v1/project/read", json={"path": ".env"}).status_code == 403
    assert client.post("/api/v1/project/write", json={"path": ".env", "content": "x", "overwrite": True}).status_code == 403


def test_delete_requires_approval(client, ws):
    f = ws / "victim.txt"
    f.write_text("keep me")
    r = tool(client, "filesystem.delete", {"path": "victim.txt"})
    assert r.status_code == 428 and r.json()["status"] == "approval_required"
    assert f.exists()  # nothing was deleted
    apr = r.json()["approval_id"]
    # wrong approval id / unapproved id must not work
    assert tool(client, "filesystem.delete", {"path": "victim.txt"}, apr).status_code == 428
    assert f.exists()
    assert client.post(f"/api/v1/approvals/{apr}/approve").status_code == 200
    # an approval for victim.txt cannot authorise a different path
    (ws / "other.txt").write_text("x")
    assert tool(client, "filesystem.delete", {"path": "other.txt"}, apr).status_code == 428
    assert (ws / "other.txt").exists()
    assert tool(client, "filesystem.delete", {"path": "victim.txt"}, apr).status_code == 200
    assert not f.exists()
    assert tool(client, "filesystem.delete", {"path": "victim.txt"}, apr).status_code == 428  # single use


def test_command_allowlist_and_rejection_via_api(client):
    r = tool(client, "command.run", {"program": "python", "args": ["--version"]})
    assert r.status_code == 200 and r.json()["exit_code"] == 0 and "Python" in r.json()["stdout"]
    for prog, args in (("rm", ["-rf", "x"]), ("curl", ["http://example.com"]), ("sh", ["-c", "id"]), ("ls", [])):
        r = tool(client, "command.run", {"program": prog, "args": args})
        assert r.status_code == 403 and r.json()["status"] == "denied", prog
    assert tool(client, "command.run", {"program": "npx", "args": ["cowsay"]}).status_code == 428


def test_command_timeout_end_to_end(client, ws):
    (ws / "sleep.py").write_text("import time\ntime.sleep(30)\n")
    r = tool(client, "command.run", {"program": "python", "args": ["sleep.py"]})
    assert r.status_code == 428  # running workspace scripts needs approval
    apr = r.json()["approval_id"]
    client.post(f"/api/v1/approvals/{apr}/approve")
    r = tool(client, "command.run", {"program": "python", "args": ["sleep.py"]}, apr)
    body = r.json()
    assert body["data"]["timed_out"] is True and body["success"] is False and "timed out" in body["error"]


def test_structured_tool_result(client):
    body = tool(client, "command.run", {"program": "python", "args": ["--version"]}).json()
    for key in ("tool", "success", "status", "exit_code", "stdout", "stderr", "duration_ms", "timestamp"):
        assert key in body
    assert body["tool"] == "command.run" and body["status"] == "success"
    assert isinstance(tool(client, "nope.tool", {}).json()["error"], str)
    assert any(t["name"] == "filesystem.read" and t["permission"] == "read" for t in client.get("/api/v1/tools").json()["tools"])


def test_activity_events(client):
    tool(client, "filesystem.list", {"path": "."})
    ev = client.get("/api/v1/activity").json()["events"][-1]
    assert {"tool", "status", "timestamp", "duration_ms"} <= ev.keys() and ev["tool"] == "filesystem.list"


def test_project_inspection(client, ws):
    (ws / "package.json").write_text(json.dumps({"dependencies": {"next": "16", "react": "19"}, "scripts": {"build": "next build --webpack"}}))
    (ws / "app").mkdir()
    (ws / "app" / "page.tsx").write_text("export default function P(){return null}")
    d = client.get("/api/v1/project/inspect").json()["data"]
    assert "nextjs" in d["types"] and "react" in d["types"]
    assert d["scripts"]["build"] == "next build --webpack" and "app/page.tsx" in d["tree"]


def test_inspection_detects_fastapi_and_generic(client, ws):
    assert client.get("/api/v1/project/inspect").json()["data"]["types"] == ["generic"]
    (ws / "requirements.txt").write_text("fastapi\n")
    assert client.get("/api/v1/project/inspect").json()["data"]["types"] == ["fastapi", "python"]


def test_agent_planning(client):
    r = client.post("/api/v1/agent/plan", json={"request": "Create a landing page"})
    assert r.status_code == 200
    plan = r.json()
    assert plan["planner"] == "deterministic" and len(plan["steps"]) >= 7
    assert [s["id"] for s in plan["steps"]][0] == "inspect"
    assert any(s["kind"] == "unsupported" and "model provider" in s["note"] for s in plan["steps"])


def test_agent_plan_rejects_escape(client):
    r = client.post("/api/v1/agent/plan", json={"request": "x", "project_path": "../.."})
    assert r.status_code == 403


def test_agent_run_with_real_verification(client, ws):
    (ws / "tests").mkdir()
    (ws / "tests" / "test_ok.py").write_text("def test_ok():\n    assert 1 + 1 == 2\n")
    r = client.post("/api/v1/agent/run", json={"request": "check this project"})
    state = r.json()
    assert state["status"] == "completed", state
    assert state["verification_results"][0]["passed"] is True
    assert state["tool_calls"] and state["tool_calls"][0]["result"]["tool"] == "project.inspect"
    assert client.get(f"/api/v1/agent/runs/{state['run_id']}").json()["run_id"] == state["run_id"]


def test_agent_run_reports_failed_verification(client, ws):
    (ws / "tests").mkdir()
    (ws / "tests" / "test_bad.py").write_text("def test_bad():\n    assert False\n")
    state = client.post("/api/v1/agent/run", json={"request": "check"}).json()
    assert state["status"] == "failed" and state["verification_results"][0]["passed"] is False
    assert "not implemented" in state["errors"][0]


def test_agent_run_with_nothing_to_verify(client):
    state = client.post("/api/v1/agent/run", json={"request": "hello"}).json()
    assert state["status"] == "completed" and state["verification_results"][0]["passed"] is None
    assert "no file edits" in state["summary"]
