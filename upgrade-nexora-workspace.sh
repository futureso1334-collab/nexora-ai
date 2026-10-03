#!/usr/bin/env bash
# NEXORA AI - workspace UI upgrade (frontend only, mock data, no backend).
# Run from the project root:  bash upgrade-nexora-workspace.sh
# Installs no packages. Does not touch app/, package.json, tsconfig or the build script.
# Existing files it replaces are backed up as <file>.bak (kept if a .bak already exists).
set -e

if [ ! -f package.json ] || ! grep -q '"next"' package.json; then
  echo "ERROR: run from the NEXORA project root."; exit 1
fi
if [ ! -d app ] || [ ! -d components ] || [ ! -d lib ]; then
  echo "ERROR: expected app/, components/ and lib/ (run the earlier shell installer first)."; exit 1
fi
grep -q '"build"[^,]*--webpack' package.json || \
  echo "WARNING: your build script does not contain --webpack. Not changing it; check package.json."

USE_ALIAS=0
if [ -f tsconfig.json ] && tr -d ' \t\r\n' < tsconfig.json | grep -q '"@/\*":\["\./\*"\]'; then USE_ALIAS=1; fi

FILES="lib/mock.ts lib/ui.ts components/Sidebar.tsx components/ProjectHeader.tsx components/PromptWorkspace.tsx components/FileExplorer.tsx components/CodeEditor.tsx components/RightPanel.tsx components/Workspace.tsx"
for f in $FILES; do
  if [ -f "$f" ] && [ ! -f "$f.bak" ]; then cp "$f" "$f.bak"; echo "Backed up $f -> $f.bak"; fi
done

# ---------------- lib/ui.ts ----------------
cat > lib/ui.ts <<'EOF'
export const focus =
  "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-cyan-400/70";
export const panel = "rounded-xl border border-white/10 bg-white/[0.03]";
EOF

# ---------------- lib/mock.ts ----------------
cat > lib/mock.ts <<'EOF'
// Local mock data only. Nothing here comes from an agent, API or database.
export type View = "workspace" | "templates" | "settings";
export type Status = "Ready" | "Planning" | "Building" | "Testing";
export type StepState = "done" | "active" | "pending";
export type TreeNode = { name: string; path: string; children?: TreeNode[] };

export const projects = ["My Website", "AI Dashboard", "Mobile App"];
export const recent = ["E-commerce platform", "SaaS dashboard", "Portfolio website"];

export const examples = [
  "A task manager with teams, due dates and a kanban board",
  "A SaaS landing page with pricing and a waitlist form",
  "A REST API for a bookstore with tests",
];

export const projectTypes = ["Web App", "Mobile App", "API", "Full Stack", "Other"];

export const config = [
  { id: "framework", label: "Framework", options: ["Next.js", "React + Vite", "Express", "Expo"] },
  { id: "language", label: "Language", options: ["TypeScript", "JavaScript", "Python"] },
  { id: "database", label: "Database", options: ["None", "PostgreSQL", "SQLite", "MongoDB"] },
  { id: "styling", label: "Styling", options: ["Tailwind CSS", "CSS Modules", "Plain CSS"] },
  { id: "deployment", label: "Deployment", options: ["Not decided", "Vercel", "Docker", "Static host"] },
];

export const activity: { label: string; state: StepState }[] = [
  { label: "Understanding request", state: "done" },
  { label: "Creating project plan", state: "done" },
  { label: "Generating components", state: "active" },
  { label: "Running tests", state: "pending" },
  { label: "Checking errors", state: "pending" },
  { label: "Creating checkpoint", state: "pending" },
];

export const plan = [
  "Analyze requirements",
  "Design architecture",
  "Create application structure",
  "Generate components",
  "Configure dependencies",
  "Run tests",
  "Fix errors",
  "Verify project",
  "Create checkpoint",
];

export const verification = [
  { name: "TypeScript", result: "Passed" },
  { name: "Lint", result: "Passed" },
  { name: "Build", result: "Passed" },
];

export const checkpointInitial = { name: "Initial frontend shell", status: "Saved" };

