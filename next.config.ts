import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  reactStrictMode: true,
  // Lets `next build` write to a separate output dir (e.g.
  // `NEXT_DIST_DIR=.next-prod next build`) so a production build never
  // collides with a running `next dev` on the shared `.next/` — a real
  // hazard when the repo lives in a OneDrive-synced folder, where a stale
  // `.next` can't always be fully cleared. Unset → ".next", unchanged.
  distDir: process.env.NEXT_DIST_DIR ?? ".next",
  images: {
    remotePatterns: [
      {
        protocol: "https",
        hostname: "**.supabase.co",
      },
    ],
  },
  async headers() {
    return [
      {
        // The public booking page is meant to be embedded in a club's own
        // website, so it must be framable from any origin. Scoped to this
        // one route: every other page — the whole dashboard included — keeps
        // the default deny and cannot be put in a frame.
        source: "/book/:path*",
        headers: [{ key: "Content-Security-Policy", value: "frame-ancestors *" }],
      },
      {
        // The embed loader is fetched cross-origin by those sites.
        source: "/embed.js",
        headers: [
          { key: "Access-Control-Allow-Origin", value: "*" },
          { key: "Cache-Control", value: "public, max-age=300" },
        ],
      },
    ];
  },
};

export default nextConfig;