"use client";

import * as React from "react";
import { Check, Layers, Plus, Trash2 } from "lucide-react";
import { OTHER_SPORT_CODE } from "@/features/sports-setup/constants";
import type { Sport } from "@/features/sports-setup/types";
import { CardHeading, FieldError, SetupCard, fieldControl } from "@/features/onboarding/components/setup-fields";
import { cn } from "@/lib/utils";

/** The order the sports are shown in (the design's), then anything else the catalogue holds. */
const DISPLAY_ORDER = ["BADMINTON", "FOOTBALL", "CRICKET", "TENNIS", "BASKETBALL", "PICKLEBALL"];

export function orderSports(sports: Sport[]): Sport[] {
  const rank = (s: Sport) => {
    const i = DISPLAY_ORDER.indexOf(s.code);
    return i === -1 ? DISPLAY_ORDER.length : i;
  };
  return sports.filter((s) => s.code !== OTHER_SPORT_CODE).sort((a, b) => rank(a) - rank(b));
}

/** The icon a venue's own sport shows (the catalogue's "Other" icon is a plus sign, which would read as another Add button). */
export const CUSTOM_SPORT_ICON = "🏅";

const TILE = "relative flex h-24 w-full flex-col items-center justify-center gap-1.5 rounded-xl border px-2 text-center text-sm font-medium";

/**
 * "Select Sports": a tile per catalogue sport (tick to offer it), a tile for each sport the owner added themselves (with its own delete
 * button), and "Add Sport" for as many more as they like.
 */
export function SportsPicker({
  sports,
  selectedIds,
  onToggle,
  customSports,
  onAddCustom,
  onRemoveCustom,
  error,
}: {
  sports: Sport[];
  selectedIds: string[];
  onToggle: (sportId: string) => void;
  /** The names of the sports the owner added. */
  customSports: string[];
  /** Adds a sport by name; returns a message when it can't be added (too short, already there), else null. */
  onAddCustom: (name: string) => string | null;
  onRemoveCustom: (name: string) => void;
  error?: string | null;
}) {
  const [adding, setAdding] = React.useState(false);
  const [name, setName] = React.useState("");
  const [problem, setProblem] = React.useState<string | null>(null);

  function confirmAdd() {
    const why = onAddCustom(name);
    if (why) {
      setProblem(why);
      return;
    }
    setName("");
    setProblem(null);
    setAdding(false);
  }

  function cancelAdd() {
    setAdding(false);
    setName("");
    setProblem(null);
  }

  return (
    <SetupCard className="p-4 sm:p-4">
      <CardHeading icon={<Layers className="h-7 w-7" aria-hidden="true" />} title="Select Sports" description="Choose the sports you offer at your venue." />
      <ul className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-7">
        {orderSports(sports).map((sport) => {
          const on = selectedIds.includes(sport.id);
          return (
            <li key={sport.id}>
              <button
                type="button"
                role="checkbox"
                aria-checked={on}
                aria-label={sport.name}
                onClick={() => onToggle(sport.id)}
                className={cn(TILE, "transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#4817C2]", on ? "border-[#4817C2] bg-[#F1EBFF]" : "border-[#E5E1EF] bg-white hover:bg-[#FBFAFE]")}
              >
                <span className="text-3xl leading-none" aria-hidden="true">
                  {sport.icon}
                </span>
                {sport.name}
                <span
                  aria-hidden="true"
                  className={cn("absolute right-2 top-2 flex h-5 w-5 items-center justify-center rounded border", on ? "border-[#4817C2] bg-[#4817C2] text-white" : "border-[#E5E1EF] bg-white")}
                >
                  {on && <Check className="h-3.5 w-3.5" strokeWidth={3} />}
                </span>
              </button>
            </li>
          );
        })}

        {customSports.map((custom) => (
          <li key={custom}>
            <div role="group" aria-label={custom} className={cn(TILE, "border-[#4817C2] bg-[#F1EBFF]")}>
              <span className="text-3xl leading-none" aria-hidden="true">
                {CUSTOM_SPORT_ICON}
              </span>
              <span className="line-clamp-1 max-w-full break-all">{custom}</span>
              <button
                type="button"
                aria-label={`Remove ${custom}`}
                onClick={() => onRemoveCustom(custom)}
                className="absolute right-1.5 top-1.5 flex h-7 w-7 items-center justify-center rounded-lg text-[#C62828] hover:bg-white focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#C62828]"
              >
                <Trash2 className="h-4 w-4" aria-hidden="true" />
              </button>
            </div>
          </li>
        ))}

        <li>
          <button
            type="button"
            onClick={() => setAdding(true)}
            aria-expanded={adding}
            className="flex h-24 w-full flex-col items-center justify-center gap-1 rounded-xl border border-dashed border-[#4817C2]/60 bg-[#F8F4FF] text-sm font-semibold text-[#4817C2] hover:bg-[#F1EBFF] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#4817C2]"
          >
            <Plus className="h-6 w-6" aria-hidden="true" />
            Add Sport
          </button>
        </li>
      </ul>

      {adding && (
        <div className="mt-4 rounded-xl border border-[#E5E1EF] bg-[#FBFAFE] p-3">
          <label htmlFor="custom-sport" className="mb-1.5 block text-sm font-semibold">
            Sport name
          </label>
          <div className="flex flex-wrap gap-2">
            <input
              id="custom-sport"
              autoFocus
              value={name}
              maxLength={50}
              placeholder="e.g. Table Tennis"
              aria-invalid={problem ? true : undefined}
              onChange={(e) => {
                setName(e.target.value);
                setProblem(null);
              }}
              onKeyDown={(e) => {
                if (e.key === "Enter") {
                  e.preventDefault();
                  confirmAdd();
                } else if (e.key === "Escape") cancelAdd();
              }}
              className={cn(fieldControl, "h-10 min-w-[200px] flex-1", problem && "border-[#C62828]")}
            />
            <button type="button" onClick={confirmAdd} className="h-10 rounded-lg bg-[#4817C2] px-4 text-sm font-semibold text-white hover:bg-[#39109F]">
              Add
            </button>
            <button type="button" onClick={cancelAdd} className="h-10 rounded-lg border border-[#E5E1EF] bg-white px-4 text-sm font-semibold hover:bg-[#FBFAFE]">
              Cancel
            </button>
          </div>
          {problem && <FieldError>{problem}</FieldError>}
        </div>
      )}

      {error && <FieldError>{error}</FieldError>}
    </SetupCard>
  );
}
