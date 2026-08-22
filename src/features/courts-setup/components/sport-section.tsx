"use client";

import { AddPlayingAreaButton } from "@/features/courts-setup/components/add-playing-area-button";
import { PlayingAreaCard } from "@/features/courts-setup/components/playing-area-card";
import { playingAreaLabelFor, pluralizeLabel } from "@/features/courts-setup/constants";
import type { PlayingArea } from "@/features/courts-setup/types";
import type { Sport } from "@/features/sports-setup/types";

export interface SportSectionProps {
  sport: Sport;
  sportDisplayName: string;
  playingAreas: PlayingArea[];
  nameErrors: Record<string, string>;
  sectionError?: string;
  onAdd: () => void;
  onNameChange: (id: string, value: string) => void;
  onTypeChange: (id: string, value: PlayingArea["type"]) => void;
  onStatusChange: (id: string, value: PlayingArea["status"]) => void;
  onBookingEnabledChange: (id: string, value: boolean) => void;
  onRemoveRequest: (id: string) => void;
}

export function SportSection({
  sport,
  sportDisplayName,
  playingAreas,
  nameErrors,
  sectionError,
  onAdd,
  onNameChange,
  onTypeChange,
  onStatusChange,
  onBookingEnabledChange,
  onRemoveRequest,
}: SportSectionProps) {
  const label = playingAreaLabelFor(sport.code);

  return (
    <section className="space-y-4 rounded-xl border border-border bg-card p-5 sm:p-6">
      <div className="flex items-center justify-between gap-3">
        <div className="flex items-center gap-2">
          <span className="text-2xl" aria-hidden="true">
            {sport.icon}
          </span>
          <h2 className="text-sm font-semibold">{sportDisplayName}</h2>
        </div>
        <span className="text-xs text-muted-foreground">
          {playingAreas.length} {pluralizeLabel(label, playingAreas.length)}
        </span>
      </div>

      <p className="text-xs text-muted-foreground">
        Add the {label.toLowerCase()}s available for {sportDisplayName}.
      </p>

      {playingAreas.length === 0 ? (
        <div className="space-y-3 rounded-lg border border-dashed border-input p-6 text-center">
          <p className="text-sm text-muted-foreground">No {label.toLowerCase()}s added yet.</p>
          <p className="text-xs text-muted-foreground">
            Add the {label.toLowerCase()}s available for this sport.
          </p>
          <AddPlayingAreaButton label={label} onClick={onAdd} />
        </div>
      ) : (
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
          {playingAreas.map((area) => (
            <PlayingAreaCard
              key={area.id}
              playingArea={area}
              nameError={nameErrors[area.id]}
              onNameChange={(value) => onNameChange(area.id, value)}
              onTypeChange={(value) => onTypeChange(area.id, value)}
              onStatusChange={(value) => onStatusChange(area.id, value)}
              onBookingEnabledChange={(value) => onBookingEnabledChange(area.id, value)}
              onRemove={() => onRemoveRequest(area.id)}
            />
          ))}
        </div>
      )}

      {playingAreas.length > 0 && <AddPlayingAreaButton label={label} onClick={onAdd} />}

      {sectionError && <p className="text-sm text-destructive">{sectionError}</p>}
    </section>
  );
}