export const templates = [
  { name: "SaaS starter", meta: "Dashboard layout, pricing, settings", prompt: "A SaaS starter with a dashboard, pricing page and settings" },
  { name: "REST API + tests", meta: "Routes, validation, test suite", prompt: "A REST API with input validation and a test suite" },
  { name: "Portfolio site", meta: "Projects, about, contact", prompt: "A personal portfolio site with projects, about and contact sections" },
  { name: "Admin dashboard", meta: "Charts, tables, filters", prompt: "An admin dashboard with charts, tables and filters" },
];

export const tree: TreeNode[] = [
  {
    name: "app", path: "app",
    children: [
      { name: "page.tsx", path: "app/page.tsx" },
      { name: "layout.tsx", path: "app/layout.tsx" },
      { name: "globals.css", path: "app/globals.css" },
    ],
  },
  {
    name: "components", path: "components",
    children: [
      { name: "Navbar.tsx", path: "components/Navbar.tsx" },
      { name: "Hero.tsx", path: "components/Hero.tsx" },
    ],
  },
  { name: "lib", path: "lib", children: [] },
  { name: "public", path: "public", children: [] },
  { name: "package.json", path: "package.json" },
  { name: "README.md", path: "README.md" },
];

export const files: Record<string, { lang: string; code: string }> = {
  "app/page.tsx": {
    lang: "TypeScript React",
    code: `import Navbar from "@/components/Navbar";
import Hero from "@/components/Hero";

export default function Page() {
  return (
    <main>
      <Navbar />
      <Hero title="My Website" />
    </main>
  );
}`,
  },
  "app/layout.tsx": {
    lang: "TypeScript React",
    code: `import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = { title: "My Website" };

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}`,
  },
  "app/globals.css": {
    lang: "CSS",
    code: `@import "tailwindcss";

body {
  background: #07090f;
  color: #e2e8f0;
}`,
  },
  "components/Navbar.tsx": {
    lang: "TypeScript React",
    code: `const links = ["Home", "About", "Contact"];

export default function Navbar() {
  return (
    <nav className="flex gap-4 p-4">
      {links.map((l) => (
        <a key={l} href="#" className="text-sm text-slate-300">
          {l}
        </a>
      ))}
    </nav>
  );
}`,
  },
  "components/Hero.tsx": {
    lang: "TypeScript React",
    code: `type HeroProps = { title: string };

export default function Hero({ title }: HeroProps) {
  // Sample component shown in the NEXORA editor mock
  return (
    <section className="p-8">
      <h1 className="text-3xl font-semibold">{title}</h1>
    </section>
  );
}`,
  },
  "package.json": {
    lang: "JSON",
    code: `{
  "name": "my-project",
  "private": true,
  "scripts": {
    "dev": "next dev",
    "build": "next build --webpack"
  }
}`,
  },
  "README.md": {
    lang: "Markdown",
    code: `# my-project

Sample project shown in the NEXORA file explorer.
This content is mock data.`,
  },
};
EOF

# ---------------- components/Sidebar.tsx ----------------
cat > components/Sidebar.tsx <<'EOF'
"use client";
import { projects, recent, type View } from "@/lib/mock";
import { focus } from "@/lib/ui";

function Item({ label, active, onClick }: { label: string; active?: boolean; onClick: () => void }) {
  return (
    <button
      onClick={onClick}
      aria-current={active ? "page" : undefined}
      className={`w-full truncate rounded-lg px-3 py-2.5 text-left text-sm transition ${focus} ${
        active ? "bg-white/10 text-white" : "text-slate-400 hover:bg-white/5 hover:text-white"
      }`}
    >
      {label}
    </button>
  );
}

function Heading({ children }: { children: React.ReactNode }) {
  return <h2 className="px-3 pb-1 text-[11px] font-medium uppercase tracking-wider text-slate-500">{children}</h2>;
}

