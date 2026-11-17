import { createMDX } from "fumadocs-mdx/next";

const withMDX = createMDX();

/** @type {import('next').NextConfig} */
const config = {
  output: "export",
  reactStrictMode: true,
  trailingSlash: false,
  images: { unoptimized: true },
  typescript: { ignoreBuildErrors: false },
  experimental: {
    inlineCss: true,
  },
};

export default withMDX(config);
