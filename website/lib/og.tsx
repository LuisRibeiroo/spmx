import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { ImageResponse } from "next/og";

export const OG_SIZE = { width: 1200, height: 630 } as const;

// Satori (next/og) cannot read CSS variables, so these mirror the dark tokens in app/globals.css.
const PAPER = "#121212";
const INK = "#f4f1ea";
const MUTED = "#b4aea4";
const ACCENT = "#ea6a38";

export async function renderOg(title: string, subtitle: string) {
  const icon = await readFile(join(process.cwd(), "public", "icon.png"));
  const src = `data:image/png;base64,${icon.toString("base64")}`;
  return new ImageResponse(
    (
      <div
        style={{
          width: "100%",
          height: "100%",
          display: "flex",
          flexDirection: "column",
          justifyContent: "space-between",
          background: PAPER,
          padding: 72,
          fontFamily: "sans-serif",
        }}
      >
        <div style={{ display: "flex", alignItems: "center", gap: 20 }}>
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src={src} width={62} height={72} alt="" style={{ imageRendering: "pixelated" }} />
          <span style={{ color: INK, fontSize: 44, fontWeight: 700 }}>spmx</span>
        </div>
        <div style={{ display: "flex", flexDirection: "column", gap: 24 }}>
          <div style={{ color: INK, fontSize: 76, fontWeight: 700, lineHeight: 1.05, letterSpacing: -2 }}>{title}</div>
          <div style={{ color: MUTED, fontSize: 32, lineHeight: 1.3 }}>{subtitle}</div>
        </div>
        <div style={{ height: 8, width: 200, background: ACCENT }} />
      </div>
    ),
    OG_SIZE,
  );
}
