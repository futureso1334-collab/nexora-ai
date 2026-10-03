#!/usr/bin/env bash
# NEXORA AI - frontend shell installer (UI prototype only, mock data).
# Targets a Next.js App Router project that uses app/ (NO src/ directory).
# Run from the project root:  bash apply-nexora-shell.sh
# Installs no packages. Backs up every existing file it overwrites to <file>.bak.
set -e

APP=app
LIB=lib
COMP=components

# ---------- Preflight ----------
if [ ! -f package.json ] || ! grep -q '"next"' package.json; then
  echo "ERROR: run this from the root of your Next.js project (package.json containing next)."
  exit 1
fi
if [ ! -d "$APP" ]; then
  echo "ERROR: ./app directory not found. This installer only supports the app/ layout."
  exit 1
fi

backup() {
  if [ -f "$1" ] && [ ! -f "$1.bak" ]; then
    cp "$1" "$1.bak"
    echo "Backed up $1 -> $1.bak"
  fi
}

# Use the @/ alias only if tsconfig maps "@/*" to "./*". Otherwise use relative imports.
USE_ALIAS=0
if [ -f tsconfig.json ] && tr -d ' \t\r\n' < tsconfig.json | grep -q '"@/\*":\["\./\*"\]'; then
  USE_ALIAS=1
fi
if [ "$USE_ALIAS" = "1" ]; then
  echo "tsconfig maps @/* -> ./* : using @/ imports."
else
  echo "tsconfig has no @/* -> ./* mapping: using relative imports instead (tsconfig is not modified)."
fi

mkdir -p "$LIB" "$COMP"

for f in "$APP/layout.tsx" "$APP/page.tsx" \
         "$LIB/mock.ts" \
         "$COMP/Sidebar.tsx" "$COMP/RightPanel.tsx" "$COMP/Workspace.tsx"; do
  backup "$f"
done

# ---------- app/layout.tsx ----------
cat > "$APP/layout.tsx" <<'EOF'
import type { Metadata, Viewport } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "NEXORA AI",
  description: "AI software-engineering workspace",
};

export const viewport: Viewport = { themeColor: "#05070d" };

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body className="antialiased">{children}</body>
    </html>
  );
}
EOF

# ---------- app/page.tsx ----------
cat > "$APP/page.tsx" <<'EOF'
import Workspace from "@/components/Workspace";

export default function Page() {
  return <Workspace />;
}
EOF

# ---------- lib/mock.ts ----------
cat > "$LIB/mock.ts" <<'EOF'
// Mock data only. Nothing here comes from a real agent or API.
export type View = "home" | "projects" | "recent" | "templates" | "settings";

export const examples = [
  "Build a task manager with teams, due dates and a kanban board",
  "Create a SaaS landing page with pricing and a waitlist form",
  "Make a personal finance tracker with charts and CSV export",
  "Build a REST API for a bookstore with tests",
];

export type StepState = "done" | "active" | "pending";

export const pipeline: { title: string; detail: string; state: StepState }[] = [
  { title: "Understand request", detail: "Parse goals and constraints", state: "pending" },
  { title: "Create project plan", detail: "Milestones and file structure", state: "pending" },
  { title: "Generate files", detail: "Scaffold and write code", state: "pending" },
  { title: "Run controlled tests", detail: "Lint, build, unit tests", state: "pending" },
  { title: "Fix errors", detail: "Read output, patch, retry", state: "pending" },
  { title: "Save checkpoint", detail: "Snapshot project state", state: "pending" },
];

export const sampleProjects = [
  { name: "Sample: Kanban App", meta: "Next.js · 12 files" },
  { name: "Sample: Bookstore API", meta: "Node · 8 files" },
  { name: "Sample: Landing Page", meta: "Next.js · 5 files" },
];

export const sampleRecent = [
  { name: "Sample: Kanban App", meta: "Edited 2 hours ago" },
  { name: "Sample: Landing Page", meta: "Edited yesterday" },
];

export const templates = [
  { name: "Next.js SaaS starter", meta: "Dashboard layout, pricing, settings" },
  { name: "REST API + tests", meta: "Routes, validation, test suite" },
  { name: "Dashboard", meta: "Charts, tables, filters" },
  { name: "Landing page", meta: "Hero, features, waitlist" },
];

export const sampleStatus = {
  files: ["app/page.tsx", "lib/db.ts", "package.json"],
};
EOF

# ---------- components/Sidebar.tsx ----------
cat > "$COMP/Sidebar.tsx" <<'EOF'
"use client";
import type { View } from "@/lib/mock";

