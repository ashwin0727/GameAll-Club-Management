import { fromMinorUnits, toMinorUnits } from "@/features/pricing/money";
import type { PricingAudience, PricingDayType, PricingRule, RateTier } from "@/features/pricing/types";
import { validatePricingRules } from "@/features/pricing/validation";
import { SHORT_DAY, formatClock } from "@/features/operating-hours/setup-model";
import type { DayOfWeek, OperatingDay } from "@/features/operating-hours/types";

/**
 * The Pricing step edits one setup per sport (By Sport) or per court (By Court): a base price, optionally broken into time slots for
 * weekdays / weekends / chosen days, and optionally a member rate and a coaching rate. These helpers turn that into the rules that are
 * saved (and back) and check it; they are pure so the same rules can be tested without the screen.
 */

export type PricingMode = "BY_SPORT" | "BY_COURT";
export type PriceUnit = "PER_HOUR" | "PER_SESSION";
/** The day groups a time slot list can belong to. ALL_DAYS is used when weekday / weekend pricing is switched off. */
export type SlotGroup = "ALL_DAYS" | "WEEKDAYS" | "WEEKENDS" | "SPECIFIC_DAYS";

export interface Slot {
  /** UI id only. */
  id: string;
  /** "HH:MM" */
  start: string;
  end: string;
  /** Typed amount in rupees ("550"). */
  price: string;
  tier: RateTier | "";
  /** True once the owner picked the tag themselves, so it stops following the price. */
  tierTouched?: boolean;
}

export interface PriceSetup {
  unit: PriceUnit;
  basePrice: string;
  timeBased: boolean;
  allDays: Slot[];
  weekdays: Slot[];
  weekends: Slot[];
  specific: { days: DayOfWeek[]; slots: Slot[] };
  memberPrice: string;
  coachingPrice: string;
}

export interface PricingSettings {
  mode: PricingMode;
  differentWeekendPricing: boolean;
  memberPricingEnabled: boolean;
  coachingPricingEnabled: boolean;
}

export const DEFAULT_PRICING_SETTINGS: PricingSettings = { mode: "BY_SPORT", differentWeekendPricing: true, memberPricingEnabled: false, coachingPricingEnabled: false };

const CURRENCY = "INR";
let counter = 0;
export const newSlotId = () => `slot-${++counter}-${Math.random().toString(36).slice(2, 7)}`;

export function emptySetup(): PriceSetup {
  return { unit: "PER_HOUR", basePrice: "", timeBased: false, allDays: [], weekdays: [], weekends: [], specific: { days: [], slots: [] }, memberPrice: "", coachingPrice: "" };
}

export function cloneSetup(s: PriceSetup): PriceSetup {
  const slots = (list: Slot[]) => list.map((x) => ({ ...x, id: newSlotId() }));
  return { ...s, allDays: slots(s.allDays), weekdays: slots(s.weekdays), weekends: slots(s.weekends), specific: { days: [...s.specific.days], slots: slots(s.specific.slots) } };
}

export function slotsOf(setup: PriceSetup, group: SlotGroup): Slot[] {
  return group === "ALL_DAYS" ? setup.allDays : group === "WEEKDAYS" ? setup.weekdays : group === "WEEKENDS" ? setup.weekends : setup.specific.slots;
}

export function withSlots(setup: PriceSetup, group: SlotGroup, slots: Slot[]): PriceSetup {
  if (group === "ALL_DAYS") return { ...setup, allDays: slots };
  if (group === "WEEKDAYS") return { ...setup, weekdays: slots };
  if (group === "WEEKENDS") return { ...setup, weekends: slots };
  return { ...setup, specific: { ...setup.specific, slots } };
}

/** The tag a slot gets from its price: above the base price is Peak, below it Off-Peak, equal none. */
export function autoTier(price: string, base: string): RateTier | "" {
  const p = Number(price);
  const b = Number(base);
  if (!(p > 0) || !(b > 0) || p === b) return "";
  return p > b ? "PEAK" : "OFF_PEAK";
}

export const TIER_LABEL: Record<RateTier, string> = { PEAK: "Peak", OFF_PEAK: "Off-Peak" };

// ── setup -> rules ──────────────────────────────────────────────────────

