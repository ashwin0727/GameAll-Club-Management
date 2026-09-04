"use client";

import { useCallback, useEffect, useState } from "react";
import Link from "next/link";
import { ArrowRight } from "lucide-react";
import { Card } from "@/components/ui/card";
import { formatCurrency } from "@/features/pricing/money";
import { getReportsService } from "@/services/reports";
import { useAnalyticsFilter } from "./use-analytics-filter";
import { AnalyticsFilterBar } from "./analytics-filter-bar";
import { AnalyticsFilterSheet } from "./analytics-filter-sheet";
import { ReportShell, type ReportStatus } from "./report-shell";
import { KpiStrip, type KpiStripItem } from "./kpi-strip";
import { ReportBarList } from "./report-bar-list";
import { DataTable } from "./data-table";
import { filterToSearchParams } from "../url-state";
import { toCsv } from "../aggregation";
import type {
  GuestReleaseAnalytics,
  MembershipAnalytics,
  MembershipSessionAnalytics,
  MembershipTypeRow,
} from "../types";

const INR = "INR";

function titleCase(s: string): string {
  return s.charAt(0) + s.slice(1).toLowerCase();
}

export function MembershipReport() {
  const { filter, setFilter, ready } = useAnalyticsFilter();

  const [status, setStatus] = useState<ReportStatus>("loading");
  const [analytics, setAnalytics] = useState<MembershipAnalytics | null>(null);
  const [byType, setByType] = useState<MembershipTypeRow[]>([]);
  const [session, setSession] = useState<MembershipSessionAnalytics | null>(null);
  const [guestRelease, setGuestRelease] = useState<GuestReleaseAnalytics | null>(null);

  const load = useCallback(async () => {
    if (!filter) return;
    setStatus("loading");
    const svc = getReportsService();
    try {
      const [a, t, s, g] = await Promise.all([
        svc.getMembershipAnalytics(filter),
        svc.getMembershipsByType(filter),
        svc.getMembershipSessionAnalytics(filter),
        svc.getGuestReleaseAnalytics(filter),
      ]);
      setAnalytics(a);
      setByType(t);
      setSession(s);
      setGuestRelease(g);
      setStatus(
        a.activeMembers === 0 && a.newMemberships === 0 && s.sessionCount === 0 ? "empty" : "ready",
      );
    } catch {
      setStatus("error");
    }
  }, [filter]);

  useEffect(() => {
    if (ready) void load();
  }, [ready, load]);

  const filterBar =
    ready && filter ? (
      <>
        <div className="hidden md:block">
          <AnalyticsFilterBar filter={filter} onChange={setFilter} />
        </div>
        <div className="md:hidden">
          <AnalyticsFilterSheet filter={filter} onChange={setFilter} />
        </div>
      </>
    ) : null;

  const sessionUtilPct =
    session && session.totalCapacity > 0
      ? Math.round(((session.memberAllocations + session.guestBooked) / session.totalCapacity) * 100)
      : 0;

  const kpis: KpiStripItem[] =
    analytics && session
      ? [
          {
            key: "activeMembers",
            label: "Active Members",
            value: analytics.activeMembers.toLocaleString("en-IN"),
            accent: "#8B5CF6",
          },
          {
            key: "newMemberships",
            label: "New Memberships",
            value: analytics.newMemberships.toLocaleString("en-IN"),
            accent: "#00F08A",
          },
          {
            key: "expiringMemberships",
            label: "Expiring Soon",
            value: analytics.expiringSoon.toLocaleString("en-IN"),
            accent: "#FFB020",
          },
          {
            key: "membershipRevenue",
            label: "Membership Revenue",
            value: formatCurrency(analytics.membershipRevenueMinor, INR),
            accent: "#00D084",
          },
          {
            key: "membershipOutstanding",
            label: "Membership Outstanding",
            value: formatCurrency(analytics.outstandingMinor, INR),
            accent: "#FF4D67",
          },
          {
            key: "membershipSessionUtilization",
            label: "Session Utilization",
            value: `${sessionUtilPct}%`,
            accent: "#5B6CFF",
          },
        ]
      : [];

  const typeBars = byType.map((r) => ({
    label: r.planName === "—" ? titleCase(r.membershipType) : `${titleCase(r.membershipType)} · ${r.planName}`,
    value: r.count,
    color: "#8B5CF6",
    caption: `${r.count} · ${formatCurrency(r.revenueMinor, INR)}`,
  }));

  function handleExport() {
    if (!analytics || !session || !guestRelease || !filter) return;
    const rows: Array<Record<string, string | number>> = [
      { section: "Members", label: "Active", value: analytics.activeMembers },
      { section: "Members", label: "New", value: analytics.newMemberships },
      { section: "Members", label: "Expiring soon", value: analytics.expiringSoon },
      { section: "Payments", label: "Membership revenue", value: formatCurrency(analytics.membershipRevenueMinor, INR) },
      { section: "Payments", label: "Paid", value: analytics.paidCount },
      { section: "Payments", label: "Partially paid", value: analytics.partiallyPaidCount },
      { section: "Payments", label: "Pending", value: analytics.pendingCount },
      { section: "Payments", label: "Outstanding", value: formatCurrency(analytics.outstandingMinor, INR) },
      ...byType.map((r) => ({
        section: "By type",
        label: `${r.membershipType} ${r.planName}`,
        value: r.count,
      })),
      { section: "Sessions", label: "Total capacity", value: session.totalCapacity },
      { section: "Sessions", label: "Member allocations", value: session.memberAllocations },
      { section: "Sessions", label: "Guest released", value: session.guestReleased },
      { section: "Sessions", label: "Guest booked", value: session.guestBooked },
      { section: "Sessions", label: "Remaining released", value: session.remainingReleased },
      { section: "Sessions", label: "Unused capacity", value: session.unusedCapacity },
      { section: "Guest release", label: "Revenue", value: formatCurrency(guestRelease.revenueMinor, INR) },
    ];
    const blob = new Blob([toCsv(rows)], { type: "text/csv" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = `memberships-${filter.facilityId}-${filter.preset}.csv`;
    a.click();
    URL.revokeObjectURL(url);
  }

  return (
    <ReportShell
      title="Membership Report"
      description="Members, renewals, sessions and released capacity."
      status={status}
      onRetry={load}
      emptyMessage="No membership activity for this period."
      errorMessage="Unable to load the membership report. Please try again."
      filterBar={filterBar}
      onExportCsv={handleExport}
    >
      <div className="space-y-5">
        <KpiStrip items={kpis} />

        {analytics && (
          <div className="grid gap-4 lg:grid-cols-2">
            <Card className="p-4">
              <h2 className="mb-3 text-sm font-semibold">Membership Payments</h2>
              <DataTable
                caption="Membership payment completion"
                columns={[
                  { key: "status", label: "Status" },
                  { key: "count", label: "Count", align: "right" },
                ]}
                rows={[
                  { status: "Paid", count: analytics.paidCount },
                  { status: "Partially paid", count: analytics.partiallyPaidCount },
                  { status: "Pending", count: analytics.pendingCount },
                ]}
              />
              <p className="mt-3 text-xs text-muted-foreground">
                Outstanding: {formatCurrency(analytics.outstandingMinor, INR)} ·{" "}
                <Link href="/finance/pending-payments" className="text-primary hover:underline">
                  Collect
                </Link>
              </p>
            </Card>

            <Card className="p-4">
              <h2 className="mb-3 text-sm font-semibold">Membership Types</h2>
              {typeBars.length === 0 ? (
                <p className="text-sm text-muted-foreground">No new memberships in this period.</p>
              ) : (
                <>
                  <ReportBarList items={typeBars} />
                  <div className="mt-4">
                    <DataTable
                      caption="Memberships by type"
                      columns={[
                        { key: "type", label: "Type" },
                        { key: "plan", label: "Plan" },
                        { key: "count", label: "Count", align: "right" },
                        { key: "revenue", label: "Revenue", align: "right" },
                      ]}
                      rows={byType.map((r) => ({
                        type: titleCase(r.membershipType),
                        plan: r.planName,
                        count: r.count,
                        revenue: formatCurrency(r.revenueMinor, INR),
                      }))}
                    />
                  </div>
                </>
              )}
            </Card>
          </div>
        )}

        {session && (
          <Card className="p-4">
            <h2 className="mb-3 text-sm font-semibold">Membership Sessions</h2>
            <DataTable
              caption="Membership session capacity"
              columns={[
                { key: "metric", label: "Metric" },
                { key: "value", label: "Slots", align: "right" },
              ]}
              rows={[
                { metric: "Total capacity", value: session.totalCapacity },
                { metric: "Member allocations", value: session.memberAllocations },
                { metric: "Guest released", value: session.guestReleased },
                { metric: "Guest booked", value: session.guestBooked },
                { metric: "Remaining released", value: session.remainingReleased },
                { metric: "Unused capacity", value: session.unusedCapacity },
              ]}
            />
            <p className="mt-3 text-[11px] text-muted-foreground">
              Session usage is capacity, not revenue — member allocations are never counted as income.
            </p>
          </Card>
        )}

        {guestRelease && (
          <Card className="p-4">
            <div className="mb-3 flex items-center justify-between gap-3">
              <h2 className="text-sm font-semibold">Guest Release</h2>
              {filter && (
                <Link
                  href={`/reports/guest-bookings?${filterToSearchParams(filter).toString()}`}
                  className="inline-flex items-center gap-1 text-xs font-medium text-primary hover:underline"
                >
                  Guest booking detail <ArrowRight className="h-3.5 w-3.5" aria-hidden />
                </Link>
              )}
            </div>
            <DataTable
              caption="Guest release capacity"
              columns={[
                { key: "metric", label: "Metric" },
                { key: "value", label: "Value", align: "right" },
              ]}
              rows={[
                { metric: "Released", value: guestRelease.released },
                { metric: "Booked", value: guestRelease.booked },
                { metric: "Remaining", value: guestRelease.remaining },
                { metric: "Revenue", value: formatCurrency(guestRelease.revenueMinor, INR) },
              ]}
            />
          </Card>
        )}
      </div>
    </ReportShell>
  );
}
