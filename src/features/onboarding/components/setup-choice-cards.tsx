"use client";

import type { LucideIcon } from "lucide-react";
import { cn } from "@/lib/utils";

export interface ChoiceOption<T extends string> {
  value: T;
  title: string;
  hint: string;
  icon: LucideIcon;
}

/** Big either-or cards with a radio dot (Standard / Custom hours, By Sport / By Court): the chosen one is outlined in purple. */
export function ChoiceCards<T extends string>({ label, value, onChange, options }: { label: string; value: T; onChange: (value: T) => void; options: readonly ChoiceOption<T>[] }) {
  return (
    <div role="radiogroup" aria-label={label} className="grid gap-3 sm:grid-cols-2">
      {options.map((c) => {
        const on = value === c.value;
        return (
          <button
            key={c.value}
            type="button"
            role="radio"
            aria-checked={on}
            onClick={() => onChange(c.value)}
            className={cn(
              "flex items-center gap-4 rounded-2xl border p-4 text-left transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#4817C2]",
              on ? "border-[#4817C2] bg-[#F1EBFF]" : "border-[#E5E1EF] bg-white hover:bg-[#FBFAFE]",
            )}
          >
            <c.icon className="h-9 w-9 shrink-0 text-[#171717]" strokeWidth={1.5} aria-hidden="true" />
            <span className="min-w-0 flex-1">
              <span className="block text-lg font-semibold leading-tight">{c.title}</span>
              <span className="block text-sm font-normal text-[#666666]">{c.hint}</span>
            </span>
            <span aria-hidden="true" className={cn("flex h-6 w-6 shrink-0 items-center justify-center rounded-full border-2", on ? "border-[#4817C2]" : "border-[#B9B4C9]")}>
              {on && <span className="h-3 w-3 rounded-full bg-[#4817C2]" />}
            </span>
          </button>
        );
      })}
    </div>
  );
}
