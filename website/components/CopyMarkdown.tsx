"use client";

import { CopyButton } from "./CopyButton";

export function CopyMarkdown({ markdown }: { markdown: string }) {
  return <CopyButton text={markdown} label="Copy as Markdown" variant="text" />;
}
