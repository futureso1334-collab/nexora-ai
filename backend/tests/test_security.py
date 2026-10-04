"""Pure-stdlib security tests (no FastAPI needed)."""
import os
import sys
import time

from app.config import DEFAULT_PROGRAMS
from app.security.command_policy import evaluate
from app.security.path_guard import PathEscapeError, PathGuard, PathGuardError, SecretPathError
from app.security.permissions import ApprovalError, ApprovalStore, Decision
from app.services.process import run_process, safe_env

ALLOWED = frozenset(DEFAULT_PROGRAMS) | {"rm", "sudo", "curl", "sh", "bash", "dd", "chmod", "shutdown", "reboot", "mkfs"}


def _ev(tmp_path, program, *args):
    guard = PathGuard(tmp_path)
    return evaluate(program, list(args), allowed=ALLOWED, guard=guard, cwd=guard.root)


def _raises(exc, fn, *a, **k):
    try:
        fn(*a, **k)
    except exc:
        return True
    return False


def test_path_traversal_rejected(tmp_path):
    g = PathGuard(tmp_path)
    for bad in ("../../etc/passwd", "../x", "a/../../x", "a/b/../../../x"):
        assert _raises(PathEscapeError, g.resolve, bad), bad


def test_absolute_and_home_paths_rejected(tmp_path):
    g = PathGuard(tmp_path)
    for bad in ("/etc/passwd", "~/x", "C:\\x"):
        assert _raises(PathEscapeError, g.resolve, bad), bad
    assert _raises(PathGuardError, g.resolve, "a\x00b")


def test_workspace_restriction_allows_inside(tmp_path):
    g = PathGuard(tmp_path)
    p = g.resolve("src/deep/file.txt")
    assert p.is_relative_to(g.root) and g.rel(p) == "src/deep/file.txt"
    assert g.resolve("a/../b.txt") == g.root / "b.txt"  # stays inside after normalisation
    assert g.resolve("") == g.root


def test_symlink_escape_rejected(tmp_path):
    outside = tmp_path / "outside"
    outside.mkdir()
    (outside / "secret.txt").write_text("x")
    root = tmp_path / "ws"
    root.mkdir()
    try:
        os.symlink(outside, root / "link")
    except (OSError, NotImplementedError):
        return  # platform without symlinks
    assert _raises(PathEscapeError, PathGuard(root).resolve, "link/secret.txt")


def test_secret_files_and_git_protected(tmp_path):
    g = PathGuard(tmp_path)
    assert _raises(SecretPathError, g.resolve, ".env")
    assert _raises(SecretPathError, g.resolve, "keys/server.pem")
    assert g.resolve(".env.example")
    assert _raises(PathGuardError, g.resolve, ".git/config", for_write=True)


def test_allowlisted_commands(tmp_path):
    assert _ev(tmp_path, "python", "--version").decision is Decision.ALLOW
    assert _ev(tmp_path, "python", "-m", "pytest", "-q").decision is Decision.ALLOW
    assert _ev(tmp_path, "pytest").decision is Decision.ALLOW
    assert _ev(tmp_path, "npm", "run", "build").decision is Decision.ALLOW
    assert _ev(tmp_path, "npm", "test").decision is Decision.ALLOW
    assert _ev(tmp_path, "git", "status").decision is Decision.ALLOW
    assert _ev(tmp_path, "node", "--version").decision is Decision.ALLOW


def test_approval_required_commands(tmp_path):
    for cmd in (("npm", "install"), ("npm", "run", "deploy"), ("npx", "create-foo"), ("git", "commit", "-m", "x"),
                ("python", "script.py"), ("node", "build.js")):
        assert _ev(tmp_path, *cmd).decision is Decision.REQUIRE_APPROVAL, cmd


def test_dangerous_commands_rejected_even_if_allowlisted(tmp_path):
    for cmd in (("rm", "-rf", "x"), ("sudo", "ls"), ("curl", "http://x"), ("sh", "-c", "x"), ("bash",), ("dd", "if=a"),
                ("chmod", "-R", "777", "."), ("shutdown",), ("reboot",), ("mkfs", "x"), ("/bin/rm", "x")):
        assert _ev(tmp_path, *cmd).decision is Decision.DENY, cmd


def test_dangerous_subcommands_and_options_rejected(tmp_path):
    for cmd in (("python", "-c", "print(1)"), ("python", "-m", "pip", "install", "x"), ("node", "-e", "1"),
                ("git", "push"), ("git", "clone", "x"), ("git", "-c", "a=b", "status"), ("npm", "publish"),
                ("npm", "exec", "x"), ("npm", "run", "build", "-g")):
        assert _ev(tmp_path, *cmd).decision is Decision.DENY, cmd


def test_unlisted_program_rejected(tmp_path):
    assert _ev(tmp_path, "ls").decision is Decision.DENY


def test_argument_path_escapes_rejected(tmp_path):
    for cmd in (("pytest", "/etc/passwd"), ("pytest", "../.."), ("npm", "run", "build", "--prefix=../.."),
                ("pytest", "~/x"), ("pytest", ".env")):
        assert _ev(tmp_path, *cmd).decision is Decision.DENY, cmd
    assert _ev(tmp_path, "pytest", "tests/test_a.py::test_x").decision is Decision.ALLOW


def test_command_timeout_kills_process(tmp_path):
    t0 = time.time()
    out = run_process([sys.executable, "-c", "import time; time.sleep(10)"], tmp_path, 0.5, 1000)
    assert out.timed_out and out.exit_code is None
    assert time.time() - t0 < 5


def test_process_captures_output_and_exit_code(tmp_path):
    out = run_process([sys.executable, "-c", "import sys; print('hi'); sys.stderr.write('e'); sys.exit(3)"], tmp_path, 10, 1000)
    assert (out.exit_code, out.stdout.strip(), out.stderr.strip(), out.timed_out) == (3, "hi", "e", False)
    assert out.duration_ms >= 0


def test_child_env_excludes_secrets():
    os.environ["NEXORA_TEST_SECRET_TOKEN"] = "super-secret-value-123"
    try:
        assert "NEXORA_TEST_SECRET_TOKEN" not in safe_env()
        import tempfile
        from pathlib import Path
        with tempfile.TemporaryDirectory() as d:
            out = run_process([sys.executable, "-c", "print('super-secret-value-123')"], Path(d), 10, 1000)
        assert "super-secret-value-123" not in out.stdout and "[REDACTED]" in out.stdout
    finally:
        del os.environ["NEXORA_TEST_SECRET_TOKEN"]


def test_approval_store_binding_single_use_and_expiry():
    s = ApprovalStore(ttl_s=60)
    a = s.request("filesystem.delete", {"path": "a.txt"}, "needs approval")
    assert not s.consume(a.id, "filesystem.delete", {"path": "a.txt"})  # not approved yet
    s.approve(a.id)
    assert not s.consume(a.id, "filesystem.delete", {"path": "other.txt"})  # different args
    assert s.consume(a.id, "filesystem.delete", {"path": "a.txt"})
    assert not s.consume(a.id, "filesystem.delete", {"path": "a.txt"})  # single use
    expired = ApprovalStore(ttl_s=-1)
    b = expired.request("t", {}, "r")
    assert _raises(ApprovalError, expired.approve, b.id)
    assert _raises(ApprovalError, s.approve, "apr_missing")
