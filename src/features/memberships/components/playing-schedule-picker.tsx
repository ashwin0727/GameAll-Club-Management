"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import { CalendarDays, Check, Info } from "lucide-react";
import { SelectField } from "@/components/shared/select-field";
import { getPlayingAreasService } from "@/services/playing-areas";
import { getSportsService } from "@/services/sports";
import { useUiStore } from "@/stores/ui-store";
import { DAY_OPTIONS } from "@/features/memberships/slot-form";
import { DAY_PRESETS, HOUR_BLOCKS, matchingPreset, type PlayingScheduleDraft } from "@/features/memberships/playing-schedule";
import type { PlayingArea } from "@/features/courts-setup/types";
import { cn } from "@/lib/utils";

const NOTES = [
  "Selected time slots will be reserved for this member throughout the membership period.",
  "Guest bookings will not be allowed during these times.",
  "If you want to allow guest bookings for a particular date, you can release the slot later from the schedule.",
];

/**
 * Step 3, "Select Playing Schedule": which days, which court, and which hours — each hour its
 * own toggle rather than a single start/end range, so a member can hold two separate windows
 * in a day (e.g. 6-7 AM and 2-4 PM) instead of only one continuous block.
 */
export function PlayingSchedulePicker({
  facilityId,
  value,
  onChange,
}: {
  facilityId: string;
  value: PlayingScheduleDraft;
  onChange: (next: PlayingScheduleDraft) => void;
}) {
  const [areas, setAreas] = useState<PlayingArea[]>([]);
  const activeSportId = useUiStore((s) => s.activeFacilitySportId);

  // Every default below reads and writes through this ref instead of the `value` prop
  // directly. The sport/court fetch is async — it can resolve after another effect (or the
  // member's own click) has already updated the schedule, and spreading a stale `value`
  // closure at that point would silently overwrite that change, wiping out e.g. the Mon-Fri
  // default the moment the court list loads. The ref always holds the latest schedule.
  const valueRef = useRef(value);
  useEffect(() => {
    valueRef.current = value;
  }, [value]);

  useEffect(() => {
    let cancelled = false;
    Promise.all([getSportsService().getFacilitySports(facilityId), getPlayingAreasService().getPlayingAreas(facilityId)])
      .then(([fs, playingAreas]) => {
        if (cancelled) return;
        const enabled = fs.filter((f) => f.enabled);
        setAreas(playingAreas.filter((a) => !a.archived && a.status === "ACTIVE" && a.bookingEnabled));
        // Defaults to the sport picked in the top bar, same as every other sport-scoped page —
        // falling back to the facility's first onboarded sport if that one isn't enabled here.
        if (!valueRef.current.facilitySportId) {
          const preferred = enabled.find((f) => f.id === activeSportId) ?? enabled[0];
          if (preferred) onChange({ ...valueRef.current, facilitySportId: preferred.id });
        }
      })
      .catch(() => undefined);
    return () => {
      cancelled = true;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps -- runs once per facility; reads valueRef, not value
  }, [facilityId]);

  // The Mon - Fri default is seeded once in the wizard's own initial state (see
  // add-member-wizard-page.tsx), not here — this component unmounts and remounts every time
  // the step is left and revisited, so any seeding effect here can't distinguish "never
  // touched" from "the member picked Custom and is still choosing days", and would keep
  // stomping the latter back to Mon - Fri on every return visit.

  const courtsForSport = useMemo(
    () => areas.filter((a) => a.facilitySportId === value.facilitySportId),
    [areas, value.facilitySportId],
  );
  const courtOptions = courtsForSport.map((c) => ({ value: c.id, label: c.name }));

  // Defaults to the first court once the list loads, rather than leaving the picker blank.
  useEffect(() => {
    if (!valueRef.current.courtId && courtsForSport.length > 0) {
      onChange({ ...valueRef.current, courtId: courtsForSport[0]!.id });
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps -- only reacts to the court list itself
  }, [courtsForSport]);

  const preset = matchingPreset(value.daysOfWeek);

  function toggleDay(day: number) {
    const next = value.daysOfWeek.includes(day) ? value.daysOfWeek.filter((d) => d !== day) : [...value.daysOfWeek, day];
    onChange({ ...value, daysOfWeek: next });
  }

  function toggleHour(start: string) {
    const next = value.times.includes(start) ? value.times.filter((t) => t !== start) : [...value.times, start];
    onChange({ ...value, times: next });
  }

  return (
    <div className="space-y-6">
      <section className="space-y-3">
        <div className="flex items-start gap-2.5">
          <span className="flex h-6 w-6 shrink-0 items-center justify-center rounded-full bg-muted text-xs font-semibold text-muted-foreground">
            1
          </span>
          <div>
            <p className="text-sm font-bold text-black dark:text-foreground">Select Playing Days</p>
            <p className="text-xs text-muted-foreground">Choose the days the member will have access to the court.</p>
          </div>
        </div>

        <div className="grid grid-cols-2 gap-2 sm:grid-cols-4">
          {DAY_PRESETS.map((p) => (
            <button
              key={p.key}
              type="button"
              // "Custom" itself carries no fixed day set — clicking it clears the days so the
              // checkboxes below start empty and ready to pick individually, rather than doing
              // nothing (which looked like the button didn't work).
              onClick={() => onChange({ ...value, daysOfWeek: p.key === "custom" ? [] : p.days })}
              className={cn(
                "h-10 rounded-lg border text-sm font-medium transition-colors",
                preset === p.key
                  ? "border-[#0B9B63] bg-[#0B9B63] text-white"
                  : "border-input bg-card text-foreground hover:bg-accent",
              )}
            >
              {p.label}
            </button>
          ))}
        </div>

        <div className="flex flex-wrap gap-2">
          {DAY_OPTIONS.map((d) => {
            const on = value.daysOfWeek.includes(d.value);
            return (
              <button
                key={d.value}
                type="button"
                onClick={() => toggleDay(d.value)}
                className={cn(
                  "flex h-9 items-center gap-2 rounded-lg border px-3 text-sm transition-colors",
                  on ? "border-[#0B9B63] bg-success/10 text-[#0B7A55]" : "border-input bg-card text-foreground hover:bg-accent",
                )}
              >
                <span
                  className={cn(
                    "flex h-4 w-4 items-center justify-center rounded border-2",
                    on ? "border-[#0B9B63] bg-[#0B9B63]" : "border-input",
                  )}
                >
                  {on && <Check className="h-2.5 w-2.5 text-white" strokeWidth={4} aria-hidden />}
                </span>
                {d.label}
              </button>
            );
          })}
        </div>
      </section>

      <section className="space-y-3">
        <div className="flex flex-wrap items-start justify-between gap-3">
          <div className="flex items-start gap-2.5">
            <span className="flex h-6 w-6 shrink-0 items-center justify-center rounded-full bg-muted text-xs font-semibold text-muted-foreground">
              2
            </span>
            <div>
              <p className="text-sm font-bold text-black dark:text-foreground">Select Time Slot(s)</p>
              <p className="text-xs text-muted-foreground">Choose one or more hours for the selected days.</p>
            </div>
          </div>

          <SelectField
            wrapperClassName="w-[140px]"
            ariaLabel="Court"
            value={value.courtId}
            onValueChange={(v) => onChange({ ...value, courtId: v })}
            options={courtOptions.length > 0 ? courtOptions : [{ value: "", label: "No courts" }]}
            className="h-9 rounded-lg border border-input bg-card px-3 text-sm outline-none transition-colors hover:border-foreground/30"
          />
        </div>

        <div className="grid grid-cols-2 gap-2 sm:grid-cols-3">
          {HOUR_BLOCKS.map((b) => {
            const on = value.times.includes(b.start);
            return (
              <button
                key={b.start}
                type="button"
                onClick={() => toggleHour(b.start)}
                aria-pressed={on}
                className={cn(
                  "flex h-11 items-center justify-between gap-2 rounded-lg border px-3 text-sm transition-colors",
                  on ? "border-[#0B9B63] bg-success/10 font-medium text-[#0B7A55]" : "border-input bg-card hover:bg-accent",
                )}
              >
                {b.label}
                <span
                  className={cn(
                    "flex h-4 w-4 shrink-0 items-center justify-center rounded-full border-2",
                    on ? "border-[#0B9B63] bg-[#0B9B63]" : "border-input",
                  )}
                >
                  {on && <Check className="h-2.5 w-2.5 text-white" strokeWidth={4} aria-hidden />}
                </span>
              </button>
            );
          })}
        </div>
      </section>

      <div className="rounded-xl bg-success/10 p-4">
        <div className="flex items-center gap-2">
          <Info className="h-4 w-4 text-[#0B7A55]" aria-hidden />
          <p className="text-sm font-semibold text-[#0B7A55]">Important Note</p>
        </div>
        <ul className="mt-2 space-y-1 pl-1 text-xs text-foreground/80">
          {NOTES.map((n) => (
            <li key={n} className="flex items-start gap-2">
              <span className="mt-1.5 h-1 w-1 shrink-0 rounded-full bg-[#0B7A55]" aria-hidden />
              {n}
            </li>
          ))}
        </ul>
      </div>

      {value.times.length === 0 && (
        <p className="flex items-center gap-2 text-xs text-muted-foreground">
          <CalendarDays className="h-3.5 w-3.5" aria-hidden />
          No dedicated court time — the member can book like any guest, or you can select hours above.
        </p>
      )}
    </div>
  );
}
