"use client";

import * as React from "react";
import { CalendarDays, Clock, Info, Layers, Plus, Trash2 } from "lucide-react";
import { FieldError, SetupInput, SetupSelect } from "@/features/onboarding/components/setup-fields";
import { DayChips, TimeField } from "@/features/operating-hours/setup/hours-parts";
import {
  TIER_LABEL,
  autoTier,
  dayGroupLabel,

  nextSlot,
  slotsOf,
  withSlots,
  type PriceSetup,
  type PriceUnit,
  type PricingSettings,
  type SetupProblems,
  type Slot,
  type SlotGroup,
} from "@/features/pricing/setup/pricing-setup-model";
import type { RateTier } from "@/features/pricing/types";
import { useContainerWide } from "@/features/sports-courts/use-container-wide";
import { cn } from "@/lib/utils";

/** Digits with at most one dot and two decimals ("550", "550.5", "550.50"). */
export function cleanAmount(raw: string): string {
  const [whole = "", ...rest] = raw.replace(/[^\d.]/g, "").split(".");
  return rest.length === 0 ? whole : `${whole}.${rest.join("").slice(0, 2)}`;
}

function AmountField({ id, label, value, onChange, invalid, placeholder = "0" }: { id: string; label: string; value: string; onChange: (v: string) => void; invalid?: boolean; placeholder?: string }) {
  return (
    <SetupInput
      id={id}
      aria-label={label}
      inputMode="decimal"
      placeholder={placeholder}
      value={value}
      invalid={invalid}
      leading={<span className="text-[15px] text-[#171717]">₹</span>}
      onChange={(e) => onChange(cleanAmount(e.target.value))}
    />
  );
}

const TIER_OPTIONS = [
  { value: "NONE", label: "No tag" },
  { value: "OFF_PEAK", label: TIER_LABEL.OFF_PEAK },
  { value: "PEAK", label: TIER_LABEL.PEAK },
];

const TIER_STYLE: Record<RateTier, string> = { OFF_PEAK: "bg-[#EDE7FF] text-[#4817C2]", PEAK: "bg-[#FDE9F1] text-[#B0125C]" };

const TABS: { group: SlotGroup; title: string; hint: string }[] = [
  { group: "WEEKDAYS", title: "Weekdays", hint: "Mon – Fri" },
  { group: "WEEKENDS", title: "Weekends", hint: "Sat – Sun" },
  { group: "SPECIFIC_DAYS", title: "Specific Days", hint: "Choose custom days" },
];

/**
 * The price setup for one sport or one court: Hourly or Per Session, the base price, and (optionally) time slots with their own price
 * for weekdays, weekends or chosen days. When member / coaching pricing is switched on it also asks for those rates.
 */
