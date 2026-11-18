import "./globals.css";
import type { Metadata, Viewport } from "next";
import { Geist, IBM_Plex_Mono } from "next/font/google";
import { RootProvider } from "fumadocs-ui/provider";
import { OWNER_URL, SITE } from "@/lib/site";
import { softwareApplication, webSite } from "@/lib/jsonld";

// Two families: Geist for text and UI, IBM Plex Mono only for code, terminal output and the wordmark.
const sans = Geist({ subsets: ["latin"], variable: "--font-geist", display: "swap" });
const mono = IBM_Plex_Mono({ subsets: ["latin"], weight: ["400", "600"], variable: "--font-plex-mono", display: "swap" });

export const metadata: Metadata = {
  metadataBase: new URL(SITE.url),
  title: { default: `${SITE.name} — ${SITE.tagline}`, template: `%s · ${SITE.name}` },
  description: SITE.metaDescription,
  applicationName: SITE.name,
  category: "Developer Tools",
  keywords: [
    "spmx",
    "SwiftPM",
    "Swift Package Manager",
    "Git worktrees",
    "Xcode",
    "DerivedData",
    "APFS",
    "clonefile",
    "macOS",
    "Flutter",
    "React Native",
    "Expo",
    "Capacitor",
    "Kotlin Multiplatform",
    "LLVM CAS",
  ],
  authors: [{ name: SITE.repo.owner, url: OWNER_URL }],
  creator: SITE.repo.owner,
  publisher: SITE.repo.owner,
  alternates: { canonical: "/" },
  robots: {
    index: true,
    follow: true,
    googleBot: {
      index: true,
      follow: true,
      "max-image-preview": "large",
      "max-snippet": -1,
      "max-video-preview": -1,
    },
  },
  icons: {
    icon: [
      { url: "/favicon.ico", sizes: "48x48" },
      { url: "/icon.svg", type: "image/svg+xml" },
      { url: "/favicon-32x32.png", type: "image/png", sizes: "32x32" },
      { url: "/favicon-16x16.png", type: "image/png", sizes: "16x16" },
    ],
    apple: [{ url: "/apple-touch-icon.png", sizes: "180x180", type: "image/png" }],
  },
  openGraph: {
    type: "website",
    siteName: SITE.name,
    locale: "en_US",
    images: [{ url: "/opengraph-image", width: 1200, height: 630, alt: `${SITE.name}: ${SITE.tagline}`, type: "image/png" }],
  },
  twitter: {
    card: "summary_large_image",
    images: [{ url: "/opengraph-image", width: 1200, height: 630, alt: `${SITE.name}: ${SITE.tagline}` }],
  },
};

export const viewport: Viewport = {
  themeColor: [
    { media: "(prefers-color-scheme: dark)", color: "#121212" },
    { media: "(prefers-color-scheme: light)", color: "#ffffff" },
  ],
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" className={`${sans.variable} ${mono.variable}`} suppressHydrationWarning>
      <body className="flex min-h-screen flex-col">
        <script
          type="application/ld+json"
          dangerouslySetInnerHTML={{ __html: JSON.stringify([softwareApplication, webSite]) }}
        />
        <RootProvider
          theme={{ defaultTheme: "system", enableSystem: true }}
          search={{ options: { type: "static", api: "/api/search" } }}
        >
          {children}
        </RootProvider>
      </body>
    </html>
  );
}
