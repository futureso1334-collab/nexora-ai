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
