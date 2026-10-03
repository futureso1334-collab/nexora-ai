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
