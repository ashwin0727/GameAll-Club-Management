"use client";

import { Plus } from "lucide-react";

/** Sampled from the artwork's own pale-mint backdrop, so the panel and the image read as one surface. */
const PANEL_TINT = "#EAF9F1";

/** Clearance reserved at the right edge for the Add New Member button, so the artwork never sits under it. */
const BUTTON_LANE = 210;

/**
 * The Membership Dashboard's hero: the title block, then a panel whose background IS the
 * `Membership_Dashboard.png` artwork (shuttlecock + "Play Connect Grow" are part of the image
 * — nothing of ours is drawn over them), with the Add New Member button at the right.
 *
 * The artwork is sized to 60% of the panel's width (the value dialled in against the live
 * page). It's anchored a button's width in from the right so the button sits beside it rather
 * than over it.
 *
 * The panel's fill starts at the title block's own card colour and eases into the artwork's
 * tint, so the two halves read as one surface instead of meeting at a visible step. The fade
 * over the artwork's left edge starts transparent for the same reason — it must not repaint
 * that junction.
 */
export function MembershipDashboardHero({
  title,
  subtitle,
  tagline,
  taglineSub,
  onAddMember,
}: {
  title: string;
  subtitle: string;
  tagline: string;
  taglineSub: string;
  /** Omit to render the hero without the "Add New Member" button — used on pages where it doesn't apply. */
  onAddMember?: () => void;
}) {
  return (
    <div className="flex flex-col overflow-hidden rounded-2xl border-r border-border/60 bg-card lg:h-[100px] lg:flex-row lg:items-stretch">
      <div className="flex min-w-0 flex-col justify-center gap-1 px-6 py-4 lg:w-[34%]">
        <h1 className="truncate text-2xl font-bold text-black dark:text-foreground">{title}</h1>
        <p className="truncate text-sm text-muted-foreground">{subtitle}</p>
      </div>

      {/* Hidden on mobile/tablet — the decorative artwork + tagline don't earn their space below
       *  the title on a phone screen; desktop (lg+, where this sits beside the title instead of
       *  under it) is unaffected. The button moves to its own always-visible row below instead
       *  of disappearing along with the artwork it's drawn over. */}
      <div
        className="relative hidden flex-1 items-center gap-4 px-6 lg:flex"
        style={{
          backgroundImage: `url(/assets/Membership_Dashboard.png), linear-gradient(to right, hsl(var(--card)) 0%, ${PANEL_TINT} 22%, ${PANEL_TINT} 100%)`,
          backgroundSize: "60%, 100% 100%",
          backgroundPosition: `right ${BUTTON_LANE}px center, left center`,
          backgroundRepeat: "no-repeat, no-repeat",
        }}
      >
        {/* Feathers the artwork's left edge into the tint. Transparent at the very left so it
            never repaints the join with the title block. */}
        <div
          aria-hidden
          className="pointer-events-none absolute inset-y-0 left-0 w-[62%]"
          style={{
            backgroundImage: `linear-gradient(to right, transparent 0%, ${PANEL_TINT} 14%, ${PANEL_TINT} 40%, transparent 100%)`,
          }}
        />

        <div className="relative z-10 min-w-0 flex-1">
          <p className="text-[15px] font-bold leading-snug text-black">{tagline}</p>
          <p className="mt-1 text-xs text-black/70">{taglineSub}</p>
        </div>

        {onAddMember && (
          <button
            type="button"
            onClick={onAddMember}
            className="relative z-10 flex h-10 shrink-0 items-center gap-2 whitespace-nowrap rounded-[10px] bg-[#0B7A55] px-4 text-sm font-semibold text-white shadow-sm transition-opacity hover:opacity-90"
          >
            <Plus className="h-4 w-4" aria-hidden />
            Add New Member
          </button>
        )}
      </div>

      {onAddMember && (
        <div className="px-6 pb-4 lg:hidden">
          <button
            type="button"
            onClick={onAddMember}
            className="flex h-10 w-full items-center justify-center gap-2 rounded-[10px] bg-[#0B7A55] px-4 text-sm font-semibold text-white shadow-sm transition-opacity hover:opacity-90"
          >
            <Plus className="h-4 w-4" aria-hidden />
            Add New Member
          </button>
        </div>
      )}
    </div>
  );
}
