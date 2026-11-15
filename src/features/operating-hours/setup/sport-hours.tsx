"use client";

import * as React from "react";
import { Plus, Trash2, Trophy } from "lucide-react";
import {
  CardHeading,
  FieldError,
  SetupCard,
} from "@/features/onboarding/components/setup-fields";
import { DayChips, TimeField } from "@/features/operating-hours/setup/hours-parts";
import { DISPLAY_ORDER } from "@/features/operating-hours/constants";
import {
  dailyMinutes,
  formatHours,
  weeklyMinutes,
  type DayPlan,
} from "@/features/operating-hours/setup-model";
import type { DayOfWeek } from "@/features/operating-hours/types";

export interface SportHoursEntry {
  /** facility_sports.id */
  id: string;
  name: string;
  icon: string;
  courts: number;
}

/** One set of days that share the same hours, e.g. "Mon-Fri 6 AM - 10 PM" or "Sat, Sun 8 AM - 8 PM". */
interface TimingGroup {
  id: number;
  days: DayOfWeek[];
  open: string;
  close: string;
  is24: boolean;
}

const FALLBACK_OPEN = "06:00";
const FALLBACK_CLOSE = "23:00";

/** The open days of a sport, grouped by the hours they share (in Mon..Sun order). */
function groupsFromPlans(list: DayPlan[], nextId: () => number): TimingGroup[] {
  const byKey = new Map<string, TimingGroup>();
  for (const d of DISPLAY_ORDER) {
    const p = list.find((x) => x.dayOfWeek === d);
    if (!p || !p.isOpen) continue;
    const key = p.is24Hours ? "24h" : `${p.open}-${p.close}`;
    const existing = byKey.get(key);
    if (existing) existing.days.push(d);
    else byKey.set(key, { id: nextId(), days: [d], open: p.open, close: p.close, is24: p.is24Hours });
  }
  if (byKey.size > 0) return [...byKey.values()];
  const first = list[0];
  return [{ id: nextId(), days: [], open: first?.open ?? FALLBACK_OPEN, close: first?.close ?? FALLBACK_CLOSE, is24: false }];
}

/** The per-day plans that the groups describe (a day in no group is closed). */
function plansFromGroups(base: DayPlan[], groups: TimingGroup[]): DayPlan[] {
  return base.map((p) => {
    const g = groups.find((x) => x.days.includes(p.dayOfWeek));
    return g ? { ...p, isOpen: true, open: g.open, close: g.close, is24Hours: g.is24 } : { ...p, isOpen: false, is24Hours: false };
  });
}

function samePlans(a: DayPlan[], b: DayPlan[]): boolean {
  if (a.length !== b.length) return false;
  return a.every((p, i) => {
    const q = b[i]!;
    if (p.dayOfWeek !== q.dayOfWeek || p.isOpen !== q.isOpen) return false;
    if (!p.isOpen) return true;
    return p.is24Hours === q.is24Hours && (p.is24Hours || (p.open === q.open && p.close === q.close));
  });
}

/**
 * "Sport-wise Operating Hours": each sport gets its own days and times, and each of its courts follows them instead of the venue's.
 * A sport can have more than one timing (say Mon-Fri one way and the weekend another): every day belongs to at most one timing.
 */
export function SportHoursCard({
  sports,
  plans,
  onChange,
  errors,
}: {
  sports: SportHoursEntry[];
  plans: Record<string, DayPlan[]>;
  onChange: (sportId: string, next: DayPlan[]) => void;
  errors: Record<string, string>;
}) {
  return (
    <SetupCard className="p-4 sm:p-5">
      <CardHeading
        icon={<Trophy className="h-7 w-7" aria-hidden="true" />}
        title="Sport-wise Operating Hours"
        description="Each sport's courts follow these days and times instead of the venue's hours."
      />
      <div className="space-y-4">
        {sports.map((s) => (
          <SportSection key={s.id} sport={s} list={plans[s.id] ?? []} onChange={(next) => onChange(s.id, next)} error={errors[s.id]} />
        ))}
      </div>
    </SetupCard>
  );
}

