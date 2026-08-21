"use client";

import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { SelectField } from "@/components/form/select-field";
import { TextField } from "@/features/auth/components/text-field";
import type { PlayingArea } from "@/features/courts-setup/types";

const TYPE_OPTIONS = [
  { value: "INDOOR", label: "Indoor" },
  { value: "OUTDOOR", label: "Outdoor" },
];

const STATUS_OPTIONS = [
  { value: "ACTIVE", label: "Active" },
  { value: "INACTIVE", label: "Inactive" },
];

const BOOKING_OPTIONS = [
  { value: "true", label: "Enabled" },
  { value: "false", label: "Disabled" },
];

export interface PlayingAreaCardProps {
  playingArea: PlayingArea;
  nameError?: string;
  onNameChange: (value: string) => void;
  onTypeChange: (value: PlayingArea["type"]) => void;
  onStatusChange: (value: PlayingArea["status"]) => void;
  onBookingEnabledChange: (value: boolean) => void;
  onRemove: () => void;
}

export function PlayingAreaCard({
  playingArea,
  nameError,
  onNameChange,
  onTypeChange,
  onStatusChange,
  onBookingEnabledChange,
  onRemove,
}: PlayingAreaCardProps) {
  return (
    <Card className="space-y-4 p-4">
      <TextField
        id={`playing-area-name-${playingArea.id}`}
        label="Name"
        placeholder="Court 1"
        maxLength={50}
        value={playingArea.name}
        onChange={(e) => onNameChange(e.target.value)}
        error={nameError}
      />

      <SelectField
        id={`playing-area-type-${playingArea.id}`}
        label="Type"
        options={TYPE_OPTIONS}
        value={playingArea.type}
        onValueChange={(value) => onTypeChange(value as PlayingArea["type"])}
      />

      <SelectField
        id={`playing-area-status-${playingArea.id}`}
        label="Status"
        options={STATUS_OPTIONS}
        value={playingArea.status}
        onValueChange={(value) => onStatusChange(value as PlayingArea["status"])}
      />

      <SelectField
        id={`playing-area-booking-${playingArea.id}`}
        label="Available for Booking"
        options={BOOKING_OPTIONS}
        value={String(playingArea.bookingEnabled)}
        onValueChange={(value) => onBookingEnabledChange(value === "true")}
      />

      <div className="flex justify-end">
        <Button type="button" variant="ghost" size="sm" onClick={onRemove}>
          Remove
        </Button>
      </div>
    </Card>
  );
}