"use client";

import { useState } from "react";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { cn } from "@/lib/utils";

export function CopyPricingDialog({
  open,
  onOpenChange,
  fromLabel,
  targets,
  onCopy,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  fromLabel: string;
  targets: { id: string; label: string }[];
  onCopy: (targetIds: string[]) => void;
}) {
  const [selected, setSelected] = useState<string[]>([]);

  function toggle(id: string) {
    setSelected((prev) => (prev.includes(id) ? prev.filter((d) => d !== id) : [...prev, id]));
  }

  function handleOpenChange(next: boolean) {
    if (!next) setSelected([]);
    onOpenChange(next);
  }

  return (
    <Dialog open={open} onOpenChange={handleOpenChange}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Copy {fromLabel}&apos;s pricing</DialogTitle>
          <DialogDescription>Choose which sports should use the same pricing.</DialogDescription>
        </DialogHeader>

        <div className="space-y-2">
          {targets.map((target) => {
            const checked = selected.includes(target.id);
            return (
              <button
                key={target.id}
                type="button"
                role="checkbox"
                aria-checked={checked}
                onClick={() => toggle(target.id)}
                className={cn(
                  "flex h-11 w-full items-center justify-start gap-2 rounded-md border px-3 text-sm",
                  checked ? "border-primary bg-primary/10 text-primary" : "border-input",
                )}
              >
                <span
                  className={cn(
                    "flex h-4 w-4 items-center justify-center rounded border text-[10px]",
                    checked ? "border-primary bg-primary text-primary-foreground" : "border-muted-foreground",
                  )}
                >
                  {checked ? "✓" : ""}
                </span>
                {target.label}
              </button>
            );
          })}
        </div>

        <DialogFooter>
          <Button type="button" variant="outline" onClick={() => handleOpenChange(false)}>
            Cancel
          </Button>
          <Button
            type="button"
            disabled={selected.length === 0}
            onClick={() => {
              onCopy(selected);
              handleOpenChange(false);
            }}
          >
            Copy
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}