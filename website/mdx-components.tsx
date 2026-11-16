import defaultMdxComponents from "fumadocs-ui/mdx";
import { Tab, Tabs } from "fumadocs-ui/components/tabs";
import { Step, Steps } from "fumadocs-ui/components/steps";
import type { MDXComponents } from "mdx/types";
import { StoreDiagram } from "@/components/StoreDiagram";
import { CommandCard } from "@/components/CommandCard";
import { Changelog } from "@/components/Changelog";

export function getMDXComponents(components?: MDXComponents): MDXComponents {
  return {
    ...defaultMdxComponents,
    Tab,
    Tabs,
    Step,
    Steps,
    StoreDiagram,
    CommandCard,
    Changelog,
    ...components,
  };
}
