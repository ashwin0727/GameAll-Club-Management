"use client";

import type { CalEventKind } from "@/features/bookings/calendar-events";
import {
  EVENT_SHORT_LABEL,
  EVENT_TOGGLE_STYLE,
} from "@/features/bookings/components/booking-event-style";
import { SelectField } from "@/features/bookings/components/select-field";
import { ToggleSwitch } from "@/features/bookings/components/toggle-switch";
import { SELECT } from "@/features/bookings/components/booking-toolbar";
import { cn } from "@/lib/utils";

/** The types the calendar can show, in the order they are listed. */
export const CALENDAR_KINDS: CalEventKind[] = [
  "SESSION",
  "GUEST",
  "COACHING",
  "MAINTENANCE",
];

/**
 * The legend doubles as the show/hide controls: one switch per type, coloured like
 * that type on the calendar, and the court filter on the right.
 */
export function CalendarLegendBar({
  hidden,
  onToggle,
  courts,
  courtId,
  onCourtChange,
}: {
  hidden: ReadonlySet<CalEventKind>;
  onToggle: (kind: CalEventKind, visible: boolean) => void;
  courts: { id: string; name: string }[];
  courtId: string;
  onCourtChange: (courtId: string) => void;
}) {
  return (
    <div className="flex flex-wrap items-end justify-between gap-x-6 gap-y-3">
      <div
        className="flex flex-wrap items-center gap-x-6 gap-y-2"
        role="group"
        aria-label="Show on calendar"
      >
        {CALENDAR_KINDS.map((kind) => {
          const visible = !hidden.has(kind);
          return (
            <label
              key={kind}
              className="flex cursor-pointer items-center gap-2 text-sm"
            >
              <ToggleSwitch
                checked={visible}
                onChange={(next) => onToggle(kind, next)}
                label={`Show ${EVENT_SHORT_LABEL[kind]}`}
                onClass={EVENT_TOGGLE_STYLE[kind]}
              />
              <span className={cn(!visible && "text-muted-foreground")}>
                {EVENT_SHORT_LABEL[kind]}
              </span>
            </label>
          );
        })}
      </div>

      <div className="space-y-1">
        <p className="text-[11px] text-muted-foreground">Filter Courts</p>
        <SelectField
          wrapperClassName="w-[170px]"
          ariaLabel="Filter courts"
          value={courtId}
          onValueChange={onCourtChange}
          options={[
            { value: "", label: "All Courts" },
            ...courts.map((c) => ({ value: c.id, label: c.name })),
          ]}
          className={SELECT}
        />
      </div>
    </div>
  );
}