const items: { id: View | "new"; label: string; icon: string }[] = [
  { id: "new", label: "New Project", icon: "+" },
  { id: "projects", label: "Projects", icon: "▦" },
  { id: "recent", label: "Recent", icon: "◷" },
  { id: "templates", label: "Templates", icon: "❖" },
  { id: "settings", label: "Settings", icon: "⚙" },
];

export function Logo() {
  return (
    <div className="flex items-center gap-2.5">
      <div className="grid h-8 w-8 place-items-center rounded-lg bg-gradient-to-br from-cyan-400 to-blue-600 text-sm font-bold text-white shadow-[0_0_20px_rgba(34,211,238,0.45)]">
        N
      </div>
      <span className="text-lg font-semibold tracking-[0.2em] text-white">NEXORA</span>
    </div>
  );
}

export default function Sidebar({
  view,
  onSelect,
  open,
  onClose,
}: {
  view: View;
  onSelect: (v: View | "new") => void;
  open: boolean;
  onClose: () => void;
}) {
  return (
    <>
      {open && <div className="fixed inset-0 z-30 bg-black/60 lg:hidden" onClick={onClose} />}
      <aside
        className={`fixed inset-y-0 left-0 z-40 flex w-64 flex-col gap-6 border-r border-white/10 bg-[#070b14]/95 p-5 backdrop-blur transition-transform lg:static lg:translate-x-0 ${
          open ? "translate-x-0" : "-translate-x-full"
        }`}
      >
        <Logo />
        <nav className="flex flex-col gap-1">
          {items.map((i) => {
            const active = i.id === view;
            return (
              <button
                key={i.id}
                onClick={() => {
                  onSelect(i.id);
                  onClose();
                }}
                className={`flex items-center gap-3 rounded-xl px-3 py-2.5 text-left text-sm transition ${
                  i.id === "new"
                    ? "mb-2 bg-gradient-to-r from-cyan-500/20 to-blue-600/20 text-cyan-200 ring-1 ring-cyan-400/30 hover:ring-cyan-300/60"
                    : active
                    ? "bg-white/10 text-white"
                    : "text-slate-400 hover:bg-white/5 hover:text-white"
                }`}
              >
                <span className="w-4 text-center">{i.icon}</span>
                {i.label}
              </button>
            );
          })}
        </nav>
        <p className="mt-auto text-xs text-slate-600">NEXORA AI · UI prototype</p>
      </aside>
    </>
  );
}
EOF

# ---------- components/RightPanel.tsx ----------
cat > "$COMP/RightPanel.tsx" <<'EOF'
"use client";
import { sampleStatus } from "@/lib/mock";

function Row({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="rounded-xl border border-white/10 bg-white/[0.03] p-3">
      <p className="text-[11px] uppercase tracking-wider text-slate-500">{label}</p>
      <div className="mt-1 text-sm text-slate-200">{children}</div>
    </div>
  );
}

export default function RightPanel({
  open,
  onClose,
  projectName,
}: {
  open: boolean;
  onClose: () => void;
  projectName: string;
}) {
  return (
    <>
      {open && <div className="fixed inset-0 z-30 bg-black/60 xl:hidden" onClick={onClose} />}
      <aside
        className={`fixed inset-y-0 right-0 z-40 flex w-80 max-w-[90vw] flex-col gap-3 overflow-y-auto border-l border-white/10 bg-[#070b14]/95 p-5 backdrop-blur transition-transform xl:static xl:translate-x-0 ${
          open ? "translate-x-0" : "translate-x-full"
        }`}
      >
        <div className="flex items-center justify-between">
          <h2 className="text-sm font-semibold text-white">Project activity</h2>
          <span className="rounded-full bg-amber-400/10 px-2 py-0.5 text-[10px] text-amber-300">
            Placeholder data
          </span>
        </div>
        <Row label="Current project">{projectName}</Row>
        <Row label="Agent status">
          <span className="mr-2 inline-block h-2 w-2 rounded-full bg-slate-500" />
          Not connected
        </Row>
        <Row label="Current task">None</Row>
        <Row label="Files changed">
          <p className="mb-1 text-xs text-slate-500">Example of how files will appear:</p>
          <ul className="space-y-1 font-mono text-xs text-cyan-200/70">
            {sampleStatus.files.map((f) => (
              <li key={f}>{f}</li>
            ))}
          </ul>
        </Row>
        <Row label="Test status">Not run</Row>
        <Row label="Checkpoint">None saved</Row>
        <button
          onClick={onClose}
          className="mt-2 rounded-xl border border-white/10 py-2 text-sm text-slate-400 hover:text-white xl:hidden"
        >
          Close
        </button>
      </aside>
    </>
  );
}
EOF

# ---------- components/Workspace.tsx ----------
cat > "$COMP/Workspace.tsx" <<'EOF'
"use client";
import { useState } from "react";
import Sidebar, { Logo } from "./Sidebar";
import RightPanel from "./RightPanel";
import { examples, pipeline, sampleProjects, sampleRecent, templates, type View } from "@/lib/mock";

