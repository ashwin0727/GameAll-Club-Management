"use client";

import * as React from "react";
import { Check, ChevronDown, ChevronRight, ChevronUp, Home, Layers, LayoutGrid, Plus, Snowflake, Sprout } from "lucide-react";
import { CardHeading, SetupCard, SetupSelect } from "@/features/onboarding/components/setup-fields";
import { PriceEditor } from "@/features/pricing/setup/price-editor";
import { priceRangeLabel, type PriceSetup, type PricingSettings, type SetupProblems } from "@/features/pricing/setup/pricing-setup-model";
import { cn } from "@/lib/utils";

export interface SportEntry {
  /** facility_sports.id */
  id: string;
  name: string;
  icon: string;
}

export interface CourtEntry {
  id: string;
  name: string;
  /** the sport's facility_sports.id */
  sportId: string;
  type: "INDOOR" | "OUTDOOR";
  surface?: string;
  ac: boolean;
}

interface ViewProps {
  settings: PricingSettings;
  span: { open: string; close: string };
  problems: Record<string, SetupProblems>;
}

const NO_PROBLEMS: SetupProblems = { slots: {}, groups: {} };

// ── By Sport ───────────────────────────────────────────────────────────────

/** "Sport Pricing": one row per sport (its price when folded), the open one shows the editor. */
export function SportPricingView({
  sports,
  setups,
  onChange,
  expandedId,
  onExpand,
  onAddSportPricing,
  canAddSportPricing,
  settings,
  span,
  problems,
}: ViewProps & {
  sports: SportEntry[];
  setups: Record<string, PriceSetup>;
  onChange: (id: string, next: PriceSetup) => void;
  expandedId: string | null;
  onExpand: (id: string | null) => void;
  onAddSportPricing: () => void;
  canAddSportPricing: boolean;
}) {
  return (
    <SetupCard className="p-4 sm:p-5">
      <CardHeading
        icon={<Layers className="h-7 w-7" aria-hidden="true" />}
        title="Sport Pricing"
        description="Add and manage booking rates for each sport."
        action={
          <button
            type="button"
            onClick={onAddSportPricing}
            disabled={!canAddSportPricing}
            className="flex h-10 shrink-0 items-center gap-1.5 rounded-lg border border-[#4817C2]/50 bg-white px-3 text-sm font-semibold text-[#4817C2] hover:bg-[#F8F4FF] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#4817C2] disabled:cursor-not-allowed disabled:opacity-50"
          >
            <Plus className="h-4 w-4" aria-hidden="true" />
            Add Sport Pricing
          </button>
        }
      />
      <ul className="space-y-2">
        {sports.map((sport) => {
          const setup = setups[sport.id];
          const open = expandedId === sport.id;
          const p = problems[sport.id];
          return (
            <li key={sport.id} className={cn("overflow-hidden rounded-xl border", open ? "border-[#E5E1EF]" : p && Object.keys(p).length && p.base ? "border-[#C62828]" : "border-[#EFECF6]")}>
              <button
                type="button"
                aria-expanded={open}
                aria-controls={`sport-panel-${sport.id}`}
                onClick={() => onExpand(open ? null : sport.id)}
                className={cn("flex h-12 w-full items-center gap-3 px-3 text-left transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-[#4817C2]", open ? "bg-[#F1EBFF]" : "bg-[#FBFAFE] hover:bg-[#F7F4FD]")}
              >
                <span className="text-2xl leading-none" aria-hidden="true">
                  {sport.icon}
                </span>
                <span className="flex-1 text-base font-semibold">{sport.name}</span>
                {!open && setup && <span className="text-sm font-normal text-[#171717]">{priceRangeLabel(setup, settings)}</span>}
                {open ? <ChevronUp className="h-5 w-5" aria-hidden="true" /> : <ChevronDown className="h-5 w-5" aria-hidden="true" />}
              </button>
              {open && setup && (
                <div id={`sport-panel-${sport.id}`} role="region" aria-label={`${sport.name} pricing`} className="p-3 sm:p-4">
                  <PriceEditor idPrefix={`sport-${sport.id}`} setup={setup} onChange={(next) => onChange(sport.id, next)} settings={settings} span={span} problems={p ?? NO_PROBLEMS} />
                </div>
              )}
            </li>
          );
        })}
      </ul>
    </SetupCard>
  );
}

// ── By Court ───────────────────────────────────────────────────────────────

