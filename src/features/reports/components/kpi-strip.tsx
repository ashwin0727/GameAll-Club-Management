"use client";

import Link from "next/link";
import { Info } from "lucide-react";
import { StatCard } from "@/components/shared/stat-card";
import { KPI_DEFINITIONS, type KpiKey } from "../definitions";

export interface KpiStripItem {
  key: KpiKey;
  label: string;
  /** Already formatted for display (currency, %, count). */
  value: string;
  accent: string;
  hint?: React.ReactNode;
  /** When set, the whole card links here (drill-down). */
  href?: string;
}

/**
 * The KPI row shared by every report. A wrapping grid — never a fixed-width
 * scroller — so it reflows cleanly from a 360px phone to a wide desktop
 * without the page scrolling sideways (spec §38/§54). Each figure's formula
 * is available on hover (`title`) and to screen readers (`sr-only`); this
 * codebase has no tooltip primitive, so no library is pulled in for it.
 */
export function KpiStrip({ items }: { items: KpiStripItem[] }) {
  return (
    <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 xl:grid-cols-6">
      {items.map((item, index) => {
        const definition = KPI_DEFINITIONS[item.key];
        const card = (
          <StatCard
            label={item.label}
            value={item.value}
            accent={item.accent}
            index={index}
            hint={
              <span className="inline-flex items-center gap-1 text-muted-foreground" title={definition}>
                {item.hint}
                <Info className="h-3 w-3" aria-hidden />
                <span className="sr-only">
                  {item.label}: {definition}
                </span>
              </span>
            }
            className="h-full"
          />
        );
        return item.href ? (
          <Link
            key={item.key}
            href={item.href}
            className="rounded-xl focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
          >
            {card}
          </Link>
        ) : (
          <div key={item.key}>{card}</div>
        );
      })}
    </div>
  );
}
