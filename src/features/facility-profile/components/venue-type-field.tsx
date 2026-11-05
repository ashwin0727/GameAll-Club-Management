"use client";

import { Label } from "@/components/ui/label";
import { VENUE_TYPE_OPTIONS, type VenueType } from "@/features/facility-profile/types";
import { cn } from "@/lib/utils";

/** Indoor or Outdoor: exactly two choices, shown as two cards. */
export function VenueTypeField({ value, onChange, error }: { value: VenueType | "" | undefined; onChange: (value: VenueType) => void; error?: string }) {
  return (
    <fieldset className="space-y-2">
      <Label asChild>
        <legend>Venue Type</legend>
      </Label>
      <div role="radiogroup" aria-label="Venue type" className="grid gap-3 sm:grid-cols-2">
        {VENUE_TYPE_OPTIONS.map((o) => {
          const on = value === o.value;
          return (
            <button
              key={o.value}
              type="button"
              role="radio"
              aria-checked={on}
              onClick={() => onChange(o.value)}
              className={cn(
                "rounded-lg border p-3.5 text-left transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring",
                on ? "border-primary bg-primary/5" : "border-input hover:border-primary/50",
              )}
            >
              <span className="flex items-center gap-2 text-sm font-semibold">
                <span aria-hidden className={cn("flex h-4 w-4 items-center justify-center rounded-full border", on ? "border-primary" : "border-input")}>
                  {on && <span className="h-2 w-2 rounded-full bg-primary" />}
                </span>
                {o.label}
              </span>
              <span className="mt-1 block pl-6 text-xs text-muted-foreground">{o.hint}</span>
            </button>
          );
        })}
      </div>
      {error && (
        <p role="alert" className="text-xs text-destructive">
          {error}
        </p>
      )}
    </fieldset>
  );
}