export function CourtList({
  sports,
  courts,
  setups,
  selectedId,
  onSelect,
  filter,
  onFilter,
}: {
  sports: SportEntry[];
  courts: CourtEntry[];
  setups: Record<string, PriceSetup>;
  selectedId: string | null;
  onSelect: (id: string) => void;
  filter: string;
  onFilter: (sportId: string) => void;
}) {
  const priced = (id: string) => {
    const s = setups[id];
    return !!s && Number(s.basePrice) > 0;
  };
  const shown = sports.filter((s) => filter === "ALL" || s.id === filter);
  return (
    <SetupCard className="p-3 sm:p-4">
      <div className="mb-3 flex items-center justify-between gap-2">
        <h2 className="flex items-center gap-2 text-base font-semibold">
          <LayoutGrid className="h-5 w-5" aria-hidden="true" />
          Select Court
        </h2>
        <div className="w-[130px]">
          <SetupSelect id="court-sport-filter" ariaLabel="Filter by sport" value={filter} onChange={onFilter} options={[{ value: "ALL", label: "All Sports" }, ...sports.map((s) => ({ value: s.id, label: s.name }))]} />
        </div>
      </div>
      <div className="space-y-3">
        {shown.map((sport) => {
          const list = courts.filter((c) => c.sportId === sport.id);
          return (
            <section key={sport.id} aria-label={`${sport.name} courts`}>
              <h3 className="mb-1.5 flex items-center gap-2 rounded-lg bg-[#F1EBFF] px-3 py-2 text-sm font-semibold">
                <span aria-hidden="true" className="text-lg leading-none">
                  {sport.icon}
                </span>
                {sport.name} ({list.length})
              </h3>
              <ul className="space-y-1.5">
                {list.map((c) => {
                  const on = c.id === selectedId;
                  return (
                    <li key={c.id}>
                      <button
                        type="button"
                        aria-current={on ? "true" : undefined}
                        onClick={() => onSelect(c.id)}
                        className={cn("flex h-11 w-full items-center gap-2 rounded-lg border px-2.5 text-left text-sm transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#4817C2]", on ? "border-[#4817C2] bg-[#F8F4FF]" : "border-[#EFECF6] bg-white hover:bg-[#FBFAFE]")}
                      >
                        <span
                          aria-label={priced(c.id) ? "Price set" : "No price yet"}
                          className={cn("flex h-5 w-5 shrink-0 items-center justify-center rounded-full border", priced(c.id) ? "border-[#2E7D32] bg-[#2E7D32] text-white" : "border-[#D6D2E3] bg-white")}
                        >
                          {priced(c.id) && <Check className="h-3 w-3" strokeWidth={3} aria-hidden="true" />}
                        </span>
                        <span className="min-w-0 flex-1 truncate font-medium">{c.name}</span>
                        <span className="flex shrink-0 items-center gap-1 rounded-md bg-[#EDE7FF] px-1.5 py-0.5 text-[11px] font-semibold text-[#4817C2]">
                          <Snowflake className="h-3 w-3" aria-hidden="true" />
                          {c.ac ? "AC" : "Non-AC"}
                        </span>
                        <ChevronRight className="h-4 w-4 shrink-0" aria-hidden="true" />
                      </button>
                    </li>
                  );
                })}
              </ul>
            </section>
          );
        })}
      </div>
    </SetupCard>
  );
}

export function CourtPricingPanel({
  court,
  sport,
  setup,
  onChange,
  settings,
  span,
  problems,
}: Omit<ViewProps, "problems"> & {
  problems: SetupProblems;
  court: CourtEntry;
  sport: SportEntry | undefined;
  setup: PriceSetup;
  onChange: (next: PriceSetup) => void;
}) {
  return (
    <SetupCard className="p-4 sm:p-5">
      <div className="mb-4 flex items-start gap-3 border-b border-[#EFECF6] pb-3">
        <span aria-hidden="true" className="text-3xl leading-none">
          {sport?.icon}
        </span>
        <div className="min-w-0">
          <h2 className="text-lg font-semibold leading-tight">
            {court.name} – {sport?.name}
          </h2>
          <div className="mt-1.5 flex flex-wrap gap-1.5">
            <span className="flex items-center gap-1 rounded-md bg-[#EDE7FF] px-2 py-0.5 text-xs font-semibold text-[#4817C2]">
              <Home className="h-3 w-3" aria-hidden="true" />
              {court.type === "INDOOR" ? "Indoor" : "Outdoor"}
            </span>
            {court.surface && (
              <span className="flex items-center gap-1 rounded-md bg-[#EDE7FF] px-2 py-0.5 text-xs font-semibold text-[#4817C2]">
                <Sprout className="h-3 w-3" aria-hidden="true" />
                {court.surface}
              </span>
            )}
            {court.ac && (
              <span className="flex items-center gap-1 rounded-md bg-[#EDE7FF] px-2 py-0.5 text-xs font-semibold text-[#4817C2]">
                <Snowflake className="h-3 w-3" aria-hidden="true" />
                AC
              </span>
            )}
          </div>
        </div>
      </div>

      <PriceEditor idPrefix={`court-${court.id}`} setup={setup} onChange={onChange} settings={settings} span={span} problems={problems} />

      <p className="mt-4 flex items-start gap-2 rounded-lg bg-[#F7F5FB] px-3 py-2.5 text-xs font-normal text-[#666666]">
        <span aria-hidden="true">ⓘ</span>
        <span>
          This pricing applies only to <strong className="font-semibold text-[#171717]">{court.name}</strong>. Set prices for other courts from the list.
        </span>
      </p>
    </SetupCard>
  );
}