export default function Sidebar({
  view, project, open, onClose, onNew, onView, onProject,
}: {
  view: View; project: string; open: boolean; onClose: () => void;
  onNew: () => void; onView: (v: View) => void; onProject: (name: string) => void;
}) {
  const pick = (fn: () => void) => () => { fn(); onClose(); };
  return (
    <>
      {open && <div className="fixed inset-0 z-30 bg-black/60 lg:hidden" onClick={onClose} aria-hidden="true" />}
      <aside
        aria-label="Primary"
        className={`fixed inset-y-0 left-0 z-40 flex w-64 flex-col gap-5 overflow-y-auto border-r border-white/10 bg-[#080b12] p-4 transition-transform lg:static lg:translate-x-0 ${
          open ? "translate-x-0" : "-translate-x-full"
        }`}
      >
        <div className="flex items-center justify-between px-1">
          <div className="flex items-center gap-2.5">
            <div className="grid h-8 w-8 place-items-center rounded-lg bg-gradient-to-br from-cyan-400 to-blue-600 text-sm font-bold text-white">N</div>
            <span className="text-base font-semibold tracking-[0.2em] text-white">NEXORA</span>
          </div>
          <button onClick={onClose} aria-label="Close menu" className={`rounded-lg px-2 py-1 text-slate-400 hover:text-white lg:hidden ${focus}`}>✕</button>
        </div>

        <button
          onClick={pick(onNew)}
          className={`rounded-lg border border-cyan-400/30 bg-cyan-400/10 px-3 py-2.5 text-left text-sm font-medium text-cyan-100 hover:bg-cyan-400/15 ${focus}`}
        >
          + New Project
        </button>

        <nav aria-label="Projects" className="space-y-1">
          <Heading>Projects</Heading>
          {projects.map((p) => (
            <Item key={p} label={p} active={view === "workspace" && p === project} onClick={pick(() => onProject(p))} />
          ))}
        </nav>
        <nav aria-label="Recent" className="space-y-1">
          <Heading>Recent</Heading>
          {recent.map((p) => (
            <Item key={p} label={p} active={view === "workspace" && p === project} onClick={pick(() => onProject(p))} />
          ))}
        </nav>
        <nav aria-label="More" className="mt-auto space-y-1">
          <Item label="Templates" active={view === "templates"} onClick={pick(() => onView("templates"))} />
          <Item label="Settings" active={view === "settings"} onClick={pick(() => onView("settings"))} />
          <p className="px-3 pt-2 text-xs text-slate-600">UI prototype · mock data</p>
        </nav>
      </aside>
    </>
  );
}
EOF

# ---------------- components/ProjectHeader.tsx ----------------
cat > components/ProjectHeader.tsx <<'EOF'
"use client";
import type { Status } from "@/lib/mock";
import { focus } from "@/lib/ui";

const tone: Record<Status, string> = {
  Ready: "bg-emerald-400",
  Planning: "bg-amber-400",
  Building: "bg-cyan-400",
  Testing: "bg-violet-400",
};

const btn = `rounded-lg border border-white/10 px-3 py-2 text-sm text-slate-300 hover:bg-white/5 hover:text-white ${focus}`;

export default function ProjectHeader({
  name, status, checkpoint, preview, onMenu, onPanel, onPreview, onSettings,
}: {
  name: string; status: Status; checkpoint: string; preview: boolean;
  onMenu: () => void; onPanel: () => void; onPreview: () => void; onSettings: () => void;
}) {
  return (
    <header className="flex items-center gap-2 border-b border-white/10 bg-[#080b12]/80 px-3 py-2.5 sm:px-5">
      <button onClick={onMenu} aria-label="Open menu" className={`${btn} lg:hidden`}>☰</button>
      <div className="min-w-0 flex-1">
        <h1 className="truncate text-sm font-semibold text-white">{name}</h1>
        <p className="flex items-center gap-1.5 text-xs text-slate-400" role="status">
          <span className={`h-2 w-2 rounded-full ${tone[status]} ${status === "Ready" ? "" : "animate-pulse"}`} aria-hidden="true" />
          {status}
        </p>
      </div>
      <span className="hidden items-center gap-1.5 text-xs text-slate-400 md:flex">
        <span className="h-2 w-2 rounded-full bg-slate-500" aria-hidden="true" />
        Checkpoint: {checkpoint}
      </span>
      <button onClick={onPreview} aria-pressed={preview} className={`${btn} ${preview ? "bg-white/10 text-white" : ""}`}>Preview</button>
      <button onClick={onPanel} className={`${btn} xl:hidden`}>Activity</button>
      <button onClick={onSettings} aria-label="Settings" className={btn}>⚙</button>
    </header>
  );
}
EOF