/** The open window to start new slots from: the earliest opening and the latest closing across the open days. */
export function openSpan(days: OperatingDay[] | null): { open: string; close: string } {
  const slots = (days ?? []).filter((d) => !d.isClosed && !d.is24Hours).flatMap((d) => d.slots);
  if (slots.length === 0) return { open: "06:00", close: "23:00" };
  const open = slots.map((s) => s.startTime).sort()[0]!;
  const close = slots.map((s) => s.endTime).sort().reverse()[0]!;
  return { open, close };
}

/** A new slot starts where the last one ended (or at opening) and runs to closing. */
export function nextSlot(existing: Slot[], span: { open: string; close: string }): Slot {
  const last = existing[existing.length - 1];
  let start = last ? last.end : span.open;
  let end = span.close;
  if (start === end) {
    start = span.open;
    end = span.close;
  }
  return { id: newSlotId(), start, end, price: "", tier: "" };
}

export interface RuleScope {
  facilitySportId: string;
  playingAreaId?: string;
}

/** The rules to save for one sport or court. */
export function rulesFromSetup(setup: PriceSetup, scope: RuleScope, settings: PricingSettings): PricingRule[] {
  const priority = scope.playingAreaId ? 10 : 0;
  const base = (audience: PricingAudience, amount: string): PricingRule => ({
    facilitySportId: scope.facilitySportId,
    playingAreaId: scope.playingAreaId,
    dayType: "ALL_DAYS",
    coversFullDay: true,
    amountMinor: toMinorUnits(amount, CURRENCY),
    currency: CURRENCY,
    pricingUnit: setup.unit,
    priority,
    audience,
  });
  const rules: PricingRule[] = [];
  if (setup.basePrice.trim() !== "") rules.push(base("GENERAL", setup.basePrice));

  if (setup.timeBased) {
    const groups: { dayType: PricingDayType; slots: Slot[]; days?: DayOfWeek[] }[] = settings.differentWeekendPricing
      ? [
          { dayType: "WEEKDAYS", slots: setup.weekdays },
          { dayType: "WEEKENDS", slots: setup.weekends },
          { dayType: "SPECIFIC_DAYS", slots: setup.specific.slots, days: setup.specific.days },
        ]
      : [{ dayType: "ALL_DAYS", slots: setup.allDays }];
    for (const g of groups) {
      for (const slot of g.slots) {
        if (slot.price.trim() === "") continue;
        rules.push({
          facilitySportId: scope.facilitySportId,
          playingAreaId: scope.playingAreaId,
          dayType: g.dayType,
          daysOfWeek: g.dayType === "SPECIFIC_DAYS" ? [...(g.days ?? [])].sort() : undefined,
          rateTier: slot.tier || undefined,
          coversFullDay: false,
          startTime: slot.start,
          endTime: slot.end,
          amountMinor: toMinorUnits(slot.price, CURRENCY),
          currency: CURRENCY,
          pricingUnit: setup.unit,
          priority,
          audience: "GENERAL",
        });
      }
    }
  }
  if (settings.memberPricingEnabled && setup.memberPrice.trim() !== "") rules.push(base("MEMBER", setup.memberPrice));
  if (settings.coachingPricingEnabled && setup.coachingPrice.trim() !== "") rules.push(base("COACHING", setup.coachingPrice));
  return rules;
}

// ── rules -> setup ──────────────────────────────────────────────────────

const amountText = (minor: number) => String(fromMinorUnits(minor, CURRENCY));

/** Reads one sport's or court's saved rules back as a setup. [span] fills in the hours for an old day-scoped full-day rate. */
export function setupFromRules(rules: PricingRule[], span: { open: string; close: string }): PriceSetup {
  const setup = emptySetup();
  if (rules.length === 0) return setup;

  const general = rules.filter((r) => (r.audience ?? "GENERAL") === "GENERAL");
  const first = general[0] ?? rules[0]!;
  setup.unit = first.pricingUnit === "PER_SESSION" ? "PER_SESSION" : "PER_HOUR";

  const fullDayAll = general.find((r) => r.coversFullDay && r.dayType === "ALL_DAYS");
  const timed = general.filter((r) => !r.coversFullDay);
  // an old full-day rate for weekdays / weekends / chosen days becomes a slot over the open hours
  const legacy = general.filter((r) => r.coversFullDay && r.dayType !== "ALL_DAYS");

  const toSlot = (r: PricingRule, start?: string, end?: string): Slot => ({
    id: newSlotId(),
    start: start ?? r.startTime ?? span.open,
    end: end ?? r.endTime ?? span.close,
    price: amountText(r.amountMinor),
    tier: r.rateTier ?? "",
    tierTouched: !!r.rateTier,
  });

  for (const r of [...timed, ...legacy]) {
    const slot = r.coversFullDay ? toSlot(r, span.open, span.close) : toSlot(r);
    if (r.dayType === "WEEKDAYS") setup.weekdays.push(slot);
    else if (r.dayType === "WEEKENDS") setup.weekends.push(slot);
    else if (r.dayType === "SPECIFIC_DAYS") {
      setup.specific.days = [...new Set([...setup.specific.days, ...((r.daysOfWeek ?? []) as DayOfWeek[])])];
      setup.specific.slots.push(slot);
    } else setup.allDays.push(slot);
  }
  const sortSlots = (l: Slot[]) => l.sort((a, b) => a.start.localeCompare(b.start));
  sortSlots(setup.weekdays);
  sortSlots(setup.weekends);
  sortSlots(setup.specific.slots);
  sortSlots(setup.allDays);

  setup.timeBased = timed.length > 0 || legacy.length > 0;
  if (fullDayAll) setup.basePrice = amountText(fullDayAll.amountMinor);
  else {
    const prices = general.map((r) => r.amountMinor);
    if (prices.length > 0) setup.basePrice = amountText(Math.min(...prices));
  }

  const member = rules.find((r) => r.audience === "MEMBER");
  const coaching = rules.find((r) => r.audience === "COACHING");
  if (member) setup.memberPrice = amountText(member.amountMinor);
  if (coaching) setup.coachingPrice = amountText(coaching.amountMinor);
  return setup;
}

/** Whether saved rules use weekday / weekend / specific-day pricing (so the "different pricing" setting should start on). */
export function usesDayGroups(rules: PricingRule[]): boolean {
  return rules.some((r) => r.dayType !== "ALL_DAYS");
}

// ── checking ────────────────────────────────────────────────────────────

export interface SetupProblems {
  base?: string;
  member?: string;
  coaching?: string;
  /** keyed by slot id */
  slots: Record<string, string>;
  /** about a whole group, e.g. no days chosen or overlapping slots */
  groups: Partial<Record<SlotGroup, string>>;
}

export function hasSetupProblems(p: SetupProblems): boolean {
  return Boolean(p.base) || Boolean(p.member) || Boolean(p.coaching) || Object.keys(p.slots).length > 0 || Object.keys(p.groups).length > 0;
}

const validAmount = (v: string) => /^\d+(\.\d{1,2})?$/.test(v.trim()) && Number(v) > 0;

export function validateSetup(setup: PriceSetup, scope: RuleScope, settings: PricingSettings, operatingDays: OperatingDay[] | null): SetupProblems {
  const problems: SetupProblems = { slots: {}, groups: {} };

  if (setup.basePrice.trim() === "") problems.base = "Enter the base price.";
  else if (!validAmount(setup.basePrice)) problems.base = "Enter a valid amount greater than 0.";

  if (settings.memberPricingEnabled) {
    if (setup.memberPrice.trim() === "") problems.member = "Enter the member price.";
    else if (!validAmount(setup.memberPrice)) problems.member = "Enter a valid amount greater than 0.";
  }
  if (settings.coachingPricingEnabled) {
    if (setup.coachingPrice.trim() === "") problems.coaching = "Enter the coaching price.";
    else if (!validAmount(setup.coachingPrice)) problems.coaching = "Enter a valid amount greater than 0.";
  }

  if (setup.timeBased) {
    const groups: SlotGroup[] = settings.differentWeekendPricing ? ["WEEKDAYS", "WEEKENDS", "SPECIFIC_DAYS"] : ["ALL_DAYS"];
    for (const group of groups) {
      const slots = slotsOf(setup, group);
      if (group === "SPECIFIC_DAYS" && slots.length > 0 && setup.specific.days.length === 0) problems.groups[group] = "Choose at least one day.";
      for (const slot of slots) {
        if (slot.price.trim() === "") problems.slots[slot.id] = "Enter a price.";
        else if (!validAmount(slot.price)) problems.slots[slot.id] = "Enter a valid amount greater than 0.";
        else if (!slot.start || !slot.end) problems.slots[slot.id] = "Select start and end time.";
        else if (slot.start === slot.end) problems.slots[slot.id] = "Start and end time cannot be the same.";
      }
    }
    // the slots must fit the opening hours and must not overlap each other
    if (Object.keys(problems.slots).length === 0 && Object.keys(problems.groups).length === 0) {
      const timed = rulesFromSetup(setup, scope, settings).filter((r) => !r.coversFullDay && (r.audience ?? "GENERAL") === "GENERAL");
      const result = validatePricingRules(timed, operatingDays ?? undefined);
      if (!result.isValid) {
        const message = result.overlapError ?? result.ruleErrors[0] ?? "Check the time slots.";
        const target = groups.find((g) => slotsOf(setup, g).length > 0) ?? groups[0]!;
        problems.groups[target] = message;
      }
    }
  }
  return problems;
}

// ── preview ─────────────────────────────────────────────────────────────

export const UNIT_SUFFIX: Record<PriceUnit, string> = { PER_HOUR: "/ hour", PER_SESSION: "/ session" };

/** "Mon – Fri", "Sat – Sun", "All days", "Mon, Wed, Fri" */
export function dayGroupLabel(group: SlotGroup, days: DayOfWeek[] = []): string {
  if (group === "WEEKDAYS") return "Mon – Fri";
  if (group === "WEEKENDS") return "Sat – Sun";
  if (group === "ALL_DAYS") return "All days";
  const order: DayOfWeek[] = [1, 2, 3, 4, 5, 6, 0];
  const picked = order.filter((d) => days.includes(d));
  return picked.length === 0 ? "No days" : picked.map((d) => SHORT_DAY[d]).join(", ");
}

/** The lowest and highest price a setup charges, in rupees (the base price and every slot). Null when nothing is priced. */
export function priceRange(setup: PriceSetup, settings: PricingSettings): { min: number; max: number } | null {
  const prices: number[] = [];
  if (validAmount(setup.basePrice)) prices.push(Number(setup.basePrice));
  if (setup.timeBased) {
    const groups: SlotGroup[] = settings.differentWeekendPricing ? ["WEEKDAYS", "WEEKENDS", "SPECIFIC_DAYS"] : ["ALL_DAYS"];
    for (const g of groups) for (const s of slotsOf(setup, g)) if (validAmount(s.price)) prices.push(Number(s.price));
  }
  return prices.length === 0 ? null : { min: Math.min(...prices), max: Math.max(...prices) };
}

const money = (n: number) => `₹${n.toLocaleString("en-IN")}`;

/** "₹400 – ₹650 / hour", "₹2,000 / hour", or "Not set" */
export function priceRangeLabel(setup: PriceSetup, settings: PricingSettings): string {
  const range = priceRange(setup, settings);
  if (!range) return "Not set";
  const text = range.min === range.max ? money(range.min) : `${money(range.min)} – ${money(range.max)}`;
  return `${text} ${UNIT_SUFFIX[setup.unit]}`;
}

export interface PreviewRow {
  day: string;
  time: string;
  rate: string;
}

/** The table under "Pricing Preview" for one court: each day group with its time slots and rates. */
export function previewRows(setup: PriceSetup, settings: PricingSettings): PreviewRow[] {
  const rows: PreviewRow[] = [];
  const suffix = UNIT_SUFFIX[setup.unit];
  if (setup.timeBased) {
    const groups: SlotGroup[] = settings.differentWeekendPricing ? ["WEEKDAYS", "WEEKENDS", "SPECIFIC_DAYS"] : ["ALL_DAYS"];
    for (const g of groups) {
      const label = dayGroupLabel(g, setup.specific.days);
      for (const s of slotsOf(setup, g)) {
        if (!validAmount(s.price)) continue;
        rows.push({ day: label, time: `${formatClock(s.start)} – ${formatClock(s.end)}`, rate: `${money(Number(s.price))}${setup.unit === "PER_SESSION" ? " / session" : ""}` });
      }
    }
  }
  if (validAmount(setup.basePrice)) {
    rows.push({ day: setup.timeBased ? "Other times" : "All days", time: setup.timeBased ? "Outside the slots above" : "Full day", rate: `${money(Number(setup.basePrice))} ${suffix}` });
  }
  return rows;
}

/** The courts' setups grouped by what they charge, so identical ones can share a line. */
export function setupSignature(setup: PriceSetup): string {
  return JSON.stringify([setup.unit, setup.basePrice, setup.timeBased, [setup.allDays, setup.weekdays, setup.weekends, setup.specific.slots].map((l) => l.map((s) => [s.start, s.end, s.price, s.tier])), setup.specific.days]);
}