function SportSection({
  sport: s,
  list,
  onChange,
  error,
}: {
  sport: SportHoursEntry;
  list: DayPlan[];
  onChange: (next: DayPlan[]) => void;
  error?: string;
}) {
  const counter = React.useRef(0);
  const nextId = React.useCallback(() => ++counter.current, []);
  const [groups, setGroups] = React.useState<TimingGroup[]>(() => groupsFromPlans(list, nextId));
  const groupsRef = React.useRef(groups);
  groupsRef.current = groups;

  // Hours changed from outside (loaded, reset): start the groups again from them. Edits made here keep the two in step.
  React.useEffect(() => {
    if (!samePlans(plansFromGroups(list, groupsRef.current), list)) setGroups(groupsFromPlans(list, nextId));
  }, [list, nextId]);

  function update(next: TimingGroup[]) {
    setGroups(next);
    onChange(plansFromGroups(list, next));
  }
  function patch(id: number, change: Partial<TimingGroup>) {
    update(groups.map((g) => (g.id === id ? { ...g, ...change } : g)));
  }

  const used = new Set(groups.flatMap((g) => g.days));
  const unused = DISPLAY_ORDER.filter((d) => !used.has(d));
  const donor = groups.reduce((a, b) => (b.days.length > a.days.length ? b : a), groups[0]!);
  const canAdd = unused.length > 0 || donor.days.length >= 2;

  function addGroup() {
    const weekend: DayOfWeek[] = [6, 0];
    const fromDonor = donor.days.filter((d) => weekend.includes(d));
    let take: DayOfWeek[];
    if (fromDonor.length > 0 && fromDonor.length < donor.days.length) {
      // the usual case: the weekend gets its own timing (a weekend day that is not open yet joins it)
      take = DISPLAY_ORDER.filter((d) => fromDonor.includes(d) || (weekend.includes(d) && !used.has(d)));
    } else if (unused.length > 0) {
      take = unused;
    } else {
      take = [donor.days[donor.days.length - 1]!];
    }
    update([
      ...groups.map((g) => ({ ...g, days: g.days.filter((d) => !take.includes(d)) })),
      { id: nextId(), days: take, open: donor.open, close: donor.close, is24: donor.is24 },
    ]);
  }

  const many = groups.length > 1;
  const first = groups[0]!;
  const weekly = weeklyMinutes(plansFromGroups(list, groups), null);
  const hasOpenDay = used.size > 0;

  return (
    <section aria-label={`${s.name} hours`} className="rounded-xl border border-[#E5E1EF] p-3.5">
      <div className="mb-3 flex items-center justify-between gap-2">
        <h3 className="flex items-center gap-2 text-base font-semibold">
          <span aria-hidden="true" className="text-xl leading-none">
            {s.icon}
          </span>
          {s.name}
          <span className="text-xs font-normal text-[#666666]">
            {s.courts} {s.courts === 1 ? "court" : "courts"}
          </span>
        </h3>
        {hasOpenDay && (
          <span className="rounded-md bg-[#EDE7FF] px-2.5 py-0.5 text-xs font-semibold text-[#4817C2]">
            {many ? `${formatHours(weekly)} a week` : first.is24 ? "Open 24 hours" : `${formatHours(dailyMinutes(timeOf(first)))} a day`}
          </span>
        )}
      </div>

      <div className="space-y-3">
        {groups.map((g, i) => (
          <TimingRow
            key={g.id}
            group={g}
            index={i}
            sportId={s.id}
            sportName={s.name}
            many={many}
            takenByOthers={groups.filter((x) => x.id !== g.id).flatMap((x) => x.days)}
            invalid={!!error}
            onChange={(change) => patch(g.id, change)}
            onRemove={() => update(groups.filter((x) => x.id !== g.id))}
          />
        ))}
      </div>

      <button
        type="button"
        disabled={!canAdd}
        onClick={addGroup}
        className="mt-3 flex h-10 items-center gap-1.5 rounded-lg border border-[#4817C2]/45 bg-[#F8F4FF] px-3 text-sm font-semibold text-[#4817C2] transition-colors hover:bg-[#F1EBFF] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#4817C2] disabled:cursor-not-allowed disabled:opacity-50"
      >
        <Plus className="h-4 w-4" aria-hidden="true" />
        Add different timing for some days
      </button>
      {error && <FieldError>{error}</FieldError>}
    </section>
  );
}

function timeOf(g: TimingGroup): DayPlan {
  return { dayOfWeek: 1, isOpen: true, open: g.open, close: g.close, is24Hours: g.is24 };
}

function TimingRow({
  group: g,
  index,
  sportId,
  sportName,
  many,
  takenByOthers,
  invalid,
  onChange,
  onRemove,
}: {
  group: TimingGroup;
  index: number;
  sportId: string;
  sportName: string;
  many: boolean;
  takenByOthers: DayOfWeek[];
  invalid: boolean;
  onChange: (change: Partial<TimingGroup>) => void;
  onRemove: () => void;
}) {
  // one timing keeps the plain labels; with several, each is numbered so they can be told apart
  const label = many ? `${sportName} timing ${index + 1}` : sportName;
  const prefix = many ? `sport-${sportId}-t${index + 1}` : `sport-${sportId}`;
  return (
    <div className={many ? "rounded-lg border border-[#EFECF6] bg-[#FBFAFE] p-3" : undefined}>
      {many && (
        <div className="mb-2 flex items-center justify-between gap-2">
          <span className="text-sm font-semibold">Timing {index + 1}</span>
          <div className="flex items-center gap-2">
            {g.days.length > 0 && (
              <span className="rounded-md bg-[#EDE7FF] px-2 py-0.5 text-xs font-semibold text-[#4817C2]">
                {g.is24 ? "Open 24 hours" : `${formatHours(dailyMinutes(timeOf(g)))} a day`}
              </span>
            )}
            <button
              type="button"
              aria-label={`Remove ${label}`}
              onClick={onRemove}
              className="flex h-8 w-8 items-center justify-center rounded-lg text-[#C62828] hover:bg-[#FDECEA] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#C62828]"
            >
              <Trash2 className="h-4 w-4" aria-hidden="true" />
            </button>
          </div>
        </div>
      )}
      <DayChips value={g.days} onChange={(days) => onChange({ days })} idPrefix={`${prefix}-day`} disabled={takenByOthers} />
      <label className="mt-3 flex w-fit cursor-pointer items-center gap-2 text-sm font-medium">
        <input
          type="checkbox"
          checked={g.is24}
          onChange={(e) => onChange({ is24: e.target.checked })}
          aria-label={many ? `${label} open 24 hours` : undefined}
          className="h-4 w-4 cursor-pointer rounded accent-[#4817C2]"
        />
        Open 24 hours
      </label>
      {g.is24 ? (
        <p className="mt-3 flex h-11 items-center rounded-lg bg-[#F1EBFF] px-3 text-sm font-semibold text-[#4817C2]">Open all day, 24 Hours</p>
      ) : (
        <div className="mt-3 grid gap-3 sm:grid-cols-2">
          <div>
            <label htmlFor={`${prefix}-open`} className="mb-1 block text-sm">
              Opens At
            </label>
            <TimeField id={`${prefix}-open`} ariaLabel={`${label} opens at`} value={g.open} onChange={(v) => onChange({ open: v })} invalid={invalid} />
          </div>
          <div>
            <label htmlFor={`${prefix}-close`} className="mb-1 block text-sm">
              Closes At
            </label>
            <TimeField id={`${prefix}-close`} ariaLabel={`${label} closes at`} value={g.close} onChange={(v) => onChange({ close: v })} invalid={invalid} />
          </div>
        </div>
      )}
    </div>
  );
}
