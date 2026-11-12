"use client";

import * as React from "react";
import { CalendarClock, Clock, Info, SlidersHorizontal } from "lucide-react";
import { Switch } from "@/components/ui/switch";
import { ChoiceCards } from "@/features/onboarding/components/setup-choice-cards";
import { CardHeading, FieldError, SetupCard, SetupSelect } from "@/features/onboarding/components/setup-fields";
import { DISPLAY_ORDER } from "@/features/operating-hours/constants";
import {
  SHORT_DAY,
  TIME_OPTIONS,
  describePlan,
  formatClock,
  formatHours,
  orderedPlans,
  weeklyMinutes,
  type BreakTime,
  type DayPlan,
  type HoursMode,
} from "@/features/operating-hours/setup-model";
import { DAY_LABELS, type DayOfWeek } from "@/features/operating-hours/types";
import { useContainerWide } from "@/features/sports-courts/use-container-wide";
import { cn } from "@/lib/utils";

// ── time field ─────────────────────────────────────────────────────────────

/**
 * A time chosen from a list (every half hour, in a rounded menu with the chosen time highlighted). A list beats the browser's own time
 * input here: it looks the same everywhere, works with the keyboard (type "6" to jump to 6:00, arrows, Enter) and can't produce an
 * impossible time. A time already saved that is not on the half hour (say 6:15 AM) is kept as an extra choice.
 */
export function TimeField({
  id,
  ariaLabel,
  value,
  onChange,
  invalid,
  disabled,
  placeholder = "Select",
}: {
  id: string;
  ariaLabel: string;
  value: string;
  onChange: (value: string) => void;
  invalid?: boolean;
  disabled?: boolean;
  placeholder?: string;
}) {
  const options = value && !TIME_OPTIONS.some((o) => o.value === value) ? [{ value, label: formatClock(value) }, ...TIME_OPTIONS] : TIME_OPTIONS;
  return (
    <SetupSelect
      id={id}
      ariaLabel={ariaLabel}
      value={value}
      onChange={onChange}
      options={options}
      placeholder={placeholder}
      invalid={invalid}
      disabled={disabled}
      icon={<Clock className="h-4 w-4" aria-hidden="true" />}
    />
  );
}

// ── day chips ──────────────────────────────────────────────────────────────

/** Mon ... Sun as tick-able chips. */
export function DayChips({ value, onChange, idPrefix }: { value: DayOfWeek[]; onChange: (next: DayOfWeek[]) => void; idPrefix: string }) {
  return (
    <div className="flex flex-wrap gap-2" role="group" aria-label="Operating days">
      {DISPLAY_ORDER.map((d) => {
        const on = value.includes(d);
        return (
          <label
            key={d}
            htmlFor={`${idPrefix}-${d}`}
            className={cn(
              "flex h-10 cursor-pointer items-center gap-2 rounded-lg border px-3 text-sm font-semibold transition-colors focus-within:ring-2 focus-within:ring-[#4817C2]",
              on ? "border-[#4817C2]/50 bg-[#F1EBFF] text-[#4817C2]" : "border-[#E5E1EF] bg-white hover:bg-[#FBFAFE]",
            )}
          >
            <input
              id={`${idPrefix}-${d}`}
              type="checkbox"
              checked={on}
              onChange={(e) => onChange(e.target.checked ? [...value, d] : value.filter((x) => x !== d))}
              className="h-4 w-4 cursor-pointer rounded accent-[#4817C2]"
            />
            <span title={DAY_LABELS[d]}>{SHORT_DAY[d]}</span>
          </label>
        );
      })}
    </div>
  );
}

// ── mode cards ─────────────────────────────────────────────────────────────

export function ModeCards({ mode, onChange }: { mode: HoursMode; onChange: (mode: HoursMode) => void }) {
  return (
    <ChoiceCards
      label="How do you set your hours?"
      value={mode}
      onChange={onChange}
      options={[
        { value: "standard", title: "Standard Hours", hint: "Same operating hours for selected days", icon: CalendarClock },
        { value: "custom", title: "Custom Hours", hint: "Set different hours for each day", icon: SlidersHorizontal },
      ]}
    />
  );
}

// ── standard hours ─────────────────────────────────────────────────────────

