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
