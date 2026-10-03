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
