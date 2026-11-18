import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { ImageResponse } from "next/og";

export const OG_SIZE = { width: 1200, height: 630 } as const;

// Satori (next/og) cannot read CSS variables, so these mirror the dark tokens in app/globals.css.
const PAPER = "#121212";
const SURFACE = "#1b1917";
const BORDER = "#2f2a26";
const INK = "#f4f1ea";
const MUTED = "#b4aea4";
const ACCENT = "#ea6a38";

function titleFontSize(title: string): number {
  if (title.length > 42) return 44;
  if (title.length > 28) return 52;
  return 60;
}

export async function renderOg(title: string, subtitle: string, eyebrow = "macOS CLI · SwiftPM") {
  const icon = await readFile(join(process.cwd(), "public", "icon.png"));
  const src = `data:image/png;base64,${icon.toString("base64")}`;
  const fontSize = titleFontSize(title);

  return new ImageResponse(
    (
      <div
        style={{
          width: "100%",
          height: "100%",
          display: "flex",
          flexDirection: "row",
          alignItems: "center",
          justifyContent: "space-between",
          background: `linear-gradient(135deg, ${PAPER} 0%, #181512 100%)`,
          backgroundColor: PAPER,
          padding: "56px 68px",
          fontFamily: "sans-serif",
          gap: 48,
        }}
      >
        <div
          style={{
            display: "flex",
            flexDirection: "column",
            justifyContent: "space-between",
            height: "100%",
            flex: 1,
          }}
        >
          <div style={{ display: "flex", alignItems: "center", gap: 14 }}>
            <div
              style={{
                width: 12,
                height: 12,
                borderRadius: 3,
                background: ACCENT,
              }}
            />
            <span style={{ color: INK, fontSize: 32, fontWeight: 700, letterSpacing: -0.5 }}>spmx</span>
            <span style={{ color: "#6e675f", fontSize: 28 }}>/</span>
            <span style={{ color: ACCENT, fontSize: 22, fontWeight: 600, letterSpacing: 0.5 }}>{eyebrow}</span>
          </div>

          <div style={{ display: "flex", flexDirection: "column", gap: 20 }}>
            <div
              style={{
                color: INK,
                fontSize,
                fontWeight: 700,
                lineHeight: 1.08,
                letterSpacing: -1.5,
              }}
            >
              {title}
            </div>
            <div style={{ color: MUTED, fontSize: 26, lineHeight: 1.38 }}>{subtitle}</div>
          </div>

          <div style={{ display: "flex", alignItems: "center", gap: 20 }}>
            <div style={{ height: 6, width: 72, borderRadius: 3, background: ACCENT }} />
            <span style={{ color: MUTED, fontSize: 20, letterSpacing: 0.3 }}>
              APFS copy-on-write · Git worktrees · Xcode &amp; Flutter
            </span>
          </div>
        </div>

        <div
          style={{
            width: 344,
            height: 416,
            borderRadius: 28,
            background: `linear-gradient(155deg, ${SURFACE} 0%, #151413 100%)`,
            border: `2px solid ${BORDER}`,
            boxShadow: "0 24px 64px rgba(0, 0, 0, 0.55)",
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            flexShrink: 0,
          }}
        >
          {/* 246x288 is an exact 6x integer multiple of the 41x48 pixel-art icon */}
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src={src} width={246} height={288} alt="" style={{ imageRendering: "pixelated" }} />
        </div>
      </div>
    ),
    OG_SIZE,
  );
}
