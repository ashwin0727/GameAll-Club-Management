"use client";

import { cn } from "@/lib/utils";

/** A small on/off switch. `onClass` is the track colour while it is on. */
export function ToggleSwitch({
  checked,
  onChange,
  label,
  onClass = "bg-primary",
}: {
  checked: boolean;
  onChange: (checked: boolean) => void;
  /** Accessible name — what the switch turns on or off. */
  label: string;
  onClass?: string;
}) {
  return (
    <button
      type="button"
      role="switch"
      aria-checked={checked}
      aria-label={label}
      onClick={() => onChange(!checked)}
      className={cn(
        "relative inline-flex h-[18px] w-[32px] shrink-0 items-center rounded-full outline-none transition-colors focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 focus-visible:ring-offset-background",
        checked ? onClass : "bg-muted-foreground/30",
      )}
    >
      <span
        aria-hidden
        className={cn(
          "inline-block h-[14px] w-[14px] rounded-full bg-white shadow transition-transform",
          checked ? "translate-x-[16px]" : "translate-x-[2px]",
        )}
      />
    </button>
  );
}
