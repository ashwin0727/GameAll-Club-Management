"use client";

import { useCallback, useEffect, useState } from "react";
import Link from "next/link";
import { ArrowRight, Banknote, Hourglass, UserRoundCheck, UserRoundX, UsersRound } from "lucide-react";
import { Card } from "@/components/ui/card";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { formatCurrency } from "@/features/pricing/money";
import { DayRangeFilter } from "@/features/finance/components/day-range-filter";
import { MembershipStatCard } from "@/features/memberships/components/membership-stat-card";
import { getReportsService } from "@/services/reports";
import { useReportRange } from "./use-report-range";
import { ReportShell, type ReportStatus } from "./report-shell";
import { DataTable } from "./data-table";
import { ReportBarList } from "./report-bar-list";
import { filterToSearchParams } from "../url-state";
import { toCsv } from "../aggregation";
import { formatDays, formatTiming, groupByCourt } from "../membership-timing";
import type { GuestReleaseAnalytics, MembershipAnalytics, MembershipBatchRow, MembershipMemberCounts, MembershipTypeRow } from "../types";

const INR = "INR";
const ALL_COURTS = "__all__";

function titleCase(s: string): string {
  return s.charAt(0) + s.slice(1).toLowerCase();
}

/** "Individual · Monthly", or just "Family" when the membership has no plan. */
function typeLabel(r: MembershipTypeRow): string {
  return r.planName === "—" ? titleCase(r.membershipType) : `${titleCase(r.membershipType)} · ${r.planName}`;
}

