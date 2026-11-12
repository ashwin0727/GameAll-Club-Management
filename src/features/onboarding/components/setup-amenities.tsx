"use client";

import * as React from "react";
import { Armchair, BriefcaseMedical, Car, Coffee, Droplets, Dumbbell, Lock, Plus, ShowerHead, Shirt, Bath, Bike, Wifi, X, type LucideIcon } from "lucide-react";
import { FACILITY_AMENITIES, MAX_CUSTOM_AMENITIES, type AmenityKey } from "@/features/facility-profile/types";
import { FieldError, fieldControl } from "@/features/onboarding/components/setup-fields";
import { cn } from "@/lib/utils";

const ICONS: Record<AmenityKey, LucideIcon> = {
  car_parking: Car,
  two_wheeler_parking: Bike,
  restroom: Bath,
  changing_room: Shirt,
  shower: ShowerHead,
  drinking_water: Droplets,
  seating_area: Armchair,
  cafeteria: Coffee,
  wifi: Wifi,
  lockers: Lock,
  equipment_rental: Dumbbell,
  first_aid: BriefcaseMedical,
};

function Tile({ checked, onToggle, icon: Icon, label, id }: { checked: boolean; onToggle: () => void; icon: LucideIcon; label: string; id: string }) {
  return (
    <label
      htmlFor={id}
      className={cn(
        "flex h-12 cursor-pointer items-center gap-3 rounded-lg border px-3 text-sm font-medium transition-colors focus-within:ring-2 focus-within:ring-[#4817C2]",
        checked ? "border-[#4817C2]/40 bg-[#F1EBFF]" : "border-[#E5E1EF] bg-white hover:bg-[#FBFAFE]",
      )}
    >
      <input id={id} type="checkbox" checked={checked} onChange={onToggle} className="h-5 w-5 shrink-0 cursor-pointer rounded accent-[#4817C2]" />
      <Icon className="h-5 w-5 shrink-0 text-[#171717]" aria-hidden="true" />
      <span className="truncate">{label}</span>
    </label>
  );
}

/** The 12 standard amenities as checkable tiles, plus owner-typed custom ones ("Add Custom Amenity"). */
export function SetupAmenities({
  keys,
  onKeysChange,
  custom,
  onCustomChange,
  validateCustom,
  error,
}: {
  keys: string[];
  onKeysChange: (keys: string[]) => void;
  custom: string[];
  onCustomChange: (names: string[]) => void;
  /** Returns a message when the typed name is not acceptable (too short, duplicate, ...). */
  validateCustom: (name: string, existing: string[]) => string | null;
  error?: string;
}) {
  const [adding, setAdding] = React.useState(false);
  const [draft, setDraft] = React.useState("");
  const [problem, setProblem] = React.useState<string | null>(null);

  function toggle(key: string) {
    onKeysChange(keys.includes(key) ? keys.filter((k) => k !== key) : [...keys, key]);
  }

  function addCustom() {
    const name = draft.trim().replace(/\s+/g, " ");
    const why = validateCustom(name, custom);
    if (why) {
      setProblem(why);
      return;
    }
    onCustomChange([...custom, name]);
    setDraft("");
    setProblem(null);
    setAdding(false);
  }

  const atLimit = custom.length >= MAX_CUSTOM_AMENITIES;

  return (
    <div>
      <div className="mb-4 flex flex-wrap items-center justify-between gap-3">
        <p className="text-sm font-normal text-[#666666]">Select the amenities available at your facility.</p>
        <div className="flex items-center gap-3">
          <span className="text-xs font-normal text-[#666666]">Can&apos;t find an amenity?</span>
          <button
            type="button"
            disabled={atLimit}
            onClick={() => setAdding((v) => !v)}
            className="flex h-9 items-center gap-1.5 rounded-lg border border-[#4817C2]/40 bg-[#F8F4FF] px-3 text-sm font-semibold text-[#4817C2] hover:bg-[#F1EBFF] disabled:opacity-50"
          >
            <Plus className="h-4 w-4" aria-hidden="true" />
            Add Custom Amenity
          </button>
        </div>
      </div>

      {adding && (
        <div className="mb-4 rounded-xl border border-[#E5E1EF] bg-[#FBFAFE] p-3">
          <div className="flex flex-wrap items-center gap-2">
            <input
              autoFocus
              value={draft}
              maxLength={30}
              aria-label="Custom amenity name"
              placeholder="e.g. Physiotherapy room"
              onChange={(e) => {
                setDraft(e.target.value);
                setProblem(null);
              }}
              onKeyDown={(e) => {
                if (e.key === "Enter") {
                  e.preventDefault();
                  addCustom();
                } else if (e.key === "Escape") setAdding(false);
              }}
              className={cn(fieldControl, "h-10 min-w-[200px] flex-1", problem && "border-[#C62828]")}
            />
            <button type="button" onClick={addCustom} className="h-10 rounded-lg bg-[#4817C2] px-4 text-sm font-semibold text-white hover:bg-[#39109F]">
              Add
            </button>
            <button type="button" onClick={() => { setAdding(false); setProblem(null); setDraft(""); }} className="h-10 rounded-lg border border-[#E5E1EF] bg-white px-4 text-sm font-semibold hover:bg-[#FBFAFE]">
              Cancel
            </button>
          </div>
          {problem && <FieldError>{problem}</FieldError>}
        </div>
      )}

      <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-4 xl:grid-cols-6">
        {FACILITY_AMENITIES.map((a) => (
          <Tile key={a.key} id={`amenity-${a.key}`} checked={keys.includes(a.key)} onToggle={() => toggle(a.key)} icon={ICONS[a.key]} label={a.label} />
        ))}
        {custom.map((name) => (
          <div key={name} className="flex h-12 items-center gap-3 rounded-lg border border-[#4817C2]/40 bg-[#F1EBFF] px-3 text-sm font-medium">
            <span className="flex h-5 w-5 shrink-0 items-center justify-center rounded bg-[#4817C2] text-[11px] text-white" aria-hidden="true">
              ✓
            </span>
            <span className="min-w-0 flex-1 truncate">{name}</span>
            <button type="button" aria-label={`Remove ${name}`} onClick={() => onCustomChange(custom.filter((n) => n !== name))} className="rounded-full p-0.5 text-[#666666] hover:bg-white hover:text-[#171717]">
              <X className="h-4 w-4" aria-hidden="true" />
            </button>
          </div>
        ))}
      </div>
      {error && <FieldError>{error}</FieldError>}
    </div>
  );
}
