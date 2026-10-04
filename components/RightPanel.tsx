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
  approvalTool, onApprove, onDeny,
}: {
  open: boolean; onClose: () => void; log: string[];
  checkpoint: { name: string; status: string }; note: string;
  onCreate: () => void; onRestore: () => void;
  approvalTool: string | null;
  onApprove: () => void;
  onDeny: () => void;
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

        {approvalTool && (
          <Section title="Approval Required" note="Human decision">
            <p className="text-sm text-slate-300">
              NEXORA wants to execute:
            </p>
            <p className="mt-1 rounded-lg border border-amber-400/20 bg-amber-400/5 px-3 py-2 font-mono text-xs text-amber-200">
              {approvalTool}
            </p>
            <div className="mt-3 grid grid-cols-2 gap-2">
              <button
                onClick={onDeny}
                className={`${small} border-red-400/20 text-red-300 hover:bg-red-400/10`}
              >
                Deny
              </button>
              <button
                onClick={onApprove}
                className={`${small} border-emerald-400/20 text-emerald-300 hover:bg-emerald-400/10`}
              >
                Approve
              </button>
            </div>
          </Section>
        )}

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