const card = "rounded-2xl border border-white/10 bg-white/[0.04] backdrop-blur";
const dot = {
  done: "bg-emerald-400",
  active: "bg-cyan-400 shadow-[0_0_10px_rgba(34,211,238,0.8)]",
  pending: "bg-slate-600",
} as const;

function List({
  title,
  note,
  items,
}: {
  title: string;
  note: string;
  items: { name: string; meta: string }[];
}) {
  return (
    <div className="space-y-4">
      <div>
        <h1 className="text-2xl font-semibold text-white">{title}</h1>
        <p className="mt-1 text-sm text-slate-500">{note}</p>
      </div>
      <ul className="space-y-2">
        {items.map((p) => (
          <li key={p.name} className={`${card} flex items-center justify-between gap-3 p-4`}>
            <span className="text-sm text-slate-200">{p.name}</span>
            <span className="text-xs text-slate-500">{p.meta}</span>
          </li>
        ))}
      </ul>
    </div>
  );
}

export default function Workspace() {
  const [view, setView] = useState<View>("home");
  const [prompt, setPrompt] = useState("");
  const [captured, setCaptured] = useState<string | null>(null);
  const [error, setError] = useState(false);
  const [nav, setNav] = useState(false);
  const [panel, setPanel] = useState(false);

  const select = (v: View | "new") => {
    if (v === "new") {
      setPrompt("");
      setCaptured(null);
      setError(false);
      setView("home");
    } else {
      setView(v);
    }
  };

  const build = () => {
    if (!prompt.trim()) {
      setError(true);
      return;
    }
    setError(false);
    setCaptured(prompt.trim());
  };

  const projectName = captured ? "Untitled project (request captured)" : "No active project";

  return (
    <div className="relative flex h-dvh overflow-hidden bg-[#05070d] text-slate-200">
      <div className="pointer-events-none absolute inset-0 bg-[radial-gradient(60%_50%_at_50%_0%,rgba(34,211,238,0.12),transparent),radial-gradient(40%_40%_at_90%_10%,rgba(59,130,246,0.14),transparent)]" />
      <Sidebar view={view} onSelect={select} open={nav} onClose={() => setNav(false)} />

      <div className="relative flex min-w-0 flex-1 flex-col">
        <header className="flex items-center justify-between border-b border-white/10 p-3 lg:hidden">
          <button
            onClick={() => setNav(true)}
            className="rounded-lg px-3 py-1.5 text-lg hover:bg-white/10"
            aria-label="Open menu"
          >
            ☰
          </button>
          <Logo />
          <button
            onClick={() => setPanel(true)}
            className="rounded-lg px-3 py-1.5 text-sm hover:bg-white/10 xl:hidden"
          >
            Activity
          </button>
        </header>

        <main className="flex-1 overflow-y-auto p-4 sm:p-8">
          <div className="mx-auto max-w-3xl space-y-6">
            {view === "home" && (
              <>
                <div>
                  <h1 className="bg-gradient-to-r from-white to-cyan-300 bg-clip-text text-3xl font-semibold text-transparent sm:text-4xl">
                    What will you build?
                  </h1>
                  <p className="mt-2 text-sm text-slate-400">
                    Describe an application. NEXORA will plan, write and test it once the agent is connected.
                  </p>
                </div>

                <div
                  className={`${card} p-3 ${
                    error ? "ring-1 ring-red-400/60" : "focus-within:ring-1 focus-within:ring-cyan-400/50"
                  }`}
                >
                  <textarea
                    value={prompt}
                    onChange={(e) => {
                      setPrompt(e.target.value);
                      setError(false);
                    }}
                    rows={5}
                    placeholder="e.g. A booking app for a small gym with member accounts and a weekly schedule…"
                    className="w-full resize-none bg-transparent p-2 text-base outline-none placeholder:text-slate-600"
                  />
                  <div className="flex items-center justify-between gap-3 p-1">
                    <span className="text-xs text-slate-500">
                      {error ? "Enter a description first." : `${prompt.length} chars`}
                    </span>
                    <button
                      onClick={build}
                      className="rounded-xl bg-gradient-to-r from-cyan-500 to-blue-600 px-5 py-2.5 text-sm font-medium text-white shadow-[0_0_24px_rgba(37,99,235,0.45)] transition hover:brightness-110 active:scale-95"
                    >
                      Build with NEXORA
                    </button>
                  </div>
                </div>

                <div className="flex flex-wrap gap-2">
                  {examples.map((e) => (
                    <button
                      key={e}
                      onClick={() => {
                        setPrompt(e);
                        setError(false);
                      }}
                      className="rounded-full border border-white/10 bg-white/[0.03] px-3 py-1.5 text-left text-xs text-slate-300 transition hover:border-cyan-400/40 hover:text-white"
                    >
                      {e}
                    </button>
                  ))}
                </div>

                <section className={`${card} p-4`}>
                  <h2 className="text-sm font-semibold text-white">Project status</h2>
                  {captured ? (
                    <div className="mt-2 space-y-2 text-sm">
                      <p className="text-slate-400">Request captured in the UI only:</p>
                      <p className="rounded-lg bg-black/30 p-3 text-slate-200">{captured}</p>
                      <p className="text-xs text-amber-300/80">
                        No agent is connected yet, so nothing was planned, generated or run.
                      </p>
                    </div>
                  ) : (
                    <p className="mt-2 text-sm text-slate-500">
                      No active project. Write a prompt and press Build.
                    </p>
                  )}
                </section>

                <section className={`${card} p-4`}>
                  <div className="flex items-center justify-between">
                    <h2 className="text-sm font-semibold text-white">Activity timeline</h2>
                    <span className="text-[10px] text-slate-500">Planned pipeline preview</span>
                  </div>
                  <ol className="mt-3 space-y-3">
                    {pipeline.map((s) => (
                      <li key={s.title} className="flex items-start gap-3">
                        <span className={`mt-1.5 h-2.5 w-2.5 shrink-0 rounded-full ${dot[s.state]}`} />
                        <div>
                          <p className="text-sm text-slate-200">{s.title}</p>
                          <p className="text-xs text-slate-500">{s.detail}</p>
                        </div>
                      </li>
                    ))}
                  </ol>
                </section>
              </>
            )}

            {view === "projects" && (
              <List
                title="Projects"
                note="Sample entries. Real projects arrive with the agent and storage stage."
                items={sampleProjects}
              />
            )}
            {view === "recent" && <List title="Recent" note="Sample entries only." items={sampleRecent} />}
            {view === "templates" && (
              <List title="Templates" note="Starting points (not yet functional)." items={templates} />
            )}
            {view === "settings" && (
              <div className="space-y-4">
                <h1 className="text-2xl font-semibold text-white">Settings</h1>
                <div className={`${card} p-4 text-sm text-slate-400`}>
                  Model gateway: not configured. It will be connected through a server-side API route in the
                  next stage, so no keys ever live in the browser.
                </div>
              </div>
            )}
          </div>
        </main>
      </div>

      <RightPanel open={panel} onClose={() => setPanel(false)} projectName={projectName} />
    </div>
  );
}
EOF

