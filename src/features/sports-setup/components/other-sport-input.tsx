"use client";

import { TextField } from "@/features/auth/components/text-field";

export interface OtherSportInputProps {
  value: string;
  onChange: (value: string) => void;
  error?: string | null;
}

export function OtherSportInput({ value, onChange, error }: OtherSportInputProps) {
  return (
    <TextField
      id="other-sport-name"
      label="Sport Name"
      placeholder="e.g. Basketball"
      maxLength={50}
      value={value}
      onChange={(e) => onChange(e.target.value)}
      error={error ?? undefined}
    />
  );
}