// Local mock data only. Nothing here comes from an agent, API or database.
export type View = "workspace" | "templates" | "settings";
export type Status = "Ready" | "Planning" | "Building" | "Testing";
export type StepState = "done" | "active" | "pending";
export type TreeNode = { name: string; path: string; children?: TreeNode[] };

export const projects = ["My Website", "AI Dashboard", "Mobile App"];
export const recent = ["E-commerce platform", "SaaS dashboard", "Portfolio website"];

export const examples = [
  "A task manager with teams, due dates and a kanban board",
  "A SaaS landing page with pricing and a waitlist form",
  "A REST API for a bookstore with tests",
];

export const projectTypes = ["Web App", "Mobile App", "API", "Full Stack", "Other"];

export const config = [
  { id: "framework", label: "Framework", options: ["Next.js", "React + Vite", "Express", "Expo"] },
  { id: "language", label: "Language", options: ["TypeScript", "JavaScript", "Python"] },
  { id: "database", label: "Database", options: ["None", "PostgreSQL", "SQLite", "MongoDB"] },
  { id: "styling", label: "Styling", options: ["Tailwind CSS", "CSS Modules", "Plain CSS"] },
  { id: "deployment", label: "Deployment", options: ["Not decided", "Vercel", "Docker", "Static host"] },
];

export const activity: { label: string; state: StepState }[] = [
  { label: "Understanding request", state: "done" },
  { label: "Creating project plan", state: "done" },
  { label: "Generating components", state: "active" },
  { label: "Running tests", state: "pending" },
  { label: "Checking errors", state: "pending" },
  { label: "Creating checkpoint", state: "pending" },
];

export const plan = [
  "Analyze requirements",
  "Design architecture",
  "Create application structure",
  "Generate components",
  "Configure dependencies",
  "Run tests",
  "Fix errors",
  "Verify project",
  "Create checkpoint",
];

export const verification = [
  { name: "TypeScript", result: "Passed" },
  { name: "Lint", result: "Passed" },
  { name: "Build", result: "Passed" },
];

export const checkpointInitial = { name: "Initial frontend shell", status: "Saved" };

export const templates = [
  { name: "SaaS starter", meta: "Dashboard layout, pricing, settings", prompt: "A SaaS starter with a dashboard, pricing page and settings" },
  { name: "REST API + tests", meta: "Routes, validation, test suite", prompt: "A REST API with input validation and a test suite" },
  { name: "Portfolio site", meta: "Projects, about, contact", prompt: "A personal portfolio site with projects, about and contact sections" },
  { name: "Admin dashboard", meta: "Charts, tables, filters", prompt: "An admin dashboard with charts, tables and filters" },
];

export const tree: TreeNode[] = [
  {
    name: "app", path: "app",
    children: [
      { name: "page.tsx", path: "app/page.tsx" },
      { name: "layout.tsx", path: "app/layout.tsx" },
      { name: "globals.css", path: "app/globals.css" },
    ],
  },
  {
    name: "components", path: "components",
    children: [
      { name: "Navbar.tsx", path: "components/Navbar.tsx" },
      { name: "Hero.tsx", path: "components/Hero.tsx" },
    ],
  },
  { name: "lib", path: "lib", children: [] },
  { name: "public", path: "public", children: [] },
  { name: "package.json", path: "package.json" },
  { name: "README.md", path: "README.md" },
];

export const files: Record<string, { lang: string; code: string }> = {
  "app/page.tsx": {
    lang: "TypeScript React",
    code: `import Navbar from "@/components/Navbar";
import Hero from "@/components/Hero";

export default function Page() {
  return (
    <main>
      <Navbar />
      <Hero title="My Website" />
    </main>
  );
}`,
  },
  "app/layout.tsx": {
    lang: "TypeScript React",
    code: `import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = { title: "My Website" };

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}`,
  },
  "app/globals.css": {
    lang: "CSS",
    code: `@import "tailwindcss";

body {
  background: #07090f;
  color: #e2e8f0;
}`,
  },
  "components/Navbar.tsx": {
    lang: "TypeScript React",
    code: `const links = ["Home", "About", "Contact"];

export default function Navbar() {
  return (
    <nav className="flex gap-4 p-4">
      {links.map((l) => (
        <a key={l} href="#" className="text-sm text-slate-300">
          {l}
        </a>
      ))}
    </nav>
  );
}`,
  },
  "components/Hero.tsx": {
    lang: "TypeScript React",
    code: `type HeroProps = { title: string };

export default function Hero({ title }: HeroProps) {
  // Sample component shown in the NEXORA editor mock
  return (
    <section className="p-8">
      <h1 className="text-3xl font-semibold">{title}</h1>
    </section>
  );
}`,
  },
  "package.json": {
    lang: "JSON",
    code: `{
  "name": "my-project",
  "private": true,
  "scripts": {
    "dev": "next dev",
    "build": "next build --webpack"
  }
}`,
  },
  "README.md": {
    lang: "Markdown",
    code: `# my-project

Sample project shown in the NEXORA file explorer.
This content is mock data.`,
  },
};
