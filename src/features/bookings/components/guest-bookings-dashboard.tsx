"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { Plus } from "lucide-react";
import { Card } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { PageHero } from "@/components/shared/page-hero";
import { usePermissionContext } from "@/features/auth/context/permission-provider";
import { GuestBookingStatsRow } from "@/features/bookings/components/guest-booking-stats-row";
import { fetchAllGuestBookings, useGuestBookingStats, useGuestHistory } from "@/features/bookings/hooks/use-guest-booking-stats";
import { useUiStore } from "@/stores/ui-store";
import { GuestBookingsFilterCard, type GuestTab } from "@/features/bookings/components/guest-bookings-filter-card";
import { useFacilitySportOptions } from "@/features/facility/hooks/use-facility-sport-options";
import { GuestBookingsHighlights } from "@/features/bookings/components/guest-bookings-highlights";
import { GuestInsightsDialog } from "@/features/bookings/components/guest-insights-dialog";
import { GuestBookingsTable } from "@/features/bookings/components/guest-bookings-table";
import { PaginationControls } from "@/features/bookings/components/pagination-controls";
import { sortGuestRows, type GuestSortDir, type GuestSortKey } from "@/features/bookings/guest-booking-table";
import { ShareBookingLink } from "@/features/public-booking/components/share-booking-link";
import { useFacility } from "@/features/facility/hooks/use-facility";
import { getSportsService } from "@/services/sports";
import { getPlayingAreasService } from "@/services/playing-areas";
import { getBookingService } from "@/services/bookings";
import type {
  BookingStatus,
  GuestBookingRow,
} from "@/features/bookings/types";
import type { FacilitySport } from "@/features/sports-setup/types";
import type { PlayingArea } from "@/features/courts-setup/types";