export function MembershipReport() {
  const { filter, range, setRange, ready } = useReportRange();
  const [dirty, setDirty] = useState(false);

  const [status, setStatus] = useState<ReportStatus>("loading");
  const [counts, setCounts] = useState<MembershipMemberCounts | null>(null);
  const [analytics, setAnalytics] = useState<MembershipAnalytics | null>(null);
  const [byType, setByType] = useState<MembershipTypeRow[]>([]);
  const [guestRelease, setGuestRelease] = useState<GuestReleaseAnalytics | null>(null);
  const [batches, setBatches] = useState<MembershipBatchRow[]>([]);
  // A court filter for the timing table only — the rest of the report is not affected by it.
  const [timingCourt, setTimingCourt] = useState<string>(ALL_COURTS);

  const load = useCallback(async () => {
    if (!filter) return;
    setStatus("loading");
    const svc = getReportsService();
    try {
      const [c, a, t, g, b] = await Promise.all([
        svc.getMembershipMemberCounts(filter.facilityId, range, filter.facilitySportIds ?? null),
        svc.getMembershipAnalytics(filter),
        svc.getMembershipsByType(filter),
        svc.getGuestReleaseAnalytics(filter),
        svc.getMembershipBatchBreakdown(filter.facilityId, range, filter.facilitySportIds ?? null),
      ]);
      setCounts(c);
      setAnalytics(a);
      setByType(t);
      setGuestRelease(g);
      // Only timings that have members: a court held for memberships but with nobody in it for these dates is not listed.
      setBatches(b.filter((row) => row.batchId === null || row.members > 0));
      setStatus(c.total === 0 && a.membershipRevenueMinor === 0 && a.newMemberships === 0 ? "empty" : "ready");
    } catch {
      setStatus("error");
    }
  }, [filter, range]);

  useEffect(() => {
    if (ready) void load();
  }, [ready, load]);

  const groups = groupByCourt(batches);
  const courts = groups.flatMap((g) => g.courts.map((c) => ({ ...c, sportName: g.sportName })));
  const MEMBERS = "#8B5CF6";
  const plural = (n: number, one: string, many: string) => `${n.toLocaleString("en-IN")} ${n === 1 ? one : many}`;
  const sportBars = groups.map((g) => ({ label: g.sportName, value: g.members, color: MEMBERS, caption: plural(g.members, "member", "members") }));
  const sportRows = groups.map((g) => ({ sport: g.sportName, courts: g.courts.length, members: g.members }));
  const courtBars = courts.map((c) => ({ label: c.courtName, value: c.members, color: MEMBERS, caption: plural(c.members, "member", "members") }));
  const courtRows = courts.map((c) => ({ court: c.courtName, sport: c.sportName, members: c.members }));
  // The timing table can be narrowed to one court / turf. A court that is no longer in the data (new dates) means all courts.
  const courtKey = (sport: string, court: string) => `${sport}|${court}`;
  const courtOptions = courts.map((c) => ({ key: courtKey(c.sportName, c.courtName), label: courts.filter((x) => x.courtName === c.courtName).length > 1 ? `${c.courtName} · ${c.sportName}` : c.courtName }));
  const activeCourt = courtOptions.some((o) => o.key === timingCourt) ? timingCourt : ALL_COURTS;
  const timingRows = courts
    .filter((c) => activeCourt === ALL_COURTS || courtKey(c.sportName, c.courtName) === activeCourt)
    .flatMap((c) =>
      c.timings.map((t) => ({
        timing: formatTiming(t.startTime, t.endTime),
        days: formatDays(t.daysOfWeek),
        court: c.courtName,
        sport: c.sportName,
        members: t.members,
        active: t.activeMembers,
      })),
    );
  const unassigned = batches.find((b) => b.batchId === null && b.members > 0) ?? null;

  // Just the dates: the facility is the one facility, and the sports come from the top bar.
  const filterBar = ready ? <DayRangeFilter value={range} onApply={setRange} onDirtyChange={setDirty} /> : null;

  function handleExport() {
    if (!counts || !analytics || !guestRelease) return;
    const rows: Array<Record<string, string | number>> = [
      { section: "Period", label: "From", value: range.from },
      { section: "Period", label: "To", value: range.to },
      { section: "Members", label: "Total Members (registered or running in the dates)", value: counts.total },
      { section: "Members", label: `Active Members (not ended or cancelled by ${counts.asOf})`, value: counts.active },
      { section: "Members", label: "Inactive Members (ended or cancelled by then)", value: counts.inactive },
      { section: "Payments", label: "Membership Revenue (INR)", value: (analytics.membershipRevenueMinor / 100).toFixed(2) },
      { section: "Payments", label: "Membership Outstanding (INR)", value: (analytics.outstandingMinor / 100).toFixed(2) },
      { section: "Payments", label: "Paid", value: analytics.paidCount },
      { section: "Payments", label: "Partially Paid", value: analytics.partiallyPaidCount },
      { section: "Payments", label: "Pending", value: analytics.pendingCount },
      ...byType.flatMap((r) => [
        { section: "Membership Types", label: `${typeLabel(r)} — members`, value: r.count },
        { section: "Membership Types", label: `${typeLabel(r)} — revenue (INR)`, value: (r.revenueMinor / 100).toFixed(2) },
      ]),
      ...batches.map((b) => ({
        section: "Members by sport, court and timing",
        label: b.batchId === null ? b.sportName : `${b.sportName} · ${b.courtName} · ${formatTiming(b.startTime, b.endTime)} (${formatDays(b.daysOfWeek)})`,
        value: `${b.members} members, ${b.activeMembers} active`,
      })),
      { section: "Guest release", label: "Revenue (INR)", value: (guestRelease.revenueMinor / 100).toFixed(2) },
    ];
    const blob = new Blob(["﻿" + toCsv(rows)], { type: "text/csv" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = `memberships-${range.from}-to-${range.to}.csv`;
    a.click();
    URL.revokeObjectURL(url);
  }

  return (
    <ReportShell
      title="Membership Report"
      description="Members, revenue and what is still owed."
      status={status}
      onRetry={load}
      emptyMessage="No membership activity for this period."
      errorMessage="Unable to load the membership report. Please try again."
      filterBar={filterBar}
      onExportCsv={handleExport}
      exportDisabled={dirty}
    >
      <div className="space-y-5">
        {counts && analytics && (
          <>
            <div className="grid grid-cols-2 gap-4 md:grid-cols-3 2xl:grid-cols-5">
              <MembershipStatCard
                icon={UsersRound}
                iconBg="bg-blue-500/15"
                iconColor="text-blue-600 dark:text-blue-400"
                value={counts.total.toLocaleString("en-IN")}
                countTo={counts.total}
                format={(v) => Math.round(v).toLocaleString("en-IN")}
                label="Total Members"
                index={0}
              />
              <MembershipStatCard
                icon={UserRoundCheck}
                iconBg="bg-success/15"
                iconColor="text-success"
                value={counts.active.toLocaleString("en-IN")}
                countTo={counts.active}
                format={(v) => Math.round(v).toLocaleString("en-IN")}
                label="Active Members"
                index={1}
              />
              <MembershipStatCard
                icon={UserRoundX}
                iconBg="bg-purple-500/15"
                iconColor="text-purple-600 dark:text-purple-400"
                value={counts.inactive.toLocaleString("en-IN")}
                countTo={counts.inactive}
                format={(v) => Math.round(v).toLocaleString("en-IN")}
                label="Inactive Members"
                index={2}
              />
              <MembershipStatCard
                icon={Banknote}
                iconBg="bg-success/15"
                iconColor="text-success"
                value={formatCurrency(analytics.membershipRevenueMinor, INR)}
                countTo={analytics.membershipRevenueMinor}
                format={(v) => formatCurrency(Math.round(v), INR)}
                label="Membership Revenue"
                index={3}
              />
              <MembershipStatCard
                icon={Hourglass}
                iconBg="bg-destructive/15"
                iconColor="text-destructive"
                value={formatCurrency(analytics.outstandingMinor, INR)}
                countTo={analytics.outstandingMinor}
                format={(v) => formatCurrency(Math.round(v), INR)}
                label="Membership Outstanding"
                index={4}
              />
            </div>

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
                {byType.length === 0 ? (
                  <p className="text-sm text-muted-foreground">No new memberships in this period.</p>
                ) : (
                  <ul className="divide-y divide-border" aria-label="Memberships by type">
                    {byType.map((r) => (
                      <li key={`${r.membershipType}-${r.planName}`} className="flex items-center justify-between gap-3 py-2.5 first:pt-0 last:pb-0">
                        <span className="min-w-0 truncate text-sm font-medium">{typeLabel(r)}</span>
                        <span className="shrink-0 text-right text-sm tabular-nums">
                          <span className="font-semibold">{r.count.toLocaleString("en-IN")}</span>
                          <span className="text-muted-foreground"> {r.count === 1 ? "membership" : "memberships"}</span>
                          <span className="mx-1.5 text-muted-foreground">·</span>
                          <span className="font-semibold">{formatCurrency(r.revenueMinor, INR)}</span>
                        </span>
                      </li>
                    ))}
                  </ul>
                )}
              </Card>
            </div>
          </>
        )}

        {counts && (
          <>
            {/* The same two-panel layout as the Guest Bookings report: by sport on the left, by court / turf on the right. */}
            <div className="grid gap-4 lg:grid-cols-2">
              <Card className="p-4">
                <h2 className="mb-3 text-sm font-semibold">Memberships by Sport</h2>
                {sportBars.length === 0 ? (
                  <p className="text-sm text-muted-foreground">No membership timings in these dates.</p>
                ) : (
                  <>
                    <ReportBarList items={sportBars} />
                    <div className="mt-4">
                      <DataTable
                        caption="Memberships by sport"
                        columns={[
                          { key: "sport", label: "Sport" },
                          { key: "courts", label: "Courts / Turfs", align: "right" },
                          { key: "members", label: "Members", align: "right" },
                        ]}
                        rows={sportRows}
                      />
                    </div>
                  </>
                )}
              </Card>

              <Card className="p-4">
                <h2 className="mb-3 text-sm font-semibold">Memberships by Court</h2>
                {courtBars.length === 0 ? (
                  <p className="text-sm text-muted-foreground">No membership timings in these dates.</p>
                ) : (
                  <>
                    <ReportBarList items={courtBars} />
                    <div className="mt-4">
                      <DataTable
                        caption="Memberships by court"
                        columns={[
                          { key: "court", label: "Court / Turf" },
                          { key: "sport", label: "Sport" },
                          { key: "members", label: "Members", align: "right" },
                        ]}
                        rows={courtRows}
                      />
                    </div>
                  </>
                )}
              </Card>
            </div>

            <Card className="p-4">
              <div className="mb-3 flex flex-wrap items-start justify-between gap-3">
                <div>
                  <h2 className="text-sm font-semibold">Memberships by Timing</h2>
                  <p className="text-xs text-muted-foreground">Members by the timing they are booked into (members counted for the selected dates)</p>
                </div>
                {courtOptions.length > 1 && (
                  <Select value={activeCourt} onValueChange={setTimingCourt}>
                    <SelectTrigger className="h-9 w-[200px]" aria-label="Filter timings by court">
                      <SelectValue />
                    </SelectTrigger>
                    <SelectContent>
                      <SelectItem value={ALL_COURTS}>All courts / turfs</SelectItem>
                      {courtOptions.map((o) => (
                        <SelectItem key={o.key} value={o.key}>
                          {o.label}
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                )}
              </div>
              {timingRows.length === 0 ? (
                <p className="text-sm text-muted-foreground">No membership timings in these dates.</p>
              ) : (
                <DataTable
                  caption="Memberships by timing"
                  columns={[
                    { key: "timing", label: "Timing" },
                    { key: "days", label: "Days" },
                    { key: "court", label: "Court / Turf" },
                    { key: "sport", label: "Sport" },
                    { key: "members", label: "Members", align: "right" },
                    { key: "active", label: "Active", align: "right" },
                  ]}
                  rows={timingRows}
                />
              )}
              {unassigned && (
                <p className="mt-3 text-xs text-muted-foreground">
                  {unassigned.members.toLocaleString("en-IN")} {unassigned.members === 1 ? "member is" : "members are"} not assigned to any session timing.
                </p>
              )}
            </Card>
          </>
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
