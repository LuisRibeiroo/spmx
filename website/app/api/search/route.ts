import { source } from "@/lib/source";
import { createFromSource } from "fumadocs-core/search/server";

export const revalidate = false;

// Static export: the Orama index is built once at build time and fetched by the client.
export const { staticGET: GET } = createFromSource(source);
