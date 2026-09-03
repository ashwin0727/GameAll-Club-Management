"use client";

import { cn } from "@/lib/utils";

export interface DonutSegment {
  label: string;
  value: number;
  color: string;
  /** Rendered under the label — usually the formatted amount and share. */
  caption?: string;
}

/**
 * Donut with a centred total and a legend beside it.
 *
 * Each arc is drawn as a stroked circle whose dash offset starts a full arc
 * length away, so animating back to its real offset sweeps it open. That
 * needs no path measurement and no charting library.
 *
 * Sweeps once on mount and is disabled under prefers-reduced-motion, via
 * `.donut-sweep` in globals.css.
 */
export function Donut({
  segments,
  centreLabel,
  centreValue,
  size = 132,
  stroke = 18,
  className,
}: {
  segments: DonutSegment[];
  centreLabel?: string;
  centreValue?: string;
  size?: number;
  stroke?: number;
  className?: string;
}) {
  const radius = (size - stroke) / 2;
  const circumference = 2 * Math.PI * radius;
  // Guarded so an all-zero range renders an empty ring rather than dividing
  // by zero — a facility with no takings yet is a normal state, not an error.
  const total = Math.max(
    segments.reduce((sum, s) => sum + Math.max(s.value, 0), 0),
    1,
  );

  let offset = 0;

  return (
    <div className={cn("flex flex-wrap items-center gap-5", className)}>
      <div className="relative shrink-0" style={{ width: size, height: size }}>
        <svg width={size} height={size} viewBox={`0 0 ${size} ${size}`} className="-rotate-90" aria-hidden>
          <circle
            cx={size / 2}
            cy={size / 2}
            r={radius}
            fill="none"
            stroke="var(--border, #e5e7eb)"
            strokeWidth={stroke}
          />
          {segments.map((segment) => {
            const length = (Math.max(segment.value, 0) / total) * circumference;
            const element = (
              <circle
                key={segment.label}
                className="donut-sweep"
                cx={size / 2}
                cy={size / 2}
                r={radius}
                fill="none"
                stroke={segment.color}
                strokeWidth={stroke}
                strokeDasharray={`${length} ${circumference - length}`}
                strokeDashoffset={-offset}
                style={{ ["--sweep-from" as string]: `${-offset + length}px` }}
              />
            );
            offset += length;
            return element;
          })}
        </svg>

        {(centreValue || centreLabel) && (
          <div className="absolute inset-0 flex flex-col items-center justify-center text-center">
            {centreValue && <span className="text-sm font-semibold tabular-nums">{centreValue}</span>}
            {centreLabel && <span className="text-[11px] text-muted-foreground">{centreLabel}</span>}
          </div>
        )}
      </div>

      <ul className="min-w-0 flex-1 space-y-2">
        {segments.map((segment) => (
          <li key={segment.label} className="flex items-start gap-2 text-sm">
            <span
              className="mt-1.5 h-2 w-2 shrink-0 rounded-full"
              style={{ backgroundColor: segment.color }}
              aria-hidden
            />
            <span className="min-w-0">
              <span className="block truncate font-medium">{segment.label}</span>
              {segment.caption && (
                <span className="block text-xs text-muted-foreground">{segment.caption}</span>
              )}
            </span>
          </li>
        ))}
      </ul>
    </div>
  );
}