# ---------------- components/PromptWorkspace.tsx ----------------
cat > components/PromptWorkspace.tsx <<'EOF'
"use client";
import { config, examples, projectTypes } from "@/lib/mock";
import { focus, panel } from "@/lib/ui";

export default function PromptWorkspace({
  prompt, setPrompt, error, type, setType, cfg, setCfg, busy, onBuild,
}: {
  prompt: string; setPrompt: (v: string) => void; error: boolean;
  type: string; setType: (v: string) => void;
  cfg: Record<string, string>; setCfg: (id: string, v: string) => void;
  busy: boolean; onBuild: () => void;
}) {
  return (
    <section aria-labelledby="prompt-h" className={`${panel} space-y-4 p-4`}>
      <h2 id="prompt-h" className="text-lg font-semibold text-white">What do you want to build?</h2>

      <div>
        <label htmlFor="prompt" className="sr-only">Project description</label>
        <textarea
          id="prompt"
          value={prompt}
          onChange={(e) => setPrompt(e.target.value)}
          rows={4}
          aria-invalid={error}
          placeholder="Describe the application you want NEXORA to build..."
          className={`w-full resize-y rounded-lg border bg-black/20 p-3 text-base text-slate-100 placeholder:text-slate-500 ${focus} ${
            error ? "border-red-400/70" : "border-white/10"
          }`}
        />
        {error && <p className="mt-1 text-xs text-red-300">Describe what you want to build first.</p>}
      </div>

      <div className="flex flex-wrap gap-2">
        {examples.map((e) => (
          <button key={e} onClick={() => setPrompt(e)} className={`rounded-full border border-white/10 px-3 py-1.5 text-left text-xs text-slate-300 hover:border-cyan-400/40 hover:text-white ${focus}`}>
            {e}
          </button>
        ))}
      </div>

      <div role="radiogroup" aria-label="Project type" className="flex flex-wrap gap-2">
        {projectTypes.map((t) => (
          <button
            key={t} role="radio" aria-checked={type === t} onClick={() => setType(t)}
            className={`rounded-lg px-3 py-2 text-sm ${focus} ${
              type === t ? "bg-cyan-400/15 text-cyan-100 ring-1 ring-cyan-400/40" : "border border-white/10 text-slate-300 hover:bg-white/5"
            }`}
          >
            {t}
          </button>
        ))}
      </div>

      <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-5">
        {config.map((c) => (
          <label key={c.id} className="block text-xs text-slate-400">
            {c.label}
            <select
              value={cfg[c.id]}
              onChange={(e) => setCfg(c.id, e.target.value)}
              className={`mt-1 w-full rounded-lg border border-white/10 bg-[#0b0f19] px-2 py-2.5 text-sm text-slate-200 ${focus}`}
            >
              {c.options.map((o) => <option key={o}>{o}</option>)}
            </select>
          </label>
        ))}
      </div>

      <div className="flex items-center justify-between gap-3">
        <p className="text-xs text-slate-500">Frontend demo: nothing is generated yet.</p>
        <button
          onClick={onBuild}
          disabled={busy}
          className={`flex items-center gap-2 rounded-lg bg-gradient-to-r from-cyan-500 to-blue-600 px-5 py-3 text-sm font-medium text-white hover:brightness-110 disabled:opacity-60 ${focus}`}
        >
          <svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
            <path d="M12 2l2.4 6.6L21 11l-6.6 2.4L12 20l-2.4-6.6L3 11l6.6-2.4z" />
          </svg>
          {busy ? "Working…" : "Build with NEXORA"}
        </button>
      </div>
    </section>
  );
}
EOF

# ---------------- components/FileExplorer.tsx ----------------
cat > components/FileExplorer.tsx <<'EOF'
"use client";
import { tree, type TreeNode } from "@/lib/mock";
import { focus, panel } from "@/lib/ui";

function Nodes({
  nodes, depth, expanded, selected, onToggle, onSelect,
}: {
  nodes: TreeNode[]; depth: number; expanded: Set<string>; selected: string;
  onToggle: (p: string) => void; onSelect: (p: string) => void;
}) {
  return (
    <ul role={depth === 0 ? "tree" : "group"}>
      {nodes.map((n) => {
        const pad = { paddingLeft: 8 + depth * 14 };
        if (n.children) {
          const open = expanded.has(n.path);
          return (
            <li key={n.path} role="treeitem" aria-expanded={open}>
              <button onClick={() => onToggle(n.path)} style={pad} className={`flex w-full items-center gap-2 rounded-md py-2 pr-2 text-left text-sm text-slate-300 hover:bg-white/5 ${focus}`}>
                <span className="w-3 text-xs text-slate-500" aria-hidden="true">{open ? "▾" : "▸"}</span>
                {n.name}/
              </button>
              {open && (n.children.length ? (
                <Nodes nodes={n.children} depth={depth + 1} expanded={expanded} selected={selected} onToggle={onToggle} onSelect={onSelect} />
              ) : (
                <p style={{ paddingLeft: 8 + (depth + 1) * 14 + 20 }} className="py-1 text-xs text-slate-600">empty</p>
              ))}
            </li>
          );
        }
        return (
          <li key={n.path} role="treeitem" aria-selected={selected === n.path}>
            <button onClick={() => onSelect(n.path)} style={{ paddingLeft: 8 + depth * 14 + 20 }} className={`w-full rounded-md py-2 pr-2 text-left font-mono text-[13px] ${focus} ${
              selected === n.path ? "bg-cyan-400/10 text-cyan-100" : "text-slate-400 hover:bg-white/5 hover:text-white"
            }`}>
              {n.name}
            </button>
          </li>
        );
      })}
    </ul>
  );
}

export default function FileExplorer(props: {
  expanded: Set<string>; selected: string; onToggle: (p: string) => void; onSelect: (p: string) => void;
}) {
  return (
    <section aria-label="File explorer" className={`${panel} max-h-56 overflow-y-auto p-2 md:max-h-96`}>
      <p className="px-2 pb-1 pt-1 text-[11px] font-medium uppercase tracking-wider text-slate-500">my-project/</p>
      <Nodes nodes={tree} depth={0} {...props} />
    </section>
  );
}
EOF

# ---------------- components/CodeEditor.tsx ----------------
cat > components/CodeEditor.tsx <<'EOF'
"use client";
import { useState } from "react";
import { files } from "@/lib/mock";
import { focus } from "@/lib/ui";

const TOKEN =
  /(\/\/.*$)|("(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*')|\b(import|from|export|default|function|return|const|type|interface|async|await)\b|(<\/?[A-Z][A-Za-z]*)/g;

function highlight(line: string): React.ReactNode[] {
  const out: React.ReactNode[] = [];
  const re = new RegExp(TOKEN.source, "g");
  let last = 0;
  let m: RegExpExecArray | null;
  while ((m = re.exec(line)) !== null) {
    if (m.index > last) out.push(line.slice(last, m.index));
    const cls = m[1] ? "text-slate-500" : m[2] ? "text-emerald-300" : m[3] ? "text-sky-300" : "text-cyan-200";
    out.push(<span key={m.index} className={cls}>{m[0]}</span>);
    last = m.index + m[0].length;
  }
  if (last < line.length) out.push(line.slice(last));
  return out;
}

export default function CodeEditor({ path }: { path: string }) {
  const [copy, setCopy] = useState<"idle" | "copied" | "failed">("idle");
  const file = files[path];
  if (!file) return <div className="rounded-xl border border-white/10 p-6 text-sm text-slate-500">Select a file.</div>;

  const doCopy = async () => {
    try {
      await navigator.clipboard.writeText(file.code);
      setCopy("copied");
    } catch {
      setCopy("failed");
    }
    setTimeout(() => setCopy("idle"), 1500);
  };
  const plain = file.lang === "Markdown";

  return (
    <section aria-label="Code editor" className="flex min-w-0 flex-col overflow-hidden rounded-xl border border-white/10 bg-[#0a0d14]">
      <div className="flex items-center justify-between border-b border-white/10 bg-white/[0.02]">
        <span className="border-b-2 border-cyan-400 px-4 py-2.5 font-mono text-xs text-slate-200">{path.split("/").pop()}</span>
        <div className="flex items-center gap-3 pr-3">
          <span className="hidden text-xs text-slate-500 sm:inline">{file.lang}</span>
          <button onClick={doCopy} className={`rounded-md border border-white/10 px-2.5 py-1.5 text-xs text-slate-300 hover:bg-white/5 ${focus}`}>
            {copy === "copied" ? "Copied" : copy === "failed" ? "Copy failed" : "Copy"}
          </button>
        </div>
      </div>
      <pre tabIndex={0} aria-label={`Contents of ${path} (read-only sample)`} className={`max-h-96 overflow-auto py-3 font-mono text-[13px] leading-6 ${focus}`}>
        {file.code.split("\n").map((l, i) => (
          <div key={i} className="flex">
            <span className="w-10 shrink-0 select-none pr-3 text-right text-slate-600">{i + 1}</span>
            <code className="whitespace-pre pr-4 text-slate-300">{l === "" ? "\u00a0" : plain ? l : highlight(l)}</code>
          </div>
        ))}
      </pre>
    </section>
  );
}
EOF

# ---------------- components/RightPanel.tsx ----------------
cat > components/RightPanel.tsx <<'EOF'
"use client";
import { activity, plan, verification, type StepState } from "@/lib/mock";
import { focus, panel } from "@/lib/ui";

const icon: Record<StepState, { glyph: string; cls: string; text: string }> = {
  done: { glyph: "✓", cls: "text-emerald-400", text: "completed" },
  active: { glyph: "●", cls: "text-cyan-400", text: "in progress" },
  pending: { glyph: "○", cls: "text-slate-600", text: "pending" },
};

function Section({ title, note, children }: { title: string; note?: string; children: React.ReactNode }) {
  return (
    <section className={`${panel} p-3`}>
      <div className="mb-2 flex items-baseline justify-between gap-2">
        <h2 className="text-sm font-semibold text-white">{title}</h2>
        {note && <span className="text-[10px] text-slate-500">{note}</span>}
      </div>
      {children}
    </section>
  );
}

export default function RightPanel({
  open, onClose, log, checkpoint, note, onCreate, onRestore,
}: {
  open: boolean; onClose: () => void; log: string[];
  checkpoint: { name: string; status: string }; note: string;
  onCreate: () => void; onRestore: () => void;
}) {
  const small = `rounded-lg border border-white/10 px-3 py-2.5 text-sm text-slate-300 hover:bg-white/5 hover:text-white ${focus}`;
  return (
    <>
      {open && <div className="fixed inset-0 z-30 bg-black/60 xl:hidden" onClick={onClose} aria-hidden="true" />}
      <aside
        aria-label="Agent activity and project status"
        className={`fixed inset-y-0 right-0 z-40 flex w-80 max-w-[90vw] flex-col gap-3 overflow-y-auto border-l border-white/10 bg-[#080b12] p-4 transition-transform xl:static xl:translate-x-0 ${
          open ? "translate-x-0" : "translate-x-full"
        }`}
      >
        <button onClick={onClose} className={`${small} xl:hidden`}>Close panel</button>

        <Section title="NEXORA Activity" note="Sample data">
          <ul className="space-y-2">
            {activity.map((a) => (
              <li key={a.label} className="flex items-center gap-2.5 text-sm text-slate-300">
                <span className={icon[a.state].cls} aria-hidden="true">{icon[a.state].glyph}</span>
                {a.label}
                <span className="sr-only"> ({icon[a.state].text})</span>
              </li>
            ))}
          </ul>
          {log.length > 0 && (
            <ul aria-live="polite" className="mt-3 space-y-1 border-t border-white/10 pt-2 font-mono text-xs text-amber-200/80">
              {log.map((l, i) => <li key={i}>› {l}</li>)}
            </ul>
          )}
        </Section>

        <Section title="Build Plan" note="Future workflow">
          <ol className="space-y-1.5">
            {plan.map((p, i) => (
              <li key={p} className="flex gap-3 text-sm text-slate-300">
                <span className="font-mono text-xs text-slate-500">{String(i + 1).padStart(2, "0")}</span>
                {p}
              </li>
            ))}
          </ol>
        </Section>

        <Section title="Latest Checkpoint" note="UI only">
          <p className="text-sm text-slate-200">{checkpoint.name}</p>
          <p className="mt-0.5 text-xs text-emerald-300">Status: {checkpoint.status}</p>
          <div className="mt-3 flex gap-2">
            <button onClick={onRestore} className={`${small} flex-1`}>Restore</button>
            <button onClick={onCreate} className={`${small} flex-1`}>Create Checkpoint</button>
          </div>
          {note && <p role="status" className="mt-2 text-xs text-amber-200/80">{note}</p>}
        </Section>

        <Section title="Verification" note="Sample results">
          <ul className="space-y-1.5">
            {verification.map((v) => (
              <li key={v.name} className="flex justify-between text-sm text-slate-300">
                {v.name}
                <span className="text-emerald-300"><span aria-hidden="true">✓ </span>{v.result}</span>
              </li>
            ))}
          </ul>
          <p className="mt-2 text-xs text-slate-500">Nothing is executed in the browser.</p>
        </Section>
      </aside>
    </>
  );
}
EOF

# ---------------- components/Workspace.tsx ----------------
cat > components/Workspace.tsx <<'EOF'
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

  const build = () => {
    if (!prompt.trim()) { setError(true); return; }
    if (status !== "Ready") return;
    setError(false);
    clearTimers();
    setLog(["Request received (local demo, no AI backend)"]);
    setStatus("Planning");
    const at = (ms: number, fn: () => void) => timers.current.push(setTimeout(fn, ms));
    at(1200, () => { setStatus("Building"); setLog((l) => [...l, "Simulating file generation"]); });
    at(2400, () => { setStatus("Testing"); setLog((l) => [...l, "Simulating verification"]); });
    at(3400, () => { setStatus("Ready"); setLog((l) => [...l, "Demo finished. Nothing was generated or run."]); });
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
      />
    </div>
  );
}
EOF

# ---------------- import style fallback ----------------
if [ "$USE_ALIAS" = "0" ]; then
  echo "tsconfig has no @/* -> ./* mapping: switching to relative imports."
  sed -i 's#"@/lib/#"../lib/#' components/Sidebar.tsx components/ProjectHeader.tsx components/PromptWorkspace.tsx \
    components/FileExplorer.tsx components/CodeEditor.tsx components/RightPanel.tsx components/Workspace.tsx
fi

for tw in tailwind.config.ts tailwind.config.js tailwind.config.mjs tailwind.config.cjs; do
  if [ -f "$tw" ] && ! grep -q "components" "$tw"; then
    echo "WARNING: $tw may not scan ./components; styles could be missing."
  fi
done

echo ""
echo "Files written. No packages installed. app/ and package.json untouched."

# ---------------- checks ----------------
TSC="ok"; LINT="ok"; BUILD="ok"
echo ""; echo "=== TypeScript ==="
if npx --no-install tsc --noEmit; then echo "tsc: OK"; else TSC="FAILED"; fi
echo ""; echo "=== Lint ==="
if grep -q '"lint"' package.json; then
  if npm run lint; then echo "lint: OK"; else LINT="FAILED"; fi
else LINT="skipped (no lint script)"; fi
echo ""; echo "=== Build (npm run build) ==="
if npm run build; then echo "build: OK"; else BUILD="FAILED"; fi

echo ""; echo "=== Summary ==="
echo "tsc:   $TSC"; echo "lint:  $LINT"; echo "build: $BUILD"
if [ "$TSC" = "ok" ] && [ "$BUILD" = "ok" ]; then
  echo ""; echo "Run NEXORA with: npm run dev"
else
  echo ""; echo "A check failed. Paste the output above to get it fixed."; exit 1
fi