export function PriceEditor({
  idPrefix,
  setup,
  onChange,
  settings,
  span,
  problems,
}: {
  idPrefix: string;
  setup: PriceSetup;
  onChange: (next: PriceSetup) => void;
  settings: PricingSettings;
  span: { open: string; close: string };
  problems: SetupProblems;
}) {
  const [tab, setTab] = React.useState<SlotGroup>("WEEKDAYS");
  const [ref, wide] = useContainerWide(520);
  const group: SlotGroup = settings.differentWeekendPricing ? tab : "ALL_DAYS";
  const slots = slotsOf(setup, group);
  const per = setup.unit === "PER_SESSION" ? "session" : "hour";

  function setBase(base: string) {
    // slots whose tag was never picked by hand follow the price
    const retag = (list: Slot[]) => list.map((s) => (s.tierTouched ? s : { ...s, tier: autoTier(s.price, base) }));
    onChange({ ...setup, basePrice: base, allDays: retag(setup.allDays), weekdays: retag(setup.weekdays), weekends: retag(setup.weekends), specific: { ...setup.specific, slots: retag(setup.specific.slots) } });
  }

  function patchSlot(id: string, patch: Partial<Slot>) {
    onChange(withSlots(setup, group, slots.map((s) => (s.id === id ? { ...s, ...patch } : s))));
  }

  function setPrice(slot: Slot, price: string) {
    patchSlot(slot.id, { price, ...(slot.tierTouched ? {} : { tier: autoTier(price, setup.basePrice) }) });
  }

  function addSlot() {
    const fresh = nextSlot(slots, span);
    onChange(withSlots({ ...setup, timeBased: true }, group, [...slots, fresh]));
  }

  function setTimeBased(on: boolean) {
    const next = { ...setup, timeBased: on };
    // switching it on starts with one slot, so there is something to fill in
    if (on && slotsOf(next, group).length === 0) onChange(withSlots(next, group, [nextSlot([], span)]));
    else onChange(next);
  }

  const groupTitle = group === "ALL_DAYS" ? "All Days Pricing" : group === "WEEKDAYS" ? "Weekday Pricing" : group === "WEEKENDS" ? "Weekend Pricing" : "Specific Days Pricing";

  return (
    <div ref={ref} className="min-w-0 space-y-4">
      <div className="grid items-start gap-4 sm:grid-cols-2">
        <div>
          <p className="mb-1.5 flex items-center gap-1.5 text-sm font-semibold">
            Pricing Type
            <span title="Hourly charges for the time booked. Per Session charges one price for the whole booking." className="text-[#666666]">
              <Info className="h-4 w-4" aria-hidden="true" />
              <span className="sr-only">Hourly charges for the time booked. Per Session charges one price for the whole booking.</span>
            </span>
          </p>
          <div role="radiogroup" aria-label="Pricing type" className="grid h-11 grid-cols-2 overflow-hidden rounded-lg border border-[#E5E1EF]">
            {(
              [
                { value: "PER_HOUR", label: "Hourly", icon: Clock },
                { value: "PER_SESSION", label: "Per Session", icon: Layers },
              ] as { value: PriceUnit; label: string; icon: typeof Clock }[]
            ).map((o) => {
              const on = setup.unit === o.value;
              return (
                <button
                  key={o.value}
                  type="button"
                  role="radio"
                  aria-checked={on}
                  onClick={() => onChange({ ...setup, unit: o.value })}
                  className={cn("flex items-center justify-center gap-2 text-sm font-semibold transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-[#4817C2]", on ? "bg-[#4817C2] text-white" : "bg-white hover:bg-[#FBFAFE]")}
                >
                  <o.icon className="h-4 w-4" aria-hidden="true" />
                  {o.label}
                </button>
              );
            })}
          </div>
        </div>

        <div>
          <label htmlFor={`${idPrefix}-base`} className="mb-1.5 block text-sm font-semibold">
            Base Price (per {per}) <span className="text-[#C62828]">*</span>
          </label>
          <AmountField id={`${idPrefix}-base`} label={`Base price per ${per}`} value={setup.basePrice} onChange={setBase} invalid={!!problems.base} />
          {problems.base && <FieldError>{problems.base}</FieldError>}
        </div>
      </div>

      <label className="flex w-fit cursor-pointer items-center gap-2 text-sm font-semibold">
        <input type="checkbox" checked={setup.timeBased} onChange={(e) => setTimeBased(e.target.checked)} className="h-4 w-4 cursor-pointer rounded accent-[#4817C2]" />
        Enable Time-based Pricing
        <span title="Charge a different price for certain times of the day. Anything outside your time slots uses the base price." className="font-normal text-[#666666]">
          <Info className="h-4 w-4" aria-hidden="true" />
          <span className="sr-only">Charge a different price for certain times of the day. Anything outside your time slots uses the base price.</span>
        </span>
      </label>

      {setup.timeBased && (
        <div className="space-y-3">
          {settings.differentWeekendPricing && (
            <div role="tablist" aria-label="Days" className="grid grid-cols-1 gap-2 sm:grid-cols-3">
              {TABS.map((t) => {
                const on = tab === t.group;
                return (
                  <button
                    key={t.group}
                    type="button"
                    role="tab"
                    aria-selected={on}
                    onClick={() => setTab(t.group)}
                    className={cn(
                      "flex items-center gap-2.5 rounded-lg border px-3 py-2 text-left transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#4817C2]",
                      on ? "border-[#4817C2] bg-[#F1EBFF]" : "border-[#E5E1EF] bg-white hover:bg-[#FBFAFE]",
                    )}
                  >
                    <CalendarDays className={cn("h-5 w-5 shrink-0", on ? "text-[#4817C2]" : "text-[#171717]")} aria-hidden="true" />
                    <span className="min-w-0">
                      <span className={cn("block text-sm font-semibold leading-tight", on && "text-[#4817C2]")}>{t.title}</span>
                      <span className="block text-xs font-normal text-[#666666]">{t.hint}</span>
                    </span>
                  </button>
                );
              })}
            </div>
          )}

          <div className="rounded-xl border border-[#E5E1EF] bg-[#FDFCFF] p-3">
            <div className="mb-2 flex items-center justify-between gap-2">
              <h4 className="text-sm font-semibold">
                {groupTitle} <span className="font-normal text-[#666666]">({dayGroupLabel(group, setup.specific.days)})</span>
              </h4>
              <span className="rounded-md bg-[#EDE7FF] px-2 py-0.5 text-xs font-semibold text-[#4817C2]">
                {slots.length} {slots.length === 1 ? "Time Slot" : "Time Slots"}
              </span>
            </div>

            {group === "SPECIFIC_DAYS" && (
              <div className="mb-3">
                <DayChips value={setup.specific.days} onChange={(days) => onChange({ ...setup, specific: { ...setup.specific, days } })} idPrefix={`${idPrefix}-specific-day`} />
              </div>
            )}

            <ul className="space-y-2">
              {slots.map((s, i) => {
                const label = `${dayGroupLabel(group, setup.specific.days)} slot ${i + 1}`;
                const problem = problems.slots[s.id];
                const time = (
                  <div className="grid min-w-0 grid-cols-2 gap-2">
                    <TimeField id={`${idPrefix}-${group}-${s.id}-start`} ariaLabel={`${label} starts at`} value={s.start} onChange={(v) => patchSlot(s.id, { start: v })} invalid={!!problem} />
                    <TimeField id={`${idPrefix}-${group}-${s.id}-end`} ariaLabel={`${label} ends at`} value={s.end} onChange={(v) => patchSlot(s.id, { end: v })} invalid={!!problem} />
                  </div>
                );
                const price = <AmountField id={`${idPrefix}-${group}-${s.id}-price`} label={`${label} price`} value={s.price} onChange={(v) => setPrice(s, v)} invalid={!!problem} />;
                const tier = (
                  <div className="flex items-center gap-2">
                    <div className="min-w-0 flex-1">
                      <SetupSelect
                        id={`${idPrefix}-${group}-${s.id}-tier`}
                        ariaLabel={`${label} tag`}
                        value={s.tier || "NONE"}
                        onChange={(v) => patchSlot(s.id, { tier: v === "NONE" ? "" : (v as RateTier), tierTouched: true })}
                        options={TIER_OPTIONS}
                      />
                    </div>
                    <button
                      type="button"
                      aria-label={`Remove ${label}`}
                      onClick={() => onChange(withSlots(setup, group, slots.filter((x) => x.id !== s.id)))}
                      className="flex h-11 w-9 shrink-0 items-center justify-center rounded-lg text-[#C62828] hover:bg-[#FDECEA] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#C62828]"
                    >
                      <Trash2 className="h-4 w-4" aria-hidden="true" />
                    </button>
                  </div>
                );
                return (
                  <li key={s.id}>
                    {wide ? (
                      <div className="grid grid-cols-[minmax(0,1.5fr)_minmax(0,0.8fr)_minmax(0,1fr)] items-start gap-2">
                        {time}
                        {price}
                        {tier}
                      </div>
                    ) : (
                      <div className="space-y-2 rounded-lg border border-[#EFECF6] bg-white p-2.5">
                        {time}
                        <div className="grid grid-cols-[minmax(0,1fr)_minmax(0,1.3fr)] gap-2">
                          {price}
                          {tier}
                        </div>
                      </div>
                    )}
                    {problem && <FieldError>{problem}</FieldError>}
                    {s.tier && !wide && <span className={cn("mt-1 inline-block rounded-md px-2 py-0.5 text-xs font-semibold", TIER_STYLE[s.tier])}>{TIER_LABEL[s.tier]}</span>}
                  </li>
                );
              })}
            </ul>

            {problems.groups[group] && <FieldError>{problems.groups[group]}</FieldError>}

            <button
              type="button"
              onClick={addSlot}
              className="mt-2 flex h-10 w-full items-center justify-center gap-1.5 rounded-lg border border-dashed border-[#4817C2]/60 bg-[#F8F4FF] text-sm font-semibold text-[#4817C2] hover:bg-[#F1EBFF] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#4817C2]"
            >
              <Plus className="h-4 w-4" aria-hidden="true" />
              Add Time Slot
            </button>
          </div>
        </div>
      )}

      {(settings.memberPricingEnabled || settings.coachingPricingEnabled) && (
        <div className="grid gap-4 sm:grid-cols-2">
          {settings.memberPricingEnabled && (
            <div>
              <label htmlFor={`${idPrefix}-member`} className="mb-1.5 block text-sm font-semibold">
                Member Price (per {per}) <span className="text-[#C62828]">*</span>
              </label>
              <AmountField id={`${idPrefix}-member`} label={`Member price per ${per}`} value={setup.memberPrice} onChange={(v) => onChange({ ...setup, memberPrice: v })} invalid={!!problems.member} />
              {problems.member && <FieldError>{problems.member}</FieldError>}
            </div>
          )}
          {settings.coachingPricingEnabled && (
            <div>
              <label htmlFor={`${idPrefix}-coaching`} className="mb-1.5 block text-sm font-semibold">
                Coaching Price (per {per}) <span className="text-[#C62828]">*</span>
              </label>
              <AmountField id={`${idPrefix}-coaching`} label={`Coaching price per ${per}`} value={setup.coachingPrice} onChange={(v) => onChange({ ...setup, coachingPrice: v })} invalid={!!problems.coaching} />
              {problems.coaching && <FieldError>{problems.coaching}</FieldError>}
            </div>
          )}
        </div>
      )}
    </div>
  );
}

