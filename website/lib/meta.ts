import metaJson from "@/content/generated/meta.json";
import releasesJson from "@/content/generated/releases.json";

export interface Release {
  tag: string;
  name: string;
  date: string;
  url: string;
  body: string;
  prerelease: boolean;
}

export const meta = metaJson as {
  cliVersion: string;
  latestRelease: { tag: string; url: string; date: string } | null;
  tarballBytes: number | null;
};
export const releases = releasesJson as Release[];

/** `Latest x.y.z` only when a published GitHub release exists; otherwise the CLI version from source. */
export const versionBadge = meta.latestRelease
  ? { label: `Latest ${meta.latestRelease.tag.replace(/^v/, "")}`, href: meta.latestRelease.url }
  : { label: `v${meta.cliVersion}`, href: null };
