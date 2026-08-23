"use client";

import { Button } from "@/components/ui/button";
import { QUICK_SETUP_PRESETS } from "@/features/operating-hours/constants";
import type { OperatingDay } from "@/features/operating-hours/types";

export function QuickSetup({ onApply }: { onApply: (days: OperatingDay[]) => void }) {
  return (
    <div className="space-y-2">
      <p className="text-xs font-medium text-muted-foreground">Quick setup</p>
      <div className="flex flex-wrap gap-2">
        {QUICK_SETUP_PRESETS.map((preset) => (
          <Button
            key={preset.id}
            type="button"
            variant="outline"
            size="sm"
            className="h-11"
            onClick={() => onApply(preset.build())}
          >
            <span className="flex flex-col items-start leading-tight">
              <span>{preset.label}</span>
              <span className="text-[10px] font-normal text-muted-foreground">{preset.hint}</span>
            </span>
          </Button>
        ))}
      </div>
    </div>
  );
}