# ---------- Import style fallback (only if @/* -> ./* is not configured) ----------
if [ "$USE_ALIAS" = "0" ]; then
  sed -i 's#"@/components/#"../components/#' "$APP/page.tsx"
  sed -i 's#"@/lib/#"../lib/#' "$COMP/Sidebar.tsx" "$COMP/RightPanel.tsx" "$COMP/Workspace.tsx"
fi

# ---------- Tailwind v3 content-glob warning (informational only) ----------
for tw in tailwind.config.ts tailwind.config.js tailwind.config.mjs tailwind.config.cjs; do
  if [ -f "$tw" ] && ! grep -q "components" "$tw"; then
    echo "WARNING: $tw does not appear to scan ./components. Add './components/**/*.{ts,tsx}' to its content list or styles may be missing."
  fi
done

echo ""
echo "Files written (app/, components/, lib/). No src/ created, no packages installed."
echo ""

# ---------- Checks ----------
TSC_STATUS="ok"; LINT_STATUS="ok"

echo "=== TypeScript ==="
if npx --no-install tsc --noEmit; then echo "tsc: OK"; else TSC_STATUS="FAILED"; echo "tsc: FAILED"; fi

echo ""
echo "=== Lint ==="
if grep -q '"lint"' package.json; then
  if npm run lint; then echo "lint: OK"; else LINT_STATUS="FAILED"; echo "lint: FAILED"; fi
else
  LINT_STATUS="skipped (no lint script)"; echo "$LINT_STATUS"
fi

echo ""
echo "=== Build ==="
BUILD_STATUS="ok"
if npm run build; then echo "build: OK"; else BUILD_STATUS="FAILED"; echo "build: FAILED"; fi

echo ""
echo "=== Summary ==="
echo "tsc:   $TSC_STATUS"
echo "lint:  $LINT_STATUS"
echo "build: $BUILD_STATUS"

if [ "$TSC_STATUS" = "ok" ] && [ "$BUILD_STATUS" = "ok" ]; then
  echo ""
  echo "Start NEXORA with: npm run dev"
else
  echo ""
  echo "One or more checks failed. Paste the output above to get it fixed."
  exit 1
fi
