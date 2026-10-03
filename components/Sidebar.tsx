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
