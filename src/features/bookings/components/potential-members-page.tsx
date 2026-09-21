"use client";

import { useEffect, useMemo, useState } from "react";
import { Percent, Search, SlidersHorizontal, Star, TrendingUp, Users, X, type LucideIcon } from "lucide-react";
import { PageHero } from "@/components/shared/page-hero";
import { GuestProfileDialog } from "@/features/guests/components/guest-profile-dialog";
import { Card } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { SelectField } from "@/features/bookings/components/select-field";
import { SELECT } from "@/features/bookings/components/booking-toolbar";
import { PaginationControls } from "@/features/bookings/components/pagination-controls";
import {
  BOOKING_COUNT_OPTIONS,
  PotentialMembersPanels,
} from "@/features/bookings/components/potential-members-panels";
import { PotentialMembersTable } from "@/features/bookings/components/potential-members-table";
import { displayPhone } from "@/features/bookings/guest-booking-table";
import { phoneKey } from "@/features/bookings/guest-insights";
import { useGuestProfiles } from "@/features/bookings/hooks/use-potential-members";
import {
  filterPotential,
  potentialMembers,
  segmentStats,
  sortByBookings,
  type GuestProfile,
  type PotentialFilters,
  type PotentialSortDir,
} from "@/features/bookings/potential-members";
import { useFacility } from "@/features/facility/hooks/use-facility";
import { useFacilitySportOptions } from "@/features/facility/hooks/use-facility-sport-options";
import type { GuestPlayer } from "@/features/guests/types";
import { formatCurrency } from "@/features/pricing/money";
import { getGuestService } from "@/services/guests";
import { useUiStore } from "@/stores/ui-store";
import { cn } from "@/lib/utils";

const PAGE_SIZES = [10, 25, 50];
const CONTROL = cn(SELECT, "transition-colors hover:border-foreground/30");

const DEFAULT_FILTERS: PotentialFilters = { search: "", court: "", minBookings: 3, lastBooking: "any", minSpentMinor: 0 };

/** Copy text; if the browser won't allow it, show it to copy by hand. */
async function copyText(text: string): Promise<void> {
  try {
    await navigator.clipboard.writeText(text);
  } catch {
    window.prompt("Copy this:", text);
  }
}

function StatCard({
  icon: Icon,
  tone,
  value,
  label,
  sub,
  subTone,
}: {
  icon: LucideIcon;
  tone: string;
  value: string;
  label: string;
  sub: string;
  subTone?: string;
}) {
  return (
    <Card className="flex items-center gap-4 p-4">
      <span className={cn("flex h-12 w-12 shrink-0 items-center justify-center rounded-xl", tone)}>
        <Icon className="h-6 w-6" aria-hidden />
      </span>
      <div className="min-w-0 space-y-0.5">
        <p className="truncate text-2xl font-semibold leading-tight tabular-nums">{value}</p>
        <p className="truncate text-xs text-muted-foreground">{label}</p>
        <p className={cn("truncate text-[11px]", subTone ?? "text-muted-foreground")}>{sub}</p>
      </div>
    </Card>
  );
}

/**
 * Potential Members: guests of the selected sport who have booked 3 or more times and aren't
 * members yet. Reached from the Guest Insights pop-up, and not listed in the menu.
 */
