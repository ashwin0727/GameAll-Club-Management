"use client";

import { Trophy } from "lucide-react";
import {
  CardHeading,
  FieldError,
  SetupCard,
} from "@/features/onboarding/components/setup-fields";
import {
  DayChips,
  TimeField,
} from "@/features/operating-hours/setup/hours-parts";
import {
  dailyMinutes,
  formatHours,
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

/**
 * "Sport-wise Operating Hours": each sport gets its own days and times, and each of its courts follows them instead of the venue's.
 * Same simple controls as Standard Hours, once per sport.
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
        {sports.map((s) => {
          const list = plans[s.id] ?? [];
          const openDays = list.filter((p) => p.isOpen).map((p) => p.dayOfWeek);
          const first = list.find((p) => p.isOpen) ?? list[0];
          const open = first?.open ?? "06:00";
          const close = first?.close ?? "23:00";
          const is24 = !!first?.is24Hours;
          const apply = (days: DayOfWeek[], o: string, c: string, all = is24) =>
            onChange(
              s.id,
              list.map((p) => ({
                ...p,
                isOpen: days.includes(p.dayOfWeek),
                open: o,
                close: c,
                is24Hours: all,
              })),
            );
          return (
            <section
              key={s.id}
              aria-label={`${s.name} hours`}
              className="rounded-xl border border-[#E5E1EF] p-3.5"
            >
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
                {first && (
                  <span className="rounded-md bg-[#EDE7FF] px-2.5 py-0.5 text-xs font-semibold text-[#4817C2]">
                    {is24
                      ? "Open 24 hours"
                      : `${formatHours(dailyMinutes({ ...first, isOpen: true }))} a day`}
                  </span>
                )}
              </div>
              <DayChips
                value={openDays}
                onChange={(days) => apply(days, open, close)}
                idPrefix={`sport-${s.id}-day`}
              />
              <label className="mt-3 flex w-fit cursor-pointer items-center gap-2 text-sm font-medium">
                <input
                  type="checkbox"
                  checked={is24}
                  onChange={(e) =>
                    apply(openDays, open, close, e.target.checked)
                  }
                  className="h-4 w-4 cursor-pointer rounded accent-[#4817C2]"
                />
                Open 24 hours
              </label>
              {is24 ? (
                <p className="mt-3 flex h-11 items-center rounded-lg bg-[#F1EBFF] px-3 text-sm font-semibold text-[#4817C2]">
                  Open all day, 24 Hours
                </p>
              ) : (
                <div className="mt-3 grid gap-3 sm:grid-cols-2">
                  <div>
                    <label
                      htmlFor={`sport-${s.id}-open`}
                      className="mb-1 block text-sm"
                    >
                      Opens At
                    </label>
                    <TimeField
                      id={`sport-${s.id}-open`}
                      ariaLabel={`${s.name} opens at`}
                      value={open}
                      onChange={(v) => apply(openDays, v, close)}
                      invalid={!!errors[s.id]}
                    />
                  </div>
                  <div>
                    <label
                      htmlFor={`sport-${s.id}-close`}
                      className="mb-1 block text-sm"
                    >
                      Closes At
                    </label>
                    <TimeField
                      id={`sport-${s.id}-close`}
                      ariaLabel={`${s.name} closes at`}
                      value={close}
                      onChange={(v) => apply(openDays, open, v)}
                      invalid={!!errors[s.id]}
                    />
                  </div>
                </div>
              )}
              {errors[s.id] && <FieldError>{errors[s.id]}</FieldError>}
            </section>
          );
        })}
      </div>
    </SetupCard>
  );
}
