"use client";

import { useEffect, useRef, useState } from "react";
import { Trophy } from "lucide-react";
import { cn } from "@/lib/utils";
import type { TournamentPreviewImage } from "@/config/tournament-app";

const AUTOPLAY_MS = 5000;

/**
 * ONE application preview — a single phone frame that shows one screenshot at a
 * time. With more than one screenshot it cross-fades between them every few
 * seconds; the dots also switch manually and pause the autoplay. Autoplay is
 * disabled when the viewer prefers reduced motion.
 */
export function TournamentAppPreview({
  images,
  className,
}: {
  images: TournamentPreviewImage[];
  className?: string;
}) {
  const [index, setIndex] = useState(0);
  const [paused, setPaused] = useState(false);
  // Track which sources failed to load so we can show the fallback per-image.
  const [failed, setFailed] = useState<Record<number, boolean>>({});
  const reducedMotion = useRef(false);

  useEffect(() => {
    reducedMotion.current = Boolean(
      typeof window !== "undefined" && window.matchMedia?.("(prefers-reduced-motion: reduce)").matches,
    );
  }, []);

  useEffect(() => {
    if (images.length < 2 || paused || reducedMotion.current) return;
    const id = window.setInterval(() => {
      setIndex((i) => (i + 1) % images.length);
    }, AUTOPLAY_MS);
    return () => window.clearInterval(id);
  }, [images.length, paused]);

  const noImages = images.length === 0;

  return (
    <div
      className={cn("flex flex-col items-center gap-4", className)}
      onMouseEnter={() => setPaused(true)}
      onMouseLeave={() => setPaused(false)}
      onFocusCapture={() => setPaused(true)}
      onBlurCapture={() => setPaused(false)}
    >
      {/* Device frame sized to a Samsung Galaxy S26 Ultra: 6.9" display,
          3120×1440 → a ~9:19.5 screen with a slim uniform bezel. The
          screenshot keeps its own aspect ratio (contained on black), so
          nothing is cropped. */}
      <div
        className="relative w-[240px] max-w-full overflow-hidden rounded-[2.2rem] border-[5px] border-neutral-900 bg-black shadow-xl sm:w-[280px] dark:border-neutral-800"
        style={{ aspectRatio: "1440 / 3120" }}
      >
        {noImages ? (
          <Fallback />
        ) : (
          images.map((img, i) => {
            const active = i === index;
            if (failed[i]) return active ? <Fallback key={img.src} /> : null;
            return (
              // eslint-disable-next-line @next/next/no-img-element
              <img
                key={img.src}
                src={img.src}
                alt={`GameAll Tournament Management — ${img.label}`}
                loading={i === 0 ? "eager" : "lazy"}
                decoding="async"
                aria-hidden={!active}
                className={cn(
                  "absolute inset-0 h-full w-full object-contain transition-opacity duration-700 ease-in-out",
                  active ? "opacity-100" : "opacity-0",
                )}
                onError={() => setFailed((f) => ({ ...f, [i]: true }))}
              />
            );
          })
        )}
      </div>

      {images.length > 1 && (
        <div className="flex items-center gap-2" role="tablist" aria-label="Tournament app screenshots">
          {images.map((img, i) => (
            <button
              key={img.src}
              type="button"
              role="tab"
              aria-selected={i === index}
              aria-label={`Show ${img.label}`}
              onClick={() => setIndex(i)}
              className={cn(
                "h-2.5 w-2.5 rounded-full border border-border transition-colors focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring",
                i === index ? "bg-primary" : "bg-transparent hover:bg-muted",
              )}
            />
          ))}
        </div>
      )}
    </div>
  );
}

function Fallback() {
  return (
    <div className="absolute inset-0 flex flex-col items-center justify-center gap-2 bg-muted p-6 text-center">
      <Trophy className="h-10 w-10 text-muted-foreground" aria-hidden />
      <p className="text-sm font-medium text-muted-foreground">Tournament Management</p>
      <p className="text-xs text-muted-foreground">App preview coming soon</p>
    </div>
  );
}
