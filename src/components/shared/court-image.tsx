"use client";

import { useState } from "react";
import { cn } from "@/lib/utils";

/**
 * A court's picture, or — when it has none, or the picture fails to load — the green "COURT" panel, so a card
 * never shows a broken-image icon. Fills its parent; the parent sets the size.
 */
export function CourtImage({ src, alt = "", className }: { src?: string | null; alt?: string; className?: string }) {
  const [failed, setFailed] = useState(false);
  if (src && !failed) {
    // eslint-disable-next-line @next/next/no-img-element
    return <img src={src} alt={alt} onError={() => setFailed(true)} className={cn("h-full w-full object-cover", className)} />;
  }
  return (
    <div
      className={cn(
        "flex h-full w-full items-center justify-center bg-gradient-to-br from-emerald-900 to-emerald-700 text-[10px] font-medium tracking-wide text-emerald-200",
        className,
      )}
    >
      COURT
    </div>
  );
}
