"use client";

import { Eye, SlidersHorizontal } from "lucide-react";
import { CardHeading, SetupCard } from "@/features/onboarding/components/setup-fields";
import { ToggleRow } from "@/features/operating-hours/setup/hours-parts";
import { previewRows, priceRangeLabel, type PriceSetup, type PricingSettings } from "@/features/pricing/setup/pricing-setup-model";
import type { CourtEntry, SportEntry } from "@/features/pricing/setup/pricing-views";

export function PricingSettingsCard({ settings, onChange }: { settings: PricingSettings; onChange: (next: PricingSettings) => void }) {
  return (
    <SetupCard className="p-4 sm:p-5">
      <CardHeading icon={<SlidersHorizontal className="h-7 w-7" aria-hidden="true" />} title="Pricing Settings" />
      <div className="divide-y divide-[#EFECF6]">
        <ToggleRow
          id="different-weekend"
          title="Allow different pricing for weekdays & weekends"
          hint="Charge different rates on Monday to Friday, on Saturday and Sunday, and on days you choose. Off means one set of prices for every day."
          description="Set separate rates for Mon – Fri and Sat – Sun."
          checked={settings.differentWeekendPricing}
          onChange={(v) => onChange({ ...settings, differentWeekendPricing: v })}
        />
        <ToggleRow
          id="member-pricing"
          title="Enable member pricing"
          hint="Adds a member rate to each sport or court. It is saved for membership bookings; it does not change what players pay today."
          description="Offer special rates for membership bookings."
          checked={settings.memberPricingEnabled}
          onChange={(v) => onChange({ ...settings, memberPricingEnabled: v })}
        />
        <ToggleRow
          id="coaching-pricing"
          title="Enable coaching pricing"
          hint="Adds a coaching rate to each sport or court. It is saved for coaching sessions; it does not change what players pay today."
          description="Set separate pricing for coaching sessions."
          checked={settings.coachingPricingEnabled}
          onChange={(v) => onChange({ ...settings, coachingPricingEnabled: v })}
        />
      </div>
    </SetupCard>
  );
}

/**
 * "Pricing Preview": the prices of everything that has been priced. By Sport it is a line per sport; By Court it is every court (under
 * its sport) with all of its rates, not only the court being edited.
 */
export function PricingPreviewCard({
  mode,
  settings,
  sports,
  sportSetups,
  courts,
  courtSetups,
}: {
  mode: PricingSettings["mode"];
  settings: PricingSettings;
  sports: SportEntry[];
  sportSetups: Record<string, PriceSetup>;
  courts: CourtEntry[];
  courtSetups: Record<string, PriceSetup>;
}) {
  if (mode === "BY_COURT") {
    return (
      <SetupCard className="p-4 sm:p-5">
        <CardHeading icon={<Eye className="h-7 w-7" aria-hidden="true" />} title="Pricing Preview" description="Here's a quick summary of your pricing setup." />
        <div className="space-y-4">
          {sports.map((sport) => {
            const own = courts.filter((c) => c.sportId === sport.id);
            if (own.length === 0) return null;
            return (
              <section key={sport.id} aria-label={`${sport.name} prices`}>
                <h3 className="mb-2 flex items-center gap-2 text-sm font-semibold">
                  <span aria-hidden="true" className="text-lg leading-none">
                    {sport.icon}
                  </span>
                  {sport.name}
                </h3>
                <ul className="space-y-2">
                  {own.map((c) => {
                    const setup = courtSetups[c.id];
                    const rows = setup ? previewRows(setup, settings) : [];
                    return (
                      <li key={c.id} className="overflow-hidden rounded-lg border border-[#EFECF6]">
                        <div className="flex items-center justify-between gap-2 bg-[#F7F5FB] px-3 py-2 text-sm font-semibold">
                          <span>{c.name}</span>
                          {rows.length === 0 && <span className="text-xs font-medium text-[#666666]">Not set</span>}
                        </div>
                        {rows.length > 0 && (
                          <ul>
                            {rows.map((r, i) => (
                              <li key={i} className="grid grid-cols-[84px_1fr_auto] items-center gap-2 border-t border-[#EFECF6] px-3 py-2 text-sm">
                                <span className="font-medium">{r.day}</span>
                                <span>{r.time}</span>
                                <span className="text-right font-medium">{r.rate}</span>
                              </li>
                            ))}
                          </ul>
                        )}
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

  return (
    <SetupCard className="p-4 sm:p-5">
      <CardHeading icon={<Eye className="h-7 w-7" aria-hidden="true" />} title="Pricing Preview" description="Here's a quick summary of your pricing setup." />
      <ul className="space-y-2">
        {sports.map((s) => (
          <li key={s.id} className="flex items-center gap-3 rounded-lg bg-[#F7F5FB] px-3 py-2.5 text-sm">
            <span aria-hidden="true" className="text-xl leading-none">
              {s.icon}
            </span>
            <span className="flex-1 font-semibold">{s.name}</span>
            <span className="font-semibold">{sportSetups[s.id] ? priceRangeLabel(sportSetups[s.id]!, settings) : "Not set"}</span>
          </li>
        ))}
      </ul>
    </SetupCard>
  );
}