export function StandardPanel({
  openDays,
  onDays,
  open,
  close,
  onOpen,
  onClose,
  is24Hours,
  onIs24Hours,
  dailyTotal,
  daysError,
  timeError,
}: {
  openDays: DayOfWeek[];
  onDays: (next: DayOfWeek[]) => void;
  open: string;
  close: string;
  onOpen: (v: string) => void;
  onClose: (v: string) => void;
  is24Hours: boolean;
  onIs24Hours: (v: boolean) => void;
  dailyTotal: string;
  daysError?: string;
  timeError?: string;
}) {
  return (
    <SetupCard className="p-4 sm:p-5">
      <CardHeading icon={<CalendarClock className="h-7 w-7" aria-hidden="true" />} title="Set Operating Days & Hours" />
      <div className="space-y-5">
        <div>
          <p className="mb-2 text-sm font-semibold">
            Operating Days <span className="text-[#C62828]">*</span>
          </p>
          <DayChips value={openDays} onChange={onDays} idPrefix="std-day" />
          {daysError && <FieldError>{daysError}</FieldError>}
        </div>

        <div>
          <p className="mb-2 text-sm font-semibold">
            Working Hours <span className="text-[#C62828]">*</span>
          </p>
          {is24Hours ? (
            <p className="flex h-11 items-center rounded-lg bg-[#F1EBFF] px-3 text-sm font-semibold text-[#4817C2]">Open all day, {dailyTotal}</p>
          ) : (
            <div className="grid items-end gap-3 sm:grid-cols-[1fr_1fr_auto]">
              <div>
                <label htmlFor="std-open" className="mb-1 block text-sm">
                  Opens At
                </label>
                <TimeField id="std-open" ariaLabel="Opens at" value={open} onChange={onOpen} invalid={!!timeError} />
              </div>
              <div>
                <label htmlFor="std-close" className="mb-1 block text-sm">
                  Closes At
                </label>
                <TimeField id="std-close" ariaLabel="Closes at" value={close} onChange={onClose} invalid={!!timeError} />
              </div>
              <div>
                <span className="mb-1 block text-sm">Total Hours</span>
                <span className="flex h-11 items-center justify-center rounded-lg bg-[#EDE7FF] px-4 text-sm font-semibold text-[#4817C2]" data-testid="daily-total">
                  {dailyTotal}
                </span>
              </div>
            </div>
          )}
          {timeError && <FieldError>{timeError}</FieldError>}
          <label className="mt-3 flex w-fit cursor-pointer items-center gap-2 text-sm font-medium">
            <input type="checkbox" checked={is24Hours} onChange={(e) => onIs24Hours(e.target.checked)} className="h-4 w-4 cursor-pointer rounded accent-[#4817C2]" />
            Open 24 hours
          </label>
        </div>
      </div>
    </SetupCard>
  );
}

// ── weekly preview ─────────────────────────────────────────────────────────

export function WeeklyPreview({ plans, brk }: { plans: DayPlan[]; brk?: BreakTime | null }) {
  return (
    <SetupCard className="p-4 sm:p-5">
      <CardHeading icon={<CalendarClock className="h-7 w-7" aria-hidden="true" />} title="Weekly Schedule Preview" description="Here's how your facility will be available for bookings." />
      <div className="overflow-hidden rounded-lg border border-[#EFECF6]">
        <div className="grid grid-cols-[64px_1fr_90px] bg-[#F1EBFF] px-3 py-2 text-xs font-semibold sm:grid-cols-[80px_1fr_110px]">
          <span>Day</span>
          <span>Operating Hours</span>
          <span>Status</span>
        </div>
        <ul>
          {orderedPlans(plans).map((p) => (
            <li key={p.dayOfWeek} className="grid grid-cols-[64px_1fr_90px] items-center border-t border-[#EFECF6] px-3 py-2 text-sm sm:grid-cols-[80px_1fr_110px]">
              <span className="font-medium">{SHORT_DAY[p.dayOfWeek]}</span>
              <span className={cn(!p.isOpen && "text-[#666666]")}>{p.isOpen ? describePlan(p) : "—"}</span>
              <span className="flex items-center gap-1.5">
                <span aria-hidden="true" className={cn("h-2 w-2 rounded-full", p.isOpen ? "bg-[#2E7D32]" : "bg-[#C62828]")} />
                <span className={cn(p.isOpen ? "text-[#2E7D32]" : "text-[#C62828]")}>{p.isOpen ? "Open" : "Closed"}</span>
              </span>
            </li>
          ))}
        </ul>
      </div>
      {brk && (
        <p className="mt-3 text-xs font-normal text-[#666666]">
          Daily break: {formatClock(brk.start)} – {formatClock(brk.end)} (not bookable).
        </p>
      )}
    </SetupCard>
  );
}

// ── custom hours ───────────────────────────────────────────────────────────

/** Day | Operating Hours | Status, one row per day; below ~560px each day becomes a small card. */
export function CustomHoursTable({
  plans,
  onChange,
  errors,
  brk,
}: {
  plans: DayPlan[];
  onChange: (day: DayOfWeek, patch: Partial<DayPlan>) => void;
  errors: Partial<Record<DayOfWeek, string>>;
  brk?: BreakTime | null;
}) {
  const [ref, wide] = useContainerWide(560);
  const total = formatHours(weeklyMinutes(plans, brk));
  const grid = "grid grid-cols-[96px_1fr_1fr_96px] items-center gap-3";

  return (
    <SetupCard className="p-4 sm:p-5">
      <CardHeading icon={<CalendarClock className="h-7 w-7" aria-hidden="true" />} title="Set Custom Operating Hours" description="Configure opening and closing time for each day based on your facility's availability." />
      <div ref={ref} className="min-w-0">
        {wide && (
          <div className={cn(grid, "rounded-t-lg bg-[#F1EBFF] px-3 py-2 text-xs font-semibold")} aria-hidden="true">
            <span>Day</span>
            <span>Operating Hours</span>
            <span />
            <span>Status</span>
          </div>
        )}
        <ul className={cn(wide ? "rounded-b-lg border border-t-0 border-[#EFECF6]" : "space-y-3")}>
          {orderedPlans(plans).map((p) => {
            const label = DAY_LABELS[p.dayOfWeek];
            const status = (
              <span
                className={cn(
                  "inline-flex h-7 items-center gap-1.5 rounded-full px-3 text-xs font-semibold",
                  p.isOpen ? "bg-[#E8F5E9] text-[#2E7D32]" : "bg-[#FDECEA] text-[#C62828]",
                )}
              >
                <span aria-hidden="true" className={cn("h-1.5 w-1.5 rounded-full", p.isOpen ? "bg-[#2E7D32]" : "bg-[#C62828]")} />
                {p.isOpen ? "Open" : "Closed"}
              </span>
            );
            const dayCell = (
              <label className="flex cursor-pointer items-center gap-2.5 text-sm font-semibold">
                <input
                  type="checkbox"
                  checked={p.isOpen}
                  aria-label={label}
                  onChange={(e) => onChange(p.dayOfWeek, { isOpen: e.target.checked })}
                  className="h-5 w-5 cursor-pointer rounded accent-[#4817C2]"
                />
                {SHORT_DAY[p.dayOfWeek]}
              </label>
            );
            const times = p.is24Hours ? (
              <p className="col-span-2 flex h-11 items-center text-sm font-medium text-[#4817C2]">Open 24 hours</p>
            ) : (
              <>
                <TimeField id={`day-${p.dayOfWeek}-open`} ariaLabel={`${label} opens at`} value={p.isOpen ? p.open : ""} onChange={(v) => onChange(p.dayOfWeek, { open: v })} disabled={!p.isOpen} placeholder="–" invalid={!!errors[p.dayOfWeek]} />
                <TimeField id={`day-${p.dayOfWeek}-close`} ariaLabel={`${label} closes at`} value={p.isOpen ? p.close : ""} onChange={(v) => onChange(p.dayOfWeek, { close: v })} disabled={!p.isOpen} placeholder="–" invalid={!!errors[p.dayOfWeek]} />
              </>
            );

            return (
              <li key={p.dayOfWeek} className={cn(wide ? "border-t border-[#EFECF6] px-3 py-2 first:border-t-0" : "rounded-xl border border-[#E5E1EF] p-3")}>
                {wide ? (
                  <div className={grid}>
                    {dayCell}
                    {times}
                    <span>{status}</span>
                  </div>
                ) : (
                  <div className="space-y-3">
                    <div className="flex items-center justify-between">
                      {dayCell}
                      {status}
                    </div>
                    <div className="grid grid-cols-2 gap-3">{times}</div>
                  </div>
                )}
                {errors[p.dayOfWeek] && <FieldError>{errors[p.dayOfWeek]}</FieldError>}
              </li>
            );
          })}
        </ul>
        <div className="mt-3 flex items-center justify-between rounded-lg bg-[#F1EBFF] px-4 py-3">
          <span className="flex items-center gap-2 text-base font-semibold">
            <Clock className="h-5 w-5 text-[#4817C2]" aria-hidden="true" />
            Weekly Total Operating Hours
          </span>
          <span className="rounded-md bg-[#EDE7FF] px-3 py-1 text-base font-semibold text-[#4817C2]" data-testid="weekly-total">
            {total}
          </span>
        </div>
      </div>
    </SetupCard>
  );
}

// ── additional settings ────────────────────────────────────────────────────

export function ToggleRow({ id, title, hint, description, checked, onChange, children }: { id: string; title: string; hint: string; description: string; checked: boolean; onChange: (v: boolean) => void; children?: React.ReactNode }) {
  return (
    <div className="py-3 first:pt-0 last:pb-0">
      <div className="flex items-start gap-3">
        <Switch
          id={id}
          aria-labelledby={`${id}-title`}
          checked={checked}
          onCheckedChange={onChange}
          className="mt-0.5 h-7 w-12 border-0 data-[state=on]:bg-[#4817C2]"
          style={{ backgroundColor: checked ? "#4817C2" : "#C9C5D6" }}
        />
        <div className="min-w-0 flex-1">
          <p id={`${id}-title`} className="flex items-center gap-2 text-[15px] font-semibold leading-snug">
            {title}
            <span title={hint} className="text-[#666666]">
              <Info className="h-4 w-4" aria-hidden="true" />
              <span className="sr-only">{hint}</span>
            </span>
          </p>
          <p className="mt-0.5 text-[13px] font-normal text-[#666666]">{description}</p>
          {children}
        </div>
      </div>
    </div>
  );
}

export function AdditionalSettings({
  allowOutside,
  onAllowOutside,
  breakOn,
  onBreakOn,
  brk,
  onBreak,
  breakError,
  sportWise,
  onSportWise,
}: {
  allowOutside: boolean;
  onAllowOutside: (v: boolean) => void;
  breakOn: boolean;
  onBreakOn: (v: boolean) => void;
  brk: BreakTime;
  onBreak: (next: BreakTime) => void;
  breakError?: string;
  sportWise: boolean;
  onSportWise: (v: boolean) => void;
}) {
  return (
    <SetupCard className="p-4 sm:p-5">
      <CardHeading icon={<SlidersHorizontal className="h-7 w-7" aria-hidden="true" />} title="Additional Settings" />
      <div className="divide-y divide-[#EFECF6]">
        <ToggleRow
          id="allow-outside"
          title="Allow bookings outside operating hours"
          hint="Your team can create a booking at any time, even when you are closed or on a holiday. Players on the booking page still follow your hours."
          description="Let admins create special bookings even outside working hours."
          checked={allowOutside}
          onChange={onAllowOutside}
        />
        <ToggleRow
          id="break-time"
          title="Set a break time"
          hint="Courts cannot be booked during this time on any open day."
          description="Block a fixed time (e.g., maintenance, cleaning) within working hours."
          checked={breakOn}
          onChange={onBreakOn}
        >
          {breakOn && (
            <div className="mt-3 grid gap-3 sm:grid-cols-2">
              <div>
                <label htmlFor="break-start" className="mb-1 block text-sm">
                  Break starts
                </label>
                <TimeField id="break-start" ariaLabel="Break starts at" value={brk.start} onChange={(v) => onBreak({ ...brk, start: v })} invalid={!!breakError} />
              </div>
              <div>
                <label htmlFor="break-end" className="mb-1 block text-sm">
                  Break ends
                </label>
                <TimeField id="break-end" ariaLabel="Break ends at" value={brk.end} onChange={(v) => onBreak({ ...brk, end: v })} invalid={!!breakError} />
              </div>
              {breakError && (
                <div className="sm:col-span-2">
                  <FieldError>{breakError}</FieldError>
                </div>
              )}
            </div>
          )}
        </ToggleRow>
        <ToggleRow
          id="sport-wise"
          title="Apply sport-wise operating hours"
          hint="Give each sport its own days and times. Each of its courts then follows them instead of the venue's hours."
          description="Set different timings for each sport (e.g., Badminton: 6 AM – 10 PM)."
          checked={sportWise}
          onChange={onSportWise}
        />
      </div>
    </SetupCard>
  );
}
