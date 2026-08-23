"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { getFacilityService } from "@/services/facility";
import { useDashboardSummary } from "@/features/dashboard/hooks/use-dashboard-summary";
import { KpiCard } from "@/features/dashboard/components/kpi-card";
import { UnavailableCard } from "@/features/dashboard/components/unavailable-card";
import type { DateRangePreset } from "@/features/dashboard/types";
import { formatCurrencyINR } from "@/lib/utils";

const DATE_PRESETS: { value: DateRangePreset; label: string }[] = [
  { value: "TODAY", label: "Today" },
  { value: "YESTERDAY", label: "Yesterday" },
  { value: "THIS_WEEK", label: "This Week" },
  { value: "THIS_MONTH", label: "This Month" },
];

function greeting(): string {
  const hour = new Date().getHours();
  if (hour < 12) return "Good Morning";
  if (hour < 17) return "Good Afternoon";
  return "Good Evening";
}

export function OwnerDashboard({ ownerFirstName }: { ownerFirstName: string | null }) {
  const router = useRouter();
  const [facilityId, setFacilityId] = useState<string | null>(null);
  const [facilityLoadState, setFacilityLoadState] = useState<"loading" | "ready" | "none">("loading");
  const [selectedSportId, setSelectedSportId] = useState<string | null>(null);
  const [preset, setPreset] = useState<DateRangePreset>("TODAY");

  useEffect(() => {
    let cancelled = false;
    (async () => {
      const facility = await getFacilityService().getFacility();
      if (cancelled) return;
      if (!facility) {
        setFacilityLoadState("none");
        return;
      }
      setFacilityId(facility.id);
      setFacilityLoadState("ready");
    })();
    return () => {
      cancelled = true;
    };
  }, []);

  const { data: summary, isLoading, isError, refetch } = useDashboardSummary(facilityId, {
    facilitySportId: selectedSportId,
    preset,
  });

  if (facilityLoadState === "loading" || isLoading) {
    return (
      <div className="space-y-6">
        <Skeleton className="h-20 w-full rounded-xl" />
        <div className="grid grid-cols-2 gap-4 lg:grid-cols-4">
          {Array.from({ length: 4 }).map((_, i) => (
            <Skeleton key={i} className="h-24 rounded-xl" />
          ))}
        </div>
        <Skeleton className="h-64 w-full rounded-xl" />
      </div>
    );
  }

  if (facilityLoadState === "none") {
    return (
      <div className="space-y-4 text-center">
        <p className="text-sm text-muted-foreground">Complete your facility setup to see your dashboard.</p>
        <Button type="button" onClick={() => router.push("/onboarding/facility")}>
          Continue Setup
        </Button>
      </div>
    );
  }

  if (isError || !summary) {
    return (
      <div className="space-y-4 text-center">
        <p className="text-sm text-muted-foreground">Unable to load dashboard data.</p>
        <Button type="button" variant="outline" onClick={() => refetch()}>
          Try Again
        </Button>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
        <div>
          <h1 className="text-xl font-semibold">
            {ownerFirstName ? `${greeting()}, ${ownerFirstName} 👋` : greeting()}
          </h1>
          <p className="text-sm text-muted-foreground">
            {summary.facility.name}
            {summary.facility.city ? ` · ${summary.facility.city}` : ""}
          </p>
        </div>
        <div className="flex gap-2">
          <select
            aria-label="Sport"
            value={selectedSportId ?? ""}
            onChange={(e) => setSelectedSportId(e.target.value || null)}
            className="h-11 min-w-[9rem] rounded-md border border-input bg-secondary/60 px-3 text-sm"
          >
            <option value="">All Sports</option>
            {summary.sports.map((sport) => (
              <option key={sport.facilitySportId} value={sport.facilitySportId}>
                {sport.sportIcon} {sport.sportName}
              </option>
            ))}
          </select>
          <select
            aria-label="Date range"
            value={preset}
            onChange={(e) => setPreset(e.target.value as DateRangePreset)}
            className="h-11 min-w-[8rem] rounded-md border border-input bg-secondary/60 px-3 text-sm"
          >
            {DATE_PRESETS.map((option) => (
              <option key={option.value} value={option.value}>
                {option.label}
              </option>
            ))}
          </select>
        </div>
      </div>

      {/* KPIs */}
      <div className="grid grid-cols-2 gap-4 lg:grid-cols-4">
        <KpiCard label="Revenue" kpi={summary.kpis.revenueInr} format={formatCurrencyINR} />
        <KpiCard label="Bookings" kpi={summary.kpis.bookings} format={(v) => String(v)} />
        <KpiCard label="Utilization" kpi={summary.kpis.utilizationPercent} format={(v) => `${v}%`} />
        <KpiCard label="Active Members" kpi={summary.kpis.activeMembers} format={(v) => String(v)} />
      </div>

      {/* Revenue by Sport | Utilization */}
      <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
        <UnavailableCard
          title="Revenue by Sport"
          message="Payments aren't linked to a sport yet — this will populate once the Bookings module connects payments to a court."
        />
        <Card className="space-y-3 p-4 sm:p-5">
          <div className="flex items-center justify-between">
            <h3 className="text-sm font-semibold">Court / Turf Utilization</h3>
            <span className="text-sm font-medium text-foreground">{summary.utilization.overallPercent}%</span>
          </div>
          {summary.utilization.bySport.length === 0 ? (
            <p className="text-sm text-muted-foreground">No sports configured yet.</p>
          ) : (
            <div className="space-y-2">
              {summary.utilization.bySport.map((sport) => (
                <div key={sport.facilitySportId} className="flex items-center justify-between text-sm">
                  <span className="text-muted-foreground">{sport.sportName}</span>
                  <span className="font-medium text-foreground">{sport.utilizationPercent}%</span>
                </div>
              ))}
            </div>
          )}
        </Card>
      </div>

      {/* Today's Schedule | Live Activity */}
      <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
        <Card className="space-y-3 p-4 sm:p-5">
          <div className="flex items-center justify-between">
            <h3 className="text-sm font-semibold">Today&apos;s Schedule</h3>
          </div>
          {summary.schedule.length === 0 ? (
            <p className="text-sm text-muted-foreground">No operating hours configured for today.</p>
          ) : (
            <div className="max-h-72 space-y-2 overflow-y-auto">
              {summary.schedule.map((entry, index) => (
                <div key={index} className="flex items-center justify-between text-sm">
                  <span className="text-muted-foreground">
                    {entry.time} · {entry.sportName} — {entry.playingAreaName}
                  </span>
                  <span className={entry.status === "BOOKED" ? "font-medium text-foreground" : "text-muted-foreground"}>
                    {entry.status === "BOOKED" ? "Booked" : "Available"}
                  </span>
                </div>
              ))}
            </div>
          )}
        </Card>
        <UnavailableCard
          title="Live Activity"
          message="Real-time activity (bookings, check-ins, payments) will appear here once the Bookings module is live."
        />
      </div>

      {/* Memberships | Guests | Payments | Expenses */}
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <Card className="space-y-2 p-4">
          <h3 className="text-sm font-semibold">Memberships</h3>
          <p className="text-lg font-semibold">{summary.memberships.active}</p>
          <p className="text-xs text-muted-foreground">
            {summary.memberships.expiringSoon} expiring soon · {summary.memberships.newThisMonth} new this month
          </p>
          <Button type="button" variant="ghost" size="sm" className="h-8 px-0 text-xs" onClick={() => router.push("/members")}>
            View Members →
          </Button>
        </Card>
        <UnavailableCard title="Guest Players" message="Guest booking isn't tracked yet." />
        <Card className="space-y-2 p-4">
          <h3 className="text-sm font-semibold">Payments</h3>
          <p className="text-lg font-semibold">{formatCurrencyINR(summary.payments.collectedInr)}</p>
          <p className="text-xs text-muted-foreground">
            {formatCurrencyINR(summary.payments.pendingInr)} pending · {formatCurrencyINR(summary.payments.refundsInr)} refunded
          </p>
        </Card>
        <UnavailableCard title="Expenses" message="Expense tracking isn't available yet." />
      </div>

      {/* Business Position | Attention Required */}
      <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
        <Card className="space-y-2 p-4 sm:p-5">
          <h3 className="text-sm font-semibold">Business Position</h3>
          <div className="flex items-center justify-between text-sm">
            <span className="text-muted-foreground">Revenue</span>
            <span className="font-medium text-foreground">{formatCurrencyINR(summary.businessPosition.revenueInr)}</span>
          </div>
          <p className="text-xs text-muted-foreground">
            Net operating position isn&apos;t shown yet — expense tracking isn&apos;t available.
          </p>
        </Card>
        <Card className="space-y-3 p-4 sm:p-5">
          <h3 className="text-sm font-semibold">⚠ Attention Required</h3>
          {summary.attentionItems.length === 0 ? (
            <p className="text-sm text-success">✓ Everything looks good. No immediate attention required.</p>
          ) : (
            <ul className="space-y-2">
              {summary.attentionItems.map((item) => (
                <li key={item.id} className="flex items-center justify-between gap-3 text-sm">
                  <span className="text-muted-foreground">{item.message}</span>
                  {item.actionHref && item.actionLabel && (
                    <Button type="button" variant="outline" size="sm" className="h-8 shrink-0 px-2 text-xs" onClick={() => router.push(item.actionHref!)}>
                      {item.actionLabel}
                    </Button>
                  )}
                </li>
              ))}
            </ul>
          )}
        </Card>
      </div>

      <UnavailableCard title="Upcoming" message="Tournaments and coaching batches aren't available yet." />

      {/* Quick Actions */}
      <Card className="space-y-3 p-4 sm:p-5">
        <h3 className="text-sm font-semibold">Quick Actions</h3>
        <div className="flex flex-wrap gap-2">
          <Button type="button" variant="outline" size="sm" className="h-11" onClick={() => router.push("/members")}>
            + Add Member
          </Button>
        </div>
      </Card>
    </div>
  );
}