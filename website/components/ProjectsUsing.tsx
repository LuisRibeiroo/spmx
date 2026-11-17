import { Container } from "@/components/Container";

export interface ProjectEntry {
  name: string;
  href: string;
  description?: string;
}

// Placeholder disabled until real projects using spmx are added.
const PROJECTS: ReadonlyArray<ProjectEntry> = [];

export function ProjectsUsing() {
  if (PROJECTS.length === 0) {
    return null;
  }

  return (
    <Container as="section" className="pb-16 md:pb-24" aria-labelledby="projects-using">
      <h2 id="projects-using" className="text-h2 font-bold tracking-tight">
        Projects using spmx
      </h2>
      <ul className="mt-8 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
        {PROJECTS.map((project) => (
          <li key={project.href} className="rounded-lg border border-line bg-surface p-5">
            <a
              href={project.href}
              target="_blank"
              rel="noreferrer"
              className="font-semibold text-ink hover:text-accent-text"
            >
              {project.name}
            </a>
            {project.description ? (
              <p className="mt-1 text-sm text-ink-muted">{project.description}</p>
            ) : null}
          </li>
        ))}
      </ul>
    </Container>
  );
}
