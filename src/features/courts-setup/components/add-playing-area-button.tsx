"use client";

import { Button } from "@/components/ui/button";

export function AddPlayingAreaButton({ label, onClick }: { label: string; onClick: () => void }) {
  return (
    <Button type="button" variant="outline" size="sm" onClick={onClick}>
      + Add {label}
    </Button>
  );
}