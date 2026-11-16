import "./globals.css";
import type { Metadata, Viewport } from "next";
import { Geist, IBM_Plex_Mono } from "next/font/google";
import { RootProvider } from "fumadocs-ui/provider";
import { SITE } from "@/lib/site";
import { softwareApplication, webSite } from "@/lib/jsonld";

// Two families: Geist for text and UI, IBM Plex Mono only for code, terminal output and the wordmark.
const sans = Geist({ subsets: ["latin"], variable: "--font-geist", display: "swap" });
const mono = IBM_Plex_Mono({ subsets: ["latin"], weight: ["400", "500", "600"], variable: "--font-plex-mono", display: "swap" });

export const metadata: Metadata = {
  metadataBase: new URL(SITE.url),
  title: { default: `${SITE.name} — ${SITE.tagline}`, template: `%s · ${SITE.name}` },
  description: SITE.description,
  applicationName: SITE.name,
  alternates: { canonical: "/" },
  icons: { icon: "/icon.svg", apple: "/icon.png" },
  openGraph: { type: "website", siteName: SITE.name, locale: "en_US" },
  twitter: { card: "summary_large_image" },
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
