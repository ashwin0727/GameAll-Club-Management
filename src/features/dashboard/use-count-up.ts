"use client";

import { useEffect, useRef, useState } from "react";

/**
 * Counts a KPI up from 0 to `target` on mount (and re-runs whenever the
 * target changes, e.g. after a filter switch), so a landing dashboard reads
 * as "these numbers just arrived" rather than snapping into place.
 *
 * Honours prefers-reduced-motion by returning the final value immediately —
 * the number is information, never decoration, so it must always be
 * readable and correct at the end of the frame budget either way.
 */
export function useCountUp(target: number, durationMs = 700): number {
  const [value, setValue] = useState(target);
  const frameRef = useRef<number | null>(null);

  useEffect(() => {
    if (typeof window === "undefined") return;
    const reduced = window.matchMedia?.("(prefers-reduced-motion: reduce)").matches ?? false;
    if (reduced || !Number.isFinite(target) || target === 0) {
      setValue(target);
      return;
    }

    const start = performance.now();
    const from = 0;
    const tick = (now: number) => {
      const t = Math.min(1, (now - start) / durationMs);
      // Same easing curve as the card's entrance (easeOutQuint-ish).
      const eased = 1 - Math.pow(1 - t, 4);
      setValue(from + (target - from) * eased);
      if (t < 1) frameRef.current = requestAnimationFrame(tick);
    };
    frameRef.current = requestAnimationFrame(tick);

    return () => {
      if (frameRef.current !== null) cancelAnimationFrame(frameRef.current);
    };
  }, [target, durationMs]);

  return value;
}
