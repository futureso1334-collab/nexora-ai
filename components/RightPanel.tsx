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
