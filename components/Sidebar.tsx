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