export function PotentialMembersPage() {
  const { data: facility } = useFacility();
  const facilityId = facility?.id ?? null;

  // One sport at a time: the top bar's choice, else the facility's first.
  const activeSportId = useUiStore((s) => s.activeFacilitySportId);
  const { data: sportChoices } = useFacilitySportOptions(facilityId ?? undefined);
  const sport = sportChoices?.find((o) => o.facilitySportId === activeSportId) ?? sportChoices?.[0];
  const sportId = sport?.facilitySportId ?? "";

  const { guests, isError } = useGuestProfiles(facilityId, sportId);
  const potential = useMemo(() => (guests ? potentialMembers(guests) : undefined), [guests]);
  const stats = useMemo(() => (guests ? segmentStats(guests) : null), [guests]);

  const [filters, setFilters] = useState<PotentialFilters>(DEFAULT_FILTERS);
  const [showFilters, setShowFilters] = useState(true);
  const [sortDir, setSortDir] = useState<PotentialSortDir>("desc");
  const [page, setPage] = useState(1);
  const [perPage, setPerPage] = useState(PAGE_SIZES[0]!);
  const [selected, setSelected] = useState<Set<string>>(new Set());
  const [copiedKey, setCopiedKey] = useState<string | null>(null);
  const [bulkCopied, setBulkCopied] = useState(false);
  const [notice, setNotice] = useState<string | null>(null);
  const [profileGuest, setProfileGuest] = useState<GuestPlayer | null>(null);

  const filtered = useMemo(
    () => (potential ? sortByBookings(filterPotential(potential, filters, new Date()), sortDir) : undefined),
    [potential, filters, sortDir],
  );
  const courtOptions = useMemo(
    () => [...new Set((potential ?? []).map((g) => g.preferredCourt))].sort((a, b) => a.localeCompare(b, undefined, { numeric: true })),
    [potential],
  );

  // A new sport or new filters start again from page one and forget guests that are no longer listed.
  useEffect(() => {
    setPage(1);
  }, [filters, sortDir, perPage, sportId]);
  useEffect(() => {
    setFilters((f) => (f.court ? { ...f, court: "" } : f));
    setSelected(new Set());
  }, [sportId]);
  useEffect(() => {
    if (!filtered) return;
    setSelected((prev) => {
      const visible = new Set(filtered.map((g) => g.key));
      const next = new Set([...prev].filter((k) => visible.has(k)));
      return next.size === prev.size ? prev : next;
    });
  }, [filtered]);

  const total = filtered?.length ?? 0;
  const pages = Math.max(1, Math.ceil(total / perPage));
  const safePage = Math.min(page, pages);
  const pageRows = filtered?.slice((safePage - 1) * perPage, safePage * perPage);
  const from = total === 0 ? 0 : (safePage - 1) * perPage + 1;
  const to = Math.min(safePage * perPage, total);

  const joinLink = () => `${window.location.origin}/join/${facilityId}`;

  function flash(setter: (v: boolean) => void) {
    setter(true);
    setTimeout(() => setter(false), 2000);
  }

  async function invite(g: GuestProfile) {
    await copyText(joinLink());
    setCopiedKey(g.key);
    setTimeout(() => setCopiedKey((k) => (k === g.key ? null : k)), 2000);
  }

  async function copyPhone(g: GuestProfile) {
    await copyText(displayPhone(g.phone));
    setNotice(`Copied ${g.name}'s number.`);
    setTimeout(() => setNotice(null), 2500);
  }

  /** The link, then the selected guests' numbers one to a line, ready to paste into a message. */
  async function copySelected() {
    const chosen = (filtered ?? []).filter((g) => selected.has(g.key));
    await copyText([`Membership invitation link: ${joinLink()}`, "", ...chosen.map((g) => displayPhone(g.phone))].join("\n"));
    flash(setBulkCopied);
  }

  async function viewProfile(g: GuestProfile) {
    if (!facilityId) return;
    try {
      const matches = await getGuestService().searchGuests(facilityId, g.name);
      const found = matches.find((m) => phoneKey(m.phone) === g.key) ?? null;
      if (found) setProfileGuest(found);
      else {
        setNotice(`Couldn't find a saved profile for ${g.name}.`);
        setTimeout(() => setNotice(null), 3000);
      }
    } catch {
      setNotice("Couldn't open the guest profile. Please try again.");
      setTimeout(() => setNotice(null), 3000);
    }
  }

  return (
    <div className="space-y-6">
      <PageHero
        title="Potential Members"
        subtitle="Guests who frequently book and may be interested in a membership."
        tagline="Turn Guests into Members"
        taglineSub="Build a loyal community and increase recurring revenue."
      />

      <div className="grid gap-4 xl:grid-cols-[minmax(0,1fr)_300px]">
        <div className="min-w-0 space-y-4">
          {/* The four figures for the whole segment (not narrowed by the filters). */}
          {stats ? (
            <div className="grid grid-cols-2 gap-3 xl:grid-cols-4">
              <StatCard
                icon={Users}
                tone="bg-success/15 text-success"
                value={String(stats.count)}
                label="Potential Members"
                sub="↑ Guests with 3+ bookings"
                subTone="text-success"
              />
              <StatCard
                icon={TrendingUp}
                tone="bg-success/15 text-success"
                value={formatCurrency(stats.monthlyRevenueMinor, "INR")}
                label="Potential Monthly Revenue"
                sub="If all convert to members"
              />
              <StatCard
                icon={Percent}
                tone="bg-destructive/15 text-destructive"
                value={`${Math.round(stats.conversionPercent)}%`}
                label="Conversion Opportunity"
                sub="Of frequent guests"
              />
              <StatCard
                icon={Star}
                tone="bg-warning/15 text-warning"
                value={stats.avgBookings.toFixed(1)}
                label="Avg. Bookings per Guest"
                sub="Among this segment"
                subTone="text-success"
              />
            </div>
          ) : (
            <div className="grid grid-cols-2 gap-3 xl:grid-cols-4">
              {Array.from({ length: 4 }).map((_, i) => (
                <Skeleton key={i} className="h-[88px] rounded-xl" />
              ))}
            </div>
          )}

          <Card className="overflow-visible p-0">
            <div className="flex flex-wrap items-center gap-x-3 gap-y-3 p-4">
              <div className="relative min-w-[220px] flex-1">
                <Search className="pointer-events-none absolute left-3.5 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" aria-hidden />
                <input
                  type="text"
                  aria-label="Search guests"
                  placeholder="Search by name or phone…"
                  value={filters.search}
                  onChange={(e) => setFilters({ ...filters, search: e.target.value })}
                  className={cn(CONTROL, "w-full pl-10 pr-9 placeholder:text-muted-foreground")}
                />
                {filters.search && (
                  <button
                    type="button"
                    aria-label="Clear search"
                    onClick={() => setFilters({ ...filters, search: "" })}
                    className="absolute right-2.5 top-1/2 -translate-y-1/2 rounded p-1 text-muted-foreground hover:text-foreground"
                  >
                    <X className="h-3.5 w-3.5" />
                  </button>
                )}
              </div>
              <SelectField
                wrapperClassName="w-[200px]"
                ariaLabel="Court preference"
                value={filters.court}
                onValueChange={(v) => setFilters({ ...filters, court: v })}
                options={[{ value: "", label: "All Court Preferences" }, ...courtOptions.map((c) => ({ value: c, label: c }))]}
                className={CONTROL}
              />
              <SelectField
                wrapperClassName="w-[160px]"
                ariaLabel="Booking count"
                value={String(filters.minBookings)}
                onValueChange={(v) => setFilters({ ...filters, minBookings: Number(v) })}
                options={[{ value: "", label: "Booking Count" }, ...BOOKING_COUNT_OPTIONS].filter((o) => o.value !== "")}
                className={CONTROL}
              />
              <button
                type="button"
                aria-pressed={showFilters}
                onClick={() => setShowFilters((v) => !v)}
                className={cn(CONTROL, "flex items-center gap-2 px-4 font-medium hover:bg-accent", showFilters && "bg-accent/50")}
              >
                <SlidersHorizontal className="h-4 w-4" aria-hidden />
                More Filters
              </button>
            </div>

            {isError ? (
              <p className="border-t border-border px-4 py-12 text-center text-sm text-muted-foreground">
                Unable to load guests. Please try again.
              </p>
            ) : (
              <div className="border-t border-border">
                <PotentialMembersTable
                  rows={pageRows}
                  selected={selected}
                  onToggle={(key) =>
                    setSelected((prev) => {
                      const next = new Set(prev);
                      if (next.has(key)) next.delete(key);
                      else next.add(key);
                      return next;
                    })
                  }
                  onTogglePage={(checked) =>
                    setSelected((prev) => {
                      const next = new Set(prev);
                      for (const g of pageRows ?? []) {
                        if (checked) next.add(g.key);
                        else next.delete(g.key);
                      }
                      return next;
                    })
                  }
                  sortDir={sortDir}
                  onSortBookings={() => setSortDir((d) => (d === "desc" ? "asc" : "desc"))}
                  sportIcon={sport?.icon ?? "🏅"}
                  sportName={sport?.name ?? "—"}
                  copiedKey={copiedKey}
                  onInvite={invite}
                  onViewProfile={viewProfile}
                  onCopyPhone={copyPhone}
                />
                <div className="flex flex-wrap items-center justify-between gap-3 border-t border-border px-4 py-3">
                  <p className="text-xs text-muted-foreground">
                    {total === 0 ? "No guests" : `Showing ${from}–${to} of ${total} guest${total === 1 ? "" : "s"}`}
                  </p>
                  <PaginationControls
                    page={safePage}
                    pages={pages}
                    perPage={perPage}
                    pageSizes={PAGE_SIZES}
                    onPage={setPage}
                    onPerPage={setPerPage}
                  />
                </div>
              </div>
            )}
          </Card>

          {notice && (
            <p role="status" className="text-sm text-muted-foreground">
              {notice}
            </p>
          )}
        </div>

        <PotentialMembersPanels
          filters={filters}
          onFiltersChange={setFilters}
          showFilters={showFilters}
          selectedCount={selected.size}
          onSelectGuests={() => setSelected(new Set((filtered ?? []).map((g) => g.key)))}
          onCopySelected={copySelected}
          onClearSelection={() => setSelected(new Set())}
          bulkCopied={bulkCopied}
        />
      </div>

      {facilityId && (
        <GuestProfileDialog
          open={profileGuest !== null}
          onOpenChange={(open) => !open && setProfileGuest(null)}
          facilityId={facilityId}
          guest={profileGuest}
          onChanged={setProfileGuest}
        />
      )}
    </div>
  );
}
