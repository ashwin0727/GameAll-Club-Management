"use client";

import { Check } from "lucide-react";
import { cn } from "@/lib/utils";
import type { Sport } from "@/features/sports-setup/types";

export interface SportCardProps {
  sport: Sport;
  selected: boolean;
  onToggle: (sportId: string) => void;
}

/**
 * The entire card is one button — per spec, touching anywhere inside
 * toggles selection, never just a small checkbox. min-h-12 (48px) meets
 * the "prefer 48px+" touch-target guidance.
 */
export function SportCard({ sport, selected, onToggle }: SportCardProps) {
  return (
    <button
      type="button"
      role="checkbox"
      aria-checked={selected}
      aria-label={`${sport.name} — ${sport.description}`}
      onClick={() => onToggle(sport.id)}
      className={cn(
        "flex min-h-12 w-full items-center gap-3 rounded-xl border p-4 text-left transition-colors duration-150",
        selected ? "border-primary bg-primary/5" : "border-border bg-card hover:border-muted-foreground/40",
      )}
    >
      <span className="text-2xl" aria-hidden="true">
        {sport.icon}
      </span>
      <span className="min-w-0 flex-1">
        <span className="block text-sm font-semibold text-foreground">{sport.name}</span>
        <span className="block truncate text-xs text-muted-foreground">{sport.description}</span>
      </span>
      {selected && (
        <span className="flex h-5 w-5 shrink-0 items-center justify-center rounded-full bg-primary text-primary-foreground">
          <Check className="h-3.5 w-3.5" aria-hidden="true" />
        </span>
      )}
    </button>
  );
}