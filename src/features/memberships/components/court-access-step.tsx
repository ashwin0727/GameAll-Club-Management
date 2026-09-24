"use client";

import { AlertTriangle, CalendarClock, CalendarCog, Check, Clock, Plus, Trash2, Users } from "lucide-react";
import { ToggleSwitch } from "@/features/bookings/components/toggle-switch";
import { TimeField } from "@/features/memberships/components/time-field";
import { DAY_PRESETS } from "@/features/memberships/playing-schedule";
import { findOverlap, UNLIMITED_WINDOW_CAPACITY, type PlanTimeWindow, type PlanWizardDraft } from "@/features/memberships/create-plan-wizard";
import { windowsForDay } from "@/features/bookings/slots";
import type { PlayingArea } from "@/features/courts-setup/types";
import type { OperatingSchedule } from "@/features/operating-hours/types";
import { cn } from "@/lib/utils";

const DAY_ABBR = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
/** The default day set — Mon-Fri, same as DAY_PRESETS' own "weekdays" entry — used only to seed
 *  a freshly-added time window; matches the Add Member wizard's own default. */
const DEFAULT_DAYS = DAY_PRESETS[0]!.days;

function toMinutes(t: string): number {
  const [h, m] = t.split(":").map(Number);
  return (h ?? 0) * 60 + (m ?? 0);
}

/** Whether `startTime`-`endTime` sits fully inside the court's operating hours on every one of
 *  `days` — informational only (no operating-hours record for a court just means "no data",
 *  not "closed", so this never blocks Next, only warns). */
function outsideOperatingHours(
  schedules: Map<string, OperatingSchedule | null> | undefined,
  courtId: string,
  days: number[],
  startTime: string,
  endTime: string,
): boolean {
  if (!schedules || schedules.size === 0) return false;
  const schedule = schedules.get(courtId);
  if (!schedule) return false;
  const startMin = toMinutes(startTime);
  const endMin = toMinutes(endTime);
  return days.some((dow) => {
    const day = schedule.days.find((d) => d.dayOfWeek === dow);
    if (!day) return false;
    if (day.isClosed) return true;
    if (day.is24Hours) return false;
    return !windowsForDay(day).some((w) => startMin >= w.startMin && endMin <= w.endMin);
  });
}

let windowIdSeq = 0;
function newWindowId(): string {
  windowIdSeq += 1;
  return `w-${Date.now()}-${windowIdSeq}`;
}

/** The numbered circle badge each Court Access sub-section starts with, matching the design. */
function StepBadge({ n }: { n: number }) {
  return (
    <span className="flex h-6 w-6 shrink-0 items-center justify-center rounded-full bg-muted text-xs font-semibold text-muted-foreground">
      {n}
    </span>
  );
}

export function CourtAccessStep({
  draft,
  set,
  show,
  courts,
  courtSchedules,
  loading,
}: {
  draft: PlanWizardDraft;
  set: <K extends keyof PlanWizardDraft>(key: K, value: PlanWizardDraft[K]) => void;
  show: (field: string) => string | undefined;
  courts: PlayingArea[];
  courtSchedules: Map<string, OperatingSchedule | null> | undefined;
  loading: boolean;
}) {
  const allSelected = courts.length > 0 && courts.every((c) => draft.courtIds.includes(c.id));

  function toggleCourt(courtId: string) {
    set("courtIds", draft.courtIds.includes(courtId) ? draft.courtIds.filter((c) => c !== courtId) : [...draft.courtIds, courtId]);
  }

  function toggleSelectAll() {
    set("courtIds", allSelected ? [] : courts.map((c) => c.id));
  }

  function toggleDay(day: number) {
    set("playingDays", draft.playingDays.includes(day) ? draft.playingDays.filter((d) => d !== day) : [...draft.playingDays, day].sort());
  }

  function addWindow() {
    const courtId = draft.courtIds[0];
    if (!courtId) return;
    const win: PlanTimeWindow = {
      id: newWindowId(),
      courtId,
      daysOfWeek: draft.playingDays.length > 0 ? draft.playingDays : DEFAULT_DAYS,
      startTime: "07:00",
      endTime: "08:00",
      capacity: UNLIMITED_WINDOW_CAPACITY,
    };
    set("timeWindows", [...draft.timeWindows, win]);
  }

  function updateWindow(id: string, patch: Partial<PlanTimeWindow>) {
    set(
      "timeWindows",
      draft.timeWindows.map((w) => (w.id === id ? { ...w, ...patch } : w)),
    );
  }

  function removeWindow(id: string) {
    set(
      "timeWindows",
      draft.timeWindows.filter((w) => w.id !== id),
    );
  }

  return (
    <>
      <div className="flex items-start gap-3">
        <span className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-blue-500/10 text-blue-600 dark:text-blue-400">
          <CalendarCog className="h-5 w-5" aria-hidden />
        </span>
        <div>
          <p className="text-lg font-bold text-black dark:text-foreground">Court Access</p>
          <p className="text-sm text-muted-foreground">Select which courts are accessible and set preferred days &amp; time slots for this plan.</p>
        </div>
      </div>

      {/* 1. Select Courts */}
      <div className="flex items-start gap-2.5">
        <StepBadge n={1} />
        <div className="min-w-0 flex-1">
          <div className="flex flex-wrap items-start justify-between gap-2">
            <div>
              <p className="text-sm font-bold text-foreground">Select Courts</p>
              <p className="text-xs text-muted-foreground">Choose which courts members can book under this plan.</p>
            </div>
            {courts.length > 0 && (
              <label className="flex items-center gap-1.5 text-xs text-muted-foreground">
                <input type="checkbox" checked={allSelected} onChange={toggleSelectAll} className="h-4 w-4 rounded border-input accent-success" />
                Select All Courts
              </label>
            )}
          </div>

          {loading ? (
            <p className="mt-3 text-xs text-muted-foreground">Loading courts…</p>
          ) : courts.length === 0 ? (
            <p className="mt-3 text-xs text-muted-foreground">No active courts are set up at this facility yet.</p>
          ) : (
            <div className="mt-3 grid grid-cols-2 gap-3 sm:grid-cols-4">
              {courts.map((court) => {
                const selected = draft.courtIds.includes(court.id);
                return (
                  <button
                    key={court.id}
                    type="button"
                    onClick={() => toggleCourt(court.id)}
                    aria-pressed={selected}
                    className={cn(
                      "overflow-hidden rounded-xl border text-left transition-colors",
                      selected ? "border-success bg-success/5" : "border-input hover:bg-accent/30",
                    )}
                  >
                    <div className="relative h-20 w-full bg-gradient-to-br from-slate-700 to-slate-900">
                      <span
                        className={cn(
                          "absolute left-2 top-2 flex h-5 w-5 items-center justify-center rounded-full border-2",
                          selected ? "border-success bg-success text-white" : "border-white/70 bg-white/20",
                        )}
                      >
                        {selected && <Check className="h-3 w-3" strokeWidth={3.5} aria-hidden />}
                      </span>
                    </div>
                    <div className="p-2">
                      <p className="truncate text-sm font-semibold text-foreground">{court.name}</p>
                      <p className="text-xs text-blue-600 dark:text-blue-400">{court.type === "INDOOR" ? "Indoor" : "Outdoor"} Court</p>
                    </div>
                  </button>
                );
              })}
            </div>
          )}
          {show("courtIds") && <p className="mt-1.5 text-xs text-destructive">{show("courtIds")}</p>}
        </div>
      </div>

      {/* 2. Set Playing Days */}
      <div className="flex items-start gap-2.5">
        <StepBadge n={2} />
        <div className="min-w-0 flex-1">
          <p className="text-sm font-bold text-foreground">Set Playing Days</p>
          <p className="text-xs text-muted-foreground">Select available days for this membership plan.</p>
          <div className="mt-3 flex flex-wrap gap-2">
            {DAY_ABBR.map((label, i) => {
              const selected = draft.playingDays.includes(i);
              return (
                <button
                  key={i}
                  type="button"
                  onClick={() => toggleDay(i)}
                  aria-pressed={selected}
                  className={cn(
                    "flex h-9 items-center gap-1.5 rounded-[6px] border px-3 text-xs font-semibold transition-colors",
                    selected ? "border-success bg-success/10 text-success" : "border-input text-muted-foreground hover:bg-accent/30",
                  )}
                >
                  <span
                    className={cn(
                      "flex h-4 w-4 shrink-0 items-center justify-center rounded-full",
                      selected ? "bg-success text-white" : "border border-input",
                    )}
                  >
                    {selected && <Check className="h-2.5 w-2.5" strokeWidth={3.5} aria-hidden />}
                  </span>
                  {label}
                </button>
              );
            })}
          </div>
          {show("playingDays") && <p className="mt-1.5 text-xs text-destructive">{show("playingDays")}</p>}
        </div>
      </div>

      {/* 3. Set Playing Time Slots */}
      <div className="flex items-start gap-2.5">
        <StepBadge n={3} />
        <div className="min-w-0 flex-1">
          <div className="flex flex-wrap items-start justify-between gap-2">
            <div>
              <p className="text-sm font-bold text-foreground">Set Playing Time Slots</p>
              <p className="text-xs text-muted-foreground">Choose the time slots members can book on selected days.</p>
            </div>
            <button
              type="button"
              onClick={addWindow}
              disabled={draft.courtIds.length === 0}
              className="flex h-9 items-center gap-1.5 rounded-lg border border-input bg-card px-3 text-xs font-semibold transition-colors hover:bg-accent disabled:cursor-not-allowed disabled:opacity-50"
            >
              <Plus className="h-3.5 w-3.5" aria-hidden />
              Add Time Slot
            </button>
          </div>

          <div className="mt-3 space-y-2.5">
            {draft.timeWindows.length === 0 ? (
              <p className="rounded-xl border border-dashed border-input p-4 text-center text-xs text-muted-foreground">
                {draft.courtIds.length === 0 ? "Select a court above, then add a time slot." : "No time slots yet — add one above."}
              </p>
            ) : (
              draft.timeWindows.map((w) => {
                const overlap = findOverlap(draft.timeWindows, w);
                const outsideHours = outsideOperatingHours(courtSchedules, w.courtId, w.daysOfWeek, w.startTime, w.endTime);
                return (
                  <div key={w.id} className="space-y-2 rounded-xl border border-border p-3">
                    <div className="flex flex-wrap items-center gap-2.5">
                      <Clock className="h-4 w-4 shrink-0 text-muted-foreground" aria-hidden />
                      <TimeField value={w.startTime} onChange={(v) => updateWindow(w.id, { startTime: v })} ariaLabel="Start time" />
                      <TimeField value={w.endTime} onChange={(v) => updateWindow(w.id, { endTime: v })} ariaLabel="End time" />

                      {draft.courtIds.length > 1 && (
                        <select
                          value={w.courtId}
                          onChange={(e) => updateWindow(w.id, { courtId: e.target.value })}
                          aria-label="Court"
                          className="h-9 rounded-lg border border-input bg-card px-2 text-sm outline-none"
                        >
                          {draft.courtIds.map((id) => (
                            <option key={id} value={id}>
                              {courts.find((c) => c.id === id)?.name ?? id}
                            </option>
                          ))}
                        </select>
                      )}

                      {/* Only selected days show (nothing greyed-out for the rest) — that keeps
                       *  this row short enough to sit next to the time/court selects on one
                       *  line. The restore button brings back any days trimmed from the window. */}
                      <div className="flex flex-1 flex-wrap items-center gap-1.5">
                        {DAY_ABBR.map((label, i) =>
                          w.daysOfWeek.includes(i) ? (
                            <button
                              key={i}
                              type="button"
                              onClick={() => updateWindow(w.id, { daysOfWeek: w.daysOfWeek.filter((d) => d !== i) })}
                              className="rounded-md bg-success/10 px-1.5 py-0.5 text-[11px] font-semibold text-success"
                            >
                              {label}
                            </button>
                          ) : null,
                        )}
                        {w.daysOfWeek.length < draft.playingDays.length && (
                          <button
                            type="button"
                            onClick={() => updateWindow(w.id, { daysOfWeek: [...draft.playingDays].sort() })}
                            aria-label="Restore all playing days"
                            title="Restore all playing days"
                            className="flex h-5 w-5 items-center justify-center rounded-md text-muted-foreground/60 hover:bg-accent hover:text-foreground"
                          >
                            <Plus className="h-3 w-3" aria-hidden />
                          </button>
                        )}
                      </div>

                      <button
                        type="button"
                        onClick={() => removeWindow(w.id)}
                        aria-label="Remove this time slot"
                        className="ml-auto flex h-9 w-9 shrink-0 items-center justify-center rounded-lg text-muted-foreground transition-colors hover:bg-destructive/10 hover:text-destructive"
                      >
                        <Trash2 className="h-4 w-4" aria-hidden />
                      </button>
                    </div>

                    {overlap && (
                      <p className="flex items-center gap-1.5 text-xs text-warning">
                        <AlertTriangle className="h-3.5 w-3.5 shrink-0" aria-hidden />
                        Overlaps another slot on the same court and day — allowed (courts can share capacity), just flagging it.
                      </p>
                    )}
                    {outsideHours && (
                      <p className="flex items-center gap-1.5 text-xs text-destructive">
                        <AlertTriangle className="h-3.5 w-3.5 shrink-0" aria-hidden />
                        This falls outside the court&apos;s configured operating hours on at least one selected day.
                      </p>
                    )}
                  </div>
                );
              })
            )}
          </div>
          {show("timeWindows") && <p className="mt-1.5 text-xs text-destructive">{show("timeWindows")}</p>}
        </div>
      </div>

      {/* 4. Slot Booking Rules (Optional) */}
      <div className="flex items-start gap-2.5">
        <StepBadge n={4} />
        <div className="min-w-0 flex-1">
          <p className="text-sm font-bold text-foreground">Slot Booking Rules (Optional)</p>
          <p className="text-xs text-muted-foreground">Set additional rules for how members can book courts.</p>

          <div className="mt-3 grid grid-cols-1 gap-3 sm:grid-cols-2">
            <div className="flex items-center justify-between gap-3 rounded-xl border border-input p-3">
              <div className="flex items-center gap-2.5">
                <span className="flex h-9 w-9 shrink-0 items-center justify-center rounded-lg bg-[#07101F] text-white">
                  <CalendarClock className="h-4.5 w-4.5" aria-hidden />
                </span>
                <div>
                  <p className="text-sm font-semibold text-foreground">Allow Advance Booking</p>
                  <p className="text-xs text-muted-foreground">Let members book slots in advance</p>
                </div>
              </div>
              <ToggleSwitch
                checked={draft.allowAdvanceBooking}
                onChange={(v) => set("allowAdvanceBooking", v)}
                label="Allow Advance Booking"
                onClass="bg-[#0B9B63]"
              />
            </div>

            <div className="flex items-center justify-between gap-3 rounded-xl border border-input p-3">
              <div className="flex items-center gap-2.5">
                <span className="flex h-9 w-9 shrink-0 items-center justify-center rounded-lg bg-blue-500/10 text-blue-600 dark:text-blue-400">
                  <Users className="h-4.5 w-4.5" aria-hidden />
                </span>
                <div>
                  <p className="text-sm font-semibold text-foreground">Limit Consecutive Slots</p>
                  <p className="text-xs text-muted-foreground">Restrict back-to-back bookings</p>
                </div>
              </div>
              <ToggleSwitch
                checked={draft.limitConsecutiveSlots}
                onChange={(v) => set("limitConsecutiveSlots", v)}
                label="Limit Consecutive Slots"
                onClass="bg-[#0B9B63]"
              />
            </div>
          </div>
        </div>
      </div>

      <div className="rounded-xl border border-border p-3">
        <p className="text-sm font-semibold text-foreground">Membership Reserved Time</p>
        <p className="mt-1 text-xs leading-relaxed text-foreground/80">
          Selected court capacity is reserved for members on this plan. Guest bookings cannot use this reserved capacity unless the
          owner explicitly releases it, from the same Release Member Time to Guest workflow already used elsewhere — this rule applies
          the same way for Time Based and Recurring plans.
        </p>
      </div>
    </>
  );
}
