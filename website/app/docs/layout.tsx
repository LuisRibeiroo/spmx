import { DocsLayout } from "fumadocs-ui/layouts/docs";
import { Logo } from "@/components/Logo";
import { source } from "@/lib/source";
import { REPO_URL } from "@/lib/site";

export default function Layout({ children }: { children: React.ReactNode }) {
  return (
    <DocsLayout
      tree={source.pageTree}
      nav={{ title: <Logo size={22} />, url: "/" }}
      githubUrl={REPO_URL}
      links={[{ text: "Benchmarks", url: "/benchmarks" }]}
    >
      {children}
    </DocsLayout>
  );
}