const PAGE_SIZES = [10, 25, 50];
function iso(d: Date): string {
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
}
function fmtDate(d: string): string {
  return new Date(d).toLocaleDateString("en-IN", { day: "2-digit", month: "short", year: "numeric" });
}
function fmtTime(d: string): string {
  return new Date(d).toLocaleTimeString("en-IN", { hour: "numeric", minute: "2-digit", hour12: true });
}
export function GuestBookingsDashboard() {
  const router = useRouter();
  const { data: facility } = useFacility();
  const facilityId = facility?.id ?? null;
  const facilityName = facility?.name ?? "";
  const [currency, setCurrency] = useState("INR");

  const [rows, setRows] = useState<GuestBookingRow[] | null>(null);
  const [totalCount, setTotalCount] = useState(0);

  const [search, setSearch] = useState("");
  const [debounced, setDebounced] = useState("");
  const [courtId, setCourtId] = useState("");
  const [status, setStatus] = useState<BookingStatus | "">("");
  const [tab, setTab] = useState<GuestTab>("all");
  const [from, setFrom] = useState(() => {
    const d = new Date();
    d.setDate(d.getDate() - 29);
    return iso(d);
  });
  const [to, setTo] = useState(() => iso(new Date()));
  const [page, setPage] = useState(1);
  const [perPage, setPerPage] = useState(PAGE_SIZES[0]!);
  // The clicked column sorts the rows on screen; null keeps the order the list came in.
  const [sortKey, setSortKey] = useState<GuestSortKey | null>(null);
  const [sortDir, setSortDir] = useState<GuestSortDir>("asc");
  const [facilitySports, setFacilitySports] = useState<FacilitySport[]>([]);
  const [areas, setAreas] = useState<PlayingArea[]>([]);
  const [sportsLoaded, setSportsLoaded] = useState(false);

  // One sport at a time: whatever the top bar picked, else the facility's first sport. Every
  // number, chart and row on this page is for that sport only.
  const activeSportId = useUiStore((st) => st.activeFacilitySportId);
  const facilitySport = facilitySports.find((fs) => fs.id === activeSportId) ?? facilitySports[0];
  const sportId = facilitySport?.id ?? "";
  const perms = usePermissionContext();
  // Without a permission context (e.g. mid-onboarding) the page's own role gate already applied.
  const canBook = !perms || perms.can("GUEST_BOOKINGS_CREATE") || perms.can("BOOKINGS_CREATE");
  const statsQuery = useGuestBookingStats(facilityId, sportId, from, to);
  // The sport dropdown here is the top bar's choice, shown in a second place — changing either changes both.
  const setActiveSportId = useUiStore((st) => st.setActiveFacilitySportId);
  const { data: sportChoices } = useFacilitySportOptions(facilityId ?? undefined);
  const sportOptions = (sportChoices ?? []).map((o) => ({ value: o.facilitySportId, label: o.name }));
  // Every guest booking this sport has ever had: the Recent Guests and Guest Insights cards read from it.
  const historyQuery = useGuestHistory(facilityId, sportId);
  const [insightsOpen, setInsightsOpen] = useState(false);
  useEffect(() => {
    if (!facilityId) return;
    let cancelled = false;
    (async () => {
      const [fs, pa] = await Promise.all([
        getSportsService().getFacilitySports(facilityId),
        getPlayingAreasService().getPlayingAreas(facilityId),
      ]);
      if (cancelled) return;
      setFacilitySports(fs.filter((x) => x.enabled));
      setAreas(pa.filter((a) => !a.archived));
      setSportsLoaded(true);
    })();
    return () => {
      cancelled = true;
    };
  }, [facilityId]);

  useEffect(() => {
    const t = setTimeout(() => setDebounced(search), 300);
    return () => clearTimeout(t);
  }, [search]);

  useEffect(() => {
    setPage(1);
  }, [debounced, sportId, courtId, status, tab, from, to, perPage]);

  useEffect(() => {
    setCourtId("");
  }, [sportId]);

  function changeTab(next: GuestTab) {
    setTab(next);
    setStatus(next === "completed" ? "completed" : next === "cancelled" ? "cancelled" : "");
  }
  function changeStatus(next: BookingStatus | "") {
    setStatus(next);
    setTab(next === "completed" ? "completed" : next === "cancelled" ? "cancelled" : "all");
  }

  const reload = useCallback(async () => {
    // Wait until we know which sport, or the first load would briefly list every sport.
    if (!facilityId || !sportsLoaded || !sportId) return;
    setRows(null);
    if (tab === "upcoming") {
      const today = new Date();
      const horizon = new Date(today);
      horizon.setDate(horizon.getDate() + 365);
      const all = await fetchAllGuestBookings(facilityId, sportId, iso(today), iso(horizon), {
        search: debounced || undefined,
        courtId: courtId || undefined,
      });
      const now = new Date();
      const coming = all
        .filter((r) => (r.status === "confirmed" || r.status === "pending") && new Date(r.endTime) > now)
        .sort((a, b) => a.startTime.localeCompare(b.startTime));
      setTotalCount(coming.length);
      setRows(coming.slice((page - 1) * perPage, page * perPage));
      if (coming[0]?.currency) setCurrency(coming[0].currency);
      return;
    }
    const svc = getBookingService();
    const [list] = await Promise.all([
      svc.listGuestBookings(facilityId, {
        search: debounced || undefined,
        facilitySportId: sportId,
        courtId: courtId || undefined,
        status: status || undefined,
        from,
        to,
        page,
        perPage,
      }),
    ]);
    setRows(list.rows);
    setTotalCount(list.totalCount);
    if (list.rows[0]?.currency) setCurrency(list.rows[0].currency);
  }, [facilityId, sportsLoaded, debounced, sportId, courtId, status, tab, from, to, page, perPage]);

  useEffect(() => {
    reload();
  }, [reload]);

  const totalPages = Math.max(1, Math.ceil(totalCount / perPage));
  const pageRows = useMemo(() => (rows && sortKey ? sortGuestRows(rows, sortKey, sortDir) : rows), [rows, sortKey, sortDir]);
  const sportIcon = sportChoices?.find((o) => o.facilitySportId === sportId)?.icon ?? "🏅";

  function sortBy(key: GuestSortKey) {
    if (sortKey === key) setSortDir((d) => (d === "asc" ? "desc" : "asc"));
    else {
      setSortKey(key);
      setSortDir("asc");
    }
  }
  const courtsForSport = useMemo(
    () => (sportId ? areas.filter((a) => a.facilitySportId === sportId) : areas),
    [areas, sportId],
  );


  function exportCsv() {
    if (!rows) return;
    const header = ["Booking ID", "Guest", "Phone", "Sport", "Court", "Date", "Start", "End", "Players", "Amount", "Payment", "Method", "Status"];
    const lines = rows.map((r) =>
      [
        r.code,
        r.guestName,
        r.guestPhone ?? "",
        r.sportName ?? "",
        r.courtName,
        fmtDate(r.startTime),
        fmtTime(r.startTime),
        fmtTime(r.endTime),
        r.partySize,
        r.amountMinor == null ? "" : (r.amountMinor / 100).toString(),
        r.paymentStatus,
        r.paymentMethod ?? "",
        r.status,
      ]
        .map((v) => `"${String(v).replace(/"/g, '""')}"`)
        .join(","),
    );
    const blob = new Blob([[header.join(","), ...lines].join("\n")], { type: "text/csv" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = `guest-bookings-${from}_${to}.csv`;
    a.click();
    URL.revokeObjectURL(url);
  }

  if (!facilityId) return <Skeleton className="h-96 w-full rounded-xl" />;

  return (
    <div className="space-y-6">
      <PageHero
        title="Guest Booking"
        subtitle="Create and manage bookings for walk-ins, friends or non-members."
        tagline="More Players. Happier Games."
        taglineSub="Make it easy for everyone to play."
        actions={
          <>
            <ShareBookingLink facilityId={facilityId} triggerClassName="h-[42px] rounded-[10px] px-4 text-sm shadow-sm" />
            {canBook && (
              <button
                type="button"
                onClick={() => router.push("/guest-bookings/new")}
                className="flex h-[42px] items-center justify-center gap-2 rounded-[10px] bg-[#0B7A55] px-5 text-sm font-semibold text-white shadow-sm transition-opacity hover:opacity-90 dark:bg-primary dark:text-primary-foreground"
              >
                <Plus className="h-4 w-4" aria-hidden />
                New Guest Booking
              </button>
            )}
          </>
        }
      />

      {statsQuery.data ? (
        <GuestBookingStatsRow
          stats={statsQuery.data}
          upcoming={statsQuery.data.upcoming}
          currency={currency}
          onViewToday={() => {
            const t = iso(new Date());
            setFrom(t);
            setTo(t);
          }}
        />
      ) : (
        <div className="grid grid-cols-2 gap-3 lg:grid-cols-3 xl:grid-cols-5">
          {Array.from({ length: 5 }).map((_, i) => (
            <Skeleton key={i} className="h-[88px] rounded-xl" />
          ))}
        </div>
      )}
      <div className="space-y-4">
        <div className="min-w-0 space-y-4">
          <GuestBookingsFilterCard
            tab={tab}
            onTabChange={changeTab}
            search={search}
            onSearchChange={setSearch}
            sportOptions={sportOptions}
            sportId={sportId}
            onSportChange={setActiveSportId}
            courts={courtsForSport.map((a) => ({ id: a.id, name: a.name }))}
            courtId={courtId}
            onCourtChange={setCourtId}
            status={status}
            onStatusChange={changeStatus}
            from={from}
            to={to}
            onRangeChange={(f, t) => {
              setFrom(f);
              setTo(t);
            }}
            rangeDisabled={tab === "upcoming"}
            onExport={exportCsv}
            exportDisabled={!rows || rows.length === 0}
          />
          {/* Table */}
          <Card className="stat-enter overflow-hidden p-0" style={{ "--stat-delay": "420ms" } as React.CSSProperties}>
            <GuestBookingsTable
              rows={pageRows}
              sortKey={sortKey}
              sortDir={sortDir}
              onSort={sortBy}
              sportIcon={sportIcon}
              facilityId={facilityId}
              facilityName={facilityName}
              onChanged={() => {
                void reload();
                void statsQuery.refetch();
                void historyQuery.refetch();
              }}
            />
            <div className="flex flex-wrap items-center justify-between gap-2 border-t border-border px-4 py-3 text-xs text-muted-foreground">
              <span>
                {totalCount === 0
                  ? "No bookings"
                  : `Showing ${(page - 1) * perPage + 1} to ${Math.min(page * perPage, totalCount)} of ${totalCount} bookings`}
              </span>
              <PaginationControls
                page={page}
                pages={totalPages}
                perPage={perPage}
                pageSizes={PAGE_SIZES}
                onPage={setPage}
                onPerPage={setPerPage}
              />
            </div>
          </Card>
        </div>

        <GuestBookingsHighlights
          history={historyQuery.data}
          canBook={canBook}
          onNewBooking={() => router.push("/guest-bookings/new")}
          onViewAllGuests={() => router.push("/guests")}
          onViewInsights={() => setInsightsOpen(true)}
        />

        <GuestInsightsDialog
          open={insightsOpen}
          onOpenChange={setInsightsOpen}
          rows={historyQuery.data}
          currency={currency}
          onViewPotentialMembers={() => {
            setInsightsOpen(false);
            router.push("/guest-bookings/potential-members");
          }}
        />
      </div>
    </div>
  );
}
