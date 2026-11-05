"use client";

import { Switch } from "@/components/ui/switch";
import { AMENITY_OPTIONS, type Amenities } from "@/features/facility-profile/types";

/** The five amenities, each a plain on/off toggle. */
export function AmenitiesSection({ value, onChange }: { value: Amenities; onChange: (next: Amenities) => void }) {
  return (
    <ul className="divide-y divide-border rounded-lg border border-border">
      {AMENITY_OPTIONS.map((a) => (
        <li key={a.key} className="flex items-center justify-between gap-4 px-4 py-3">
          <label htmlFor={`amenity-${a.key}`} className="cursor-pointer text-sm font-medium">
            {a.label}
          </label>
          <Switch id={`amenity-${a.key}`} checked={value[a.key]} onCheckedChange={(checked) => onChange({ ...value, [a.key]: checked })} aria-label={a.label} />
        </li>
      ))}
    </ul>
  );
}
