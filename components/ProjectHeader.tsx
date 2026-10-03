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
