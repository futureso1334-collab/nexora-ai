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
