"use client";

import { Input } from "@/components/ui/input";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import type { FinanceDateRange, FinanceDateRangePreset } from "@/features/finance/types";

const PRESET_LABELS: Record<FinanceDateRangePreset, string> = {
  TODAY: "Today",
  YESTERDAY: "Yesterday",
  THIS_WEEK: "This Week",
  LAST_WEEK: "Last Week",
  THIS_MONTH: "This Month",
  LAST_MONTH: "Last Month",
  CUSTOM: "Custom Range",
};

/**
 * Every preset resolves to actual dates on the BACKEND (facility-timezone
 * aware — resolve_finance_date_range, 0024_finance.sql). This component
 * only ever picks which preset (or which explicit start/end for CUSTOM);
 * it never computes "today" itself (spec §"Date Range" / §"Date/Time").
 */
export function DateRangePicker({ value, onChange }: { value: FinanceDateRange; onChange: (next: FinanceDateRange) => void }) {
  return (
    <div className="flex flex-wrap items-center gap-2">
      <Select value={value.preset} onValueChange={(preset) => onChange({ preset: preset as FinanceDateRangePreset, startDate: value.startDate, endDate: value.endDate })}>
        <SelectTrigger className="w-[160px]">
          <SelectValue />
        </SelectTrigger>
        <SelectContent>
          {(Object.keys(PRESET_LABELS) as FinanceDateRangePreset[]).map((preset) => (
            <SelectItem key={preset} value={preset}>
              {PRESET_LABELS[preset]}
            </SelectItem>
          ))}
        </SelectContent>
      </Select>
      {value.preset === "CUSTOM" && (
        <>
          <Input
            aria-label="Start date"
            type="date"
            value={value.startDate ?? ""}
            onChange={(e) => onChange({ ...value, startDate: e.target.value })}
            className="w-[150px]"
          />
          <span className="text-sm text-muted-foreground">to</span>
          <Input
            aria-label="End date"
            type="date"
            value={value.endDate ?? ""}
            onChange={(e) => onChange({ ...value, endDate: e.target.value })}
            className="w-[150px]"
          />
        </>
      )}
    </div>
  );
}