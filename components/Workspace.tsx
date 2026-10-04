"use client";
import { useEffect, useRef, useState } from "react";
import Sidebar from "./Sidebar";
import ProjectHeader from "./ProjectHeader";
import PromptWorkspace from "./PromptWorkspace";
import FileExplorer from "./FileExplorer";
import CodeEditor from "./CodeEditor";
import RightPanel from "./RightPanel";
import { checkpointInitial, config, templates, type Status, type View } from "@/lib/mock";
import { focus, panel } from "@/lib/ui";

const defaults = Object.fromEntries(config.map((c) => [c.id, c.options[0]])) as Record<string, string>;
const START_FILE = "app/page.tsx";

export default function Workspace() {
  const [view, setView] = useState<View>("workspace");
  const [project, setProject] = useState("Untitled project");
  const [prompt, setPrompt] = useState("");
  const [error, setError] = useState(false);
  const [type, setType] = useState("Web App");
  const [cfg, setCfg] = useState<Record<string, string>>(defaults);
  const [status, setStatus] = useState<Status>("Ready");
  const [log, setLog] = useState<string[]>([]);
  const [selected, setSelected] = useState(START_FILE);
  const [expanded, setExpanded] = useState<Set<string>>(new Set(["app", "components"]));
  const [preview, setPreview] = useState(false);
  const [checkpoint, setCheckpoint] = useState(checkpointInitial);
  const [ckCount, setCkCount] = useState(0);
  const [ckNote, setCkNote] = useState("");
  const [nav, setNav] = useState(false);
  const [panelOpen, setPanelOpen] = useState(false);
  const [runId, setRunId] = useState<string | null>(null);
  const [approvalId, setApprovalId] = useState<string | null>(null);
  const [approvalTool, setApprovalTool] = useState<string | null>(null);
  const timers = useRef<ReturnType<typeof setTimeout>[]>([]);

  useEffect(() => {
    const list = timers.current;
    return () => list.forEach(clearTimeout);
  }, []);

  const clearTimers = () => {
    timers.current.forEach(clearTimeout);
    timers.current.length = 0;
  };

  const newProject = () => {
    clearTimers();
    setView("workspace"); setProject("Untitled project"); setPrompt(""); setError(false);
    setType("Web App"); setCfg(defaults); setStatus("Ready"); setLog([]);
    setSelected(START_FILE); setPreview(false); setCheckpoint(checkpointInitial);
    setCkCount(0); setCkNote("");
  };

  const openProject = (name: string) => {
    clearTimers(); setStatus("Ready"); setLog([]); setProject(name); setView("workspace");
  };

  const build = async () => {
    if (!prompt.trim()) { setError(true); return; }
    if (status !== "Ready") return;

    setError(false);
    clearTimers();
    setStatus("Planning");
    setLog(["Sending request to NEXORA Engine..."]);

    try {
      const response = await fetch("/api/engine/run", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          prompt: prompt,
          project_path: ".",
          verify: true,
        }),
      });

      if (!response.ok) {
        throw new Error(`Engine returned HTTP ${response.status}`);
      }

      const result = await response.json();

      const agentStatus = result.success ? "completed" : String(result.status ?? "failed");

      if (result.success) {
        setStatus("Ready");
      } else if (agentStatus === "waiting_for_approval") {
        setStatus("Building");
      } else {
        setStatus("Ready");
      }

      const nextLog = [
        `NEXORA Engine: ${agentStatus}`,
        result.response ?? result.summary ?? result.error ?? "Agent run completed.",
        ...(result.run_id ? [`Run ID: ${result.run_id}`] : []),
      ];

      if (result.pending_approval) {
        setRunId(result.run_id ? String(result.run_id) : null);
        setApprovalId(
          result.pending_approval.approval_id
            ? String(result.pending_approval.approval_id)
            : null
        );
        setApprovalTool(
          result.pending_approval.tool
            ? String(result.pending_approval.tool)
            : "filesystem operation"
        );
        nextLog.push(
          `Approval required: ${result.pending_approval.tool ?? "filesystem operation"}`
        );
      } else {
        setRunId(result.run_id ? String(result.run_id) : null);
        setApprovalId(null);
        setApprovalTool(null);
      }

      if (Array.isArray(result.verification_results)) {
        for (const verification of result.verification_results) {
          nextLog.push(
            `Verification: ${verification.passed === true ? "PASSED" : verification.passed === false ? "FAILED" : "NO CHECKS"} — ${verification.summary ?? ""}`
          );
        }
      }

      if (Array.isArray(result.errors)) {
        for (const message of result.errors) {
          nextLog.push(`Error: ${message}`);
        }
      }

      if (Array.isArray(result.tool_calls)) {
        nextLog.push(`Tools executed: ${result.tool_calls.length}`);
      }

      setLog(nextLog);
    } catch (err) {
      setStatus("Ready");
      setLog([
        "Could not connect to NEXORA Engine.",
        err instanceof Error ? err.message : "Unknown connection error.",
      ]);
    }
  };

  const decideApproval = async (approve: boolean) => {
    if (!approvalId || !runId) return;

    setStatus("Building");
    setLog((prev) => [
      ...prev,
      approve ? "Approval granted. Resuming NEXORA Engine..." : "Approval denied.",
    ]);

    try {
      const decision = await fetch(`/api/engine/approvals/${approvalId}/${approve ? "approve" : "deny"}`, {
        method: "POST",
      });

      if (!decision.ok) {
        throw new Error(`Approval request failed with HTTP ${decision.status}`);
      }

      if (!approve) {
        setApprovalId(null);
        setApprovalTool(null);
        setStatus("Ready");
        return;
      }

      const resumed = await fetch(`/api/engine/run/${runId}/resume`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ approval_id: approvalId }),
      });

      if (!resumed.ok) {
        throw new Error(`Resume request failed with HTTP ${resumed.status}`);
      }

      const result = await resumed.json();
      const agentStatus = String(result.status ?? "unknown");

      setStatus(agentStatus === "completed" || agentStatus === "failed" ? "Ready" : "Building");
      setApprovalId(
        result.pending_approval?.approval_id
          ? String(result.pending_approval.approval_id)
          : null
      );
      setApprovalTool(
        result.pending_approval?.tool
          ? String(result.pending_approval.tool)
          : null
      );

      setLog((prev) => [
        ...prev,
        `NEXORA Engine: ${agentStatus}`,
        result.summary ?? "Agent resumed.",
        ...(Array.isArray(result.errors)
          ? result.errors.map((message: string) => `Error: ${message}`)
          : []),
        ...(Array.isArray(result.verification_results)
          ? result.verification_results.map(
              (v: { passed?: boolean | null; summary?: string }) =>
                `Verification: ${v.passed === true ? "PASSED" : v.passed === false ? "FAILED" : "NO CHECKS"} — ${v.summary ?? ""}`
            )
          : []),
      ]);
    } catch (err) {
      setStatus("Ready");
      setLog((prev) => [
        ...prev,
        err instanceof Error ? err.message : "Approval/resume failed.",
      ]);
    }
  };

  const toggle = (p: string) =>
    setExpanded((prev) => {
      const n = new Set(prev);
      if (n.has(p)) n.delete(p); else n.add(p);
      return n;
    });

  const createCheckpoint = () => {
    const n = ckCount + 1;
    setCkCount(n);
    setCheckpoint({ name: `Manual checkpoint ${n} (UI only)`, status: "Saved" });
    setCkNote("");
  };

  return (
    <div className="flex h-dvh overflow-hidden bg-[#06080d] text-slate-200">
      <Sidebar
        view={view} project={project} open={nav} onClose={() => setNav(false)}
        onNew={newProject} onView={setView} onProject={openProject}
      />

      <div className="flex min-w-0 flex-1 flex-col">
        <ProjectHeader
          name={project} status={status} checkpoint={checkpoint.status} preview={preview}
          onMenu={() => setNav(true)} onPanel={() => setPanelOpen(true)}
          onPreview={() => { setView("workspace"); setPreview((p) => !p); }}
          onSettings={() => setView("settings")}
        />

        <main className="flex-1 overflow-y-auto p-3 sm:p-5">
          <div className="mx-auto max-w-5xl space-y-4">
            {view === "workspace" && (
              <>
                <PromptWorkspace
                  prompt={prompt} setPrompt={(v) => { setPrompt(v); setError(false); }} error={error}
                  type={type} setType={setType} cfg={cfg} setCfg={(id, v) => setCfg((c) => ({ ...c, [id]: v }))}
                  busy={status !== "Ready"} onBuild={build}
                />
                {preview ? (
                  <section className={`${panel} p-6 text-center text-sm text-slate-400`}>
                    <p className="font-medium text-slate-200">Preview is not available yet</p>
                    <p className="mt-1">No dev server is connected. This will show the running app in a later stage.</p>
                    <button onClick={() => setPreview(false)} className={`mt-4 rounded-lg border border-white/10 px-4 py-2.5 text-slate-300 hover:bg-white/5 ${focus}`}>
                      Back to editor
                    </button>
                  </section>
                ) : (
                  <div className="grid gap-3 md:grid-cols-[13rem_minmax(0,1fr)]">
                    <FileExplorer expanded={expanded} selected={selected} onToggle={toggle} onSelect={setSelected} />
                    <CodeEditor path={selected} />
                  </div>
                )}
              </>
            )}

            {view === "templates" && (
              <div className="space-y-3">
                <h2 className="text-xl font-semibold text-white">Templates</h2>
                <p className="text-sm text-slate-500">Choosing one fills the prompt box. Nothing is generated.</p>
                <ul className="grid gap-3 sm:grid-cols-2">
                  {templates.map((t) => (
                    <li key={t.name}>
                      <button
                        onClick={() => { setPrompt(t.prompt); setView("workspace"); }}
                        className={`${panel} w-full p-4 text-left hover:border-cyan-400/40 ${focus}`}
                      >
                        <p className="text-sm font-medium text-white">{t.name}</p>
                        <p className="mt-1 text-xs text-slate-500">{t.meta}</p>
                      </button>
                    </li>
                  ))}
                </ul>
              </div>
            )}

            {view === "settings" && (
              <div className="space-y-3">
                <h2 className="text-xl font-semibold text-white">Settings</h2>
                <div className={`${panel} p-4 text-sm text-slate-400`}>
                  Model gateway: not configured. It will connect through a server-side route in a later stage,
                  so no API keys ever live in the browser.
                </div>
              </div>
            )}
          </div>
        </main>
      </div>

      <RightPanel
        open={panelOpen} onClose={() => setPanelOpen(false)} log={log} checkpoint={checkpoint}
        note={ckNote} onCreate={createCheckpoint}
        onRestore={() => setCkNote("Restore is UI-only for now. Nothing was changed.")}
        approvalTool={approvalTool}
        onApprove={() => decideApproval(true)}
        onDeny={() => decideApproval(false)}
      />
    </div>
  );
}
