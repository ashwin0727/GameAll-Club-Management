"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { ChartPie, Users, Wallet } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { getFacilityService } from "@/services/facility";
import { useDashboardSummary } from "@/features/dashboard/hooks/use-dashboard-summary";
import { KpiCard } from "@/features/dashboard/components/kpi-card";
import type { DateRangePreset, RevenueOverview as RevenueOverviewData, ScheduleBlockType, ScheduleTimeline } from "@/features/dashboard/types";
import { cn, formatCurrencyINR } from "@/lib/utils";

const DATE_PRESETS: { value: DateRangePreset; label: string }[] = [
  { value: "TODAY", label: "Today" },
  { value: "YESTERDAY", label: "Yesterday" },
  { value: "THIS_WEEK", label: "This Week" },
  { value: "THIS_MONTH", label: "This Month" },
];

const QUICK_ACTIONS: { label: string; href: string }[] = [
  { label: "Add Booking", href: "/bookings" },
  { label: "Add Member", href: "/memberships" },
  { label: "Guest Slots", href: "/membership-sessions" },
  { label: "Guest Players", href: "/guests" },
  { label: "Finance", href: "/finance" },
  { label: "Refunds", href: "/refunds" },
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
  const [revenueMonthOffset, setRevenueMonthOffset] = useState(0);

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
    revenueMonthOffset,
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

  const { memberships } = summary;
  const memberTotal = memberships.active + memberships.expiringSoon + memberships.expired;

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
        <KpiCard index={0} label="Revenue" kpi={summary.kpis.revenueInr} format={formatCurrencyINR} icon={Wallet} accentColor="#5B6CFF" />
        <KpiCard index={1} label="Active Membership" kpi={summary.kpis.activeMemberships} format={(v) => String(v)} icon={Users} accentColor="#8B5CF6" />
        <KpiCard index={2} label="Guest Bookings" kpi={summary.kpis.guestBookings} format={(v) => String(v)} icon={Users} accentColor="#FFB020" />
        <KpiCard index={3} label="Utilization" kpi={summary.kpis.utilizationPercent} format={(v) => `${v}%`} icon={ChartPie} accentColor="#00F08A" />
      </div>

      {/* Expiring-membership alert — only when there's actually something to act on */}
      {memberships.expiringSoon > 0 && (
        <button
          type="button"
          onClick={() => router.push("/memberships")}
          className="flex w-full items-center justify-between gap-3 rounded-xl border border-warning/40 bg-warning/10 p-4 text-left transition-colors hover:bg-warning/15"
        >
          <span className="text-sm font-medium text-foreground">
            {memberships.expiringSoon} membership{memberships.expiringSoon === 1 ? "" : "s"} expiring soon
          </span>
          <span className="text-sm text-muted-foreground">View members →</span>
        </button>
      )}

      {/* Today's Schedule */}
      <Card className="stat-enter space-y-3 overflow-hidden p-4 sm:p-5" style={{ "--stat-delay": "300ms" } as React.CSSProperties}>
        <div className="flex items-center justify-between">
          <h3 className="text-sm font-semibold">Today&apos;s Schedule</h3>
          <Button
            type="button"
            variant="ghost"
            size="sm"
            className="h-8 px-0 text-xs"
            onClick={() => router.push("/bookings")}
          >
            View All Bookings →
          </Button>
        </div>
        <ScheduleTimelineView timeline={summary.scheduleTimeline} showNow={preset === "TODAY"} />
      </Card>

      {/* Revenue Overview */}
      <Card className="stat-enter space-y-3 overflow-hidden p-4 sm:p-5" style={{ "--stat-delay": "360ms" } as React.CSSProperties}>
        <div className="flex items-center justify-between gap-2">
          <h3 className="text-sm font-semibold">Revenue Overview</h3>
          <select
            aria-label="Revenue month"
            value={revenueMonthOffset}
            onChange={(e) => setRevenueMonthOffset(Number(e.target.value))}
            className="h-8 rounded-md border border-input bg-secondary/60 px-2 text-xs"
          >
            {MONTH_OPTIONS.map((opt) => (
              <option key={opt.offset} value={opt.offset}>
                {opt.label}
              </option>
            ))}
          </select>
        </div>
        <RevenueOverviewPanel overview={summary.revenueOverview} />
      </Card>

      {/* Attention Required */}
      <div className="grid grid-cols-1 gap-4">
        <Card className="stat-enter space-y-3 p-4 sm:p-5" style={{ "--stat-delay": "420ms" } as React.CSSProperties}>
          <h3 className="text-sm font-semibold">Attention Required</h3>
          {summary.attentionItems.length === 0 ? (
            <p className="text-sm text-success">You&apos;re all caught up. No immediate attention required.</p>
          ) : (
            <ul className="space-y-2">
              {summary.attentionItems.map((item) => (
                <li key={item.id} className="flex items-center justify-between gap-3 text-sm">
                  <span className="text-muted-foreground">{item.message}</span>
                  {item.actionHref && item.actionLabel && (
                    <Button
                      type="button"
                      variant="outline"
                      size="sm"
                      className="h-8 shrink-0 px-2 text-xs"
                      onClick={() => router.push(item.actionHref!)}
                    >
                      {item.actionLabel}
                    </Button>
                  )}
                </li>
              ))}
            </ul>
          )}
        </Card>
      </div>

      {/* Memberships | Utilization */}
      <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
        <Card className="stat-enter space-y-3 p-4 sm:p-5" style={{ "--stat-delay": "480ms" } as React.CSSProperties}>
          <h3 className="text-sm font-semibold">Memberships</h3>
          <div>
            <p className="text-2xl font-semibold text-foreground">{memberTotal}</p>
            <p className="text-xs text-muted-foreground">Total members</p>
          </div>
          {memberTotal > 0 && (
            <div className="bar-grow flex h-2 overflow-hidden rounded-full" style={{ "--bar-delay": "160ms" } as React.CSSProperties}>
              <span className="bg-success" style={{ flexGrow: memberships.active }} />
              <span className="bg-warning" style={{ flexGrow: memberships.expiringSoon }} />
              <span className="bg-destructive" style={{ flexGrow: memberships.expired }} />
            </div>
          )}
          <p className="text-xs text-muted-foreground">
            {memberships.active} active · {memberships.expiringSoon} expiring · {memberships.expired} expired
          </p>
          <Button
            type="button"
            variant="ghost"
            size="sm"
            className="h-8 px-0 text-xs"
            onClick={() => router.push("/memberships")}
          >
            View Members →
          </Button>
        </Card>

        <Card className="stat-enter space-y-3 p-4 sm:p-5" style={{ "--stat-delay": "540ms" } as React.CSSProperties}>
          <div className="flex items-center justify-between">
            <h3 className="text-sm font-semibold">Court / Turf Utilization</h3>
            <span className="text-sm font-medium text-foreground">{summary.utilization.overallPercent}%</span>
          </div>
          {summary.utilization.bySport.length === 0 ? (
            <p className="text-sm text-muted-foreground">No sports configured yet.</p>
          ) : (
            <div className="space-y-2">
              {summary.utilization.bySport.map((sport, i) => (
                <div key={sport.facilitySportId} className="space-y-1">
                  <div className="flex items-center justify-between text-xs">
                    <span className="text-muted-foreground">{sport.sportName}</span>
                    <span className="font-medium text-foreground">{sport.utilizationPercent}%</span>
                  </div>
                  <div className="h-1.5 overflow-hidden rounded-full bg-secondary">
                    <div
                      className="bar-grow h-full rounded-full bg-primary"
                      style={
                        {
                          width: `${Math.min(Math.max(sport.utilizationPercent, 0), 100)}%`,
                          "--bar-delay": `${160 + i * 90}ms`,
                        } as React.CSSProperties
                      }
                    />
                  </div>
                </div>
              ))}
            </div>
          )}
        </Card>
      </div>

      {/* Quick Actions */}
      <Card className="stat-enter space-y-3 p-4 sm:p-5" style={{ "--stat-delay": "600ms" } as React.CSSProperties}>
        <h3 className="text-sm font-semibold">Quick Actions</h3>
        <div className="grid grid-cols-2 gap-2 sm:grid-cols-3 lg:grid-cols-6">
          {QUICK_ACTIONS.map((action) => (
            <Button
              key={action.href}
              type="button"
              variant="outline"
              size="sm"
              className="h-11 justify-start"
              onClick={() => router.push(action.href)}
            >
              {action.label}
            </Button>
          ))}
        </div>
      </Card>
    </div>
  );
}

const HOUR_WIDTH = 68;
const LABEL_WIDTH = 116;
const LANE_HEIGHT = 34;
const TRACK_PADDING = 0;
/** How long the hour ruler takes to settle before the court rows start. */
const RULER_SETTLE_MS = 120;

const BLOCK_STYLES: Record<ScheduleBlockType, string> = {
  MEMBER: "border-emerald-500/70 bg-emerald-500/15 text-emerald-700 dark:text-emerald-300",
  GUEST: "border-blue-500/70 bg-blue-500/15 text-blue-700 dark:text-blue-300",
  SESSION: "border-purple-500/70 bg-purple-500/15 text-purple-700 dark:text-purple-300",
};

const LEGEND: { type: ScheduleBlockType; label: string; dot: string }[] = [
  { type: "MEMBER", label: "Member", dot: "bg-emerald-500" },
  { type: "GUEST", label: "Guest", dot: "bg-blue-500" },
  { type: "SESSION", label: "Membership session", dot: "bg-purple-500" },
];

function formatHourTick(hour: number): string {
  const h = hour % 24;
  const h12 = h % 12 === 0 ? 12 : h % 12;
  return `${h12} ${h < 12 ? "AM" : "PM"}`;
}

function ScheduleTimelineView({ timeline, showNow }: { timeline: ScheduleTimeline; showNow: boolean }) {
  const [sportFilter, setSportFilter] = useState<string | null>(null);
  const hours = timeline.endHour - timeline.startHour;
  if (timeline.courts.length === 0 || hours <= 0) {
    return <p className="text-sm text-muted-foreground">No courts configured yet.</p>;
  }

  const sportNames = [...new Set(timeline.courts.map((c) => c.sportName))].sort((a, b) => a.localeCompare(b));
  const activeSport = sportFilter && sportNames.includes(sportFilter) ? sportFilter : null;
  const courts = activeSport ? timeline.courts.filter((c) => c.sportName === activeSport) : timeline.courts;

  const trackWidth = hours * HOUR_WIDTH;
  const windowMinutes = hours * 60;
  const toX = (minute: number) => ((minute - timeline.startHour * 60) / windowMinutes) * trackWidth;

  const now = new Date();
  const nowMinute = now.getHours() * 60 + now.getMinutes();
  const nowInWindow = showNow && nowMinute >= timeline.startHour * 60 && nowMinute <= timeline.endHour * 60;

  return (
    <div className="space-y-3">
      {sportNames.length > 1 && (
        <div className="flex flex-wrap gap-1.5">
          {[null, ...sportNames].map((name) => {
            const selected = activeSport === name;
            return (
              <button
                key={name ?? "__all"}
                type="button"
                onClick={() => setSportFilter(name)}
                className={cn(
                  "rounded-full border px-3 py-1 text-xs font-medium transition-colors",
                  selected
                    ? "border-primary bg-primary text-primary-foreground"
                    : "border-input bg-secondary/40 text-muted-foreground hover:bg-secondary",
                )}
              >
                {name ?? "All Courts"}
              </button>
            );
          })}
        </div>
      )}
      {/* Keyed on the filter so switching sports replays the reveal rather
          than snapping the new grid into place. */}
      <div className="overflow-x-auto" key={activeSport ?? "__all"}>
        <div style={{ width: LABEL_WIDTH + trackWidth }} className="min-w-full">
          {/* Hour ruler */}
          <div className="flex border-b border-border pb-1" style={{ paddingLeft: LABEL_WIDTH }}>
            {Array.from({ length: hours }).map((_, i) => (
              <div
                key={i}
                className="schedule-tick-enter shrink-0 text-xs text-muted-foreground"
                style={{ width: HOUR_WIDTH, "--tick-delay": `${i * 18}ms` } as React.CSSProperties}
              >
                {formatHourTick(timeline.startHour + i)}
              </div>
            ))}
          </div>

          {/* Court rows */}
          <div className="relative">
            {courts.map((court, rowIndex) => {
              const rowHeight = court.laneCount * LANE_HEIGHT + TRACK_PADDING;
              const rowDelay = RULER_SETTLE_MS + rowIndex * 55;
              return (
                <div
                  key={court.courtId}
                  className="schedule-row-enter flex border-b border-border/60 last:border-b-0"
                  style={{ "--row-delay": `${rowDelay}ms` } as React.CSSProperties}
                >
                  <div className="shrink-0 py-2 pr-2" style={{ width: LABEL_WIDTH }}>
                    <p className="text-xs font-medium text-foreground">{court.courtName}</p>
                    <p className="truncate text-[11px] text-muted-foreground">{court.sportName}</p>
                  </div>
                  <div className="relative shrink-0" style={{ width: trackWidth, height: rowHeight }}>
                    {/* Hour gridlines */}
                    {Array.from({ length: hours }).map((_, i) => (
                      <div
                        key={i}
                        className="absolute top-0 h-full border-l border-border/40"
                        style={{ left: i * HOUR_WIDTH }}
                      />
                    ))}
                    {court.blocks.map((block) => (
                      <div
                        key={block.id}
                        title={`${block.label} · ${block.timeLabel}`}
                        className={cn(
                          "schedule-block-enter absolute flex flex-col justify-center overflow-hidden rounded-[2px] border px-1.5 transition-transform duration-150 hover:z-10 hover:scale-[1.02]",
                          BLOCK_STYLES[block.type],
                        )}
                        style={
                          {
                            left: toX(block.startMinute),
                            width: Math.max(toX(block.endMinute) - toX(block.startMinute), 6),
                            top: block.lane * LANE_HEIGHT,
                            height: LANE_HEIGHT,
                            // Rows land first, then each booking wipes open in
                            // the order it starts during the day.
                            "--block-delay": `${rowDelay + 140 + (toX(block.startMinute) / Math.max(trackWidth, 1)) * 260}ms`,
                          } as React.CSSProperties
                        }
                      >
                        <p className="truncate text-[11px] font-semibold leading-tight">{block.label}</p>
                        <p className="truncate text-[10px] leading-tight opacity-80">{block.timeLabel}</p>
                      </div>
                    ))}
                  </div>
                </div>
              );
            })}

            {nowInWindow && (
              <div
                className="schedule-now-enter pointer-events-none absolute top-0 z-10 h-full border-l-2 border-destructive"
                style={
                  {
                    left: LABEL_WIDTH + toX(nowMinute),
                    "--now-delay": `${RULER_SETTLE_MS + courts.length * 55 + 260}ms`,
                  } as React.CSSProperties
                }
              >
                <span className="absolute -left-6 -top-0.5 rounded bg-destructive px-1 text-[10px] font-semibold text-white">
                  {formatHourTick(now.getHours())}
                </span>
              </div>
            )}
          </div>
        </div>
      </div>

      <div className="flex flex-wrap gap-x-4 gap-y-1">
        {LEGEND.map((item) => (
          <span key={item.type} className="flex items-center gap-1.5 text-xs text-muted-foreground">
            <span className={cn("h-2 w-2 rounded-full", item.dot)} />
            {item.label}
          </span>
        ))}
      </div>
    </div>
  );
}

const MONTH_NAMES_SHORT = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

const MONTH_OPTIONS = Array.from({ length: 12 }, (_, offset) => {
  const d = new Date();
  d.setDate(1);
  d.setMonth(d.getMonth() - offset);
  const label =
    offset === 0
      ? "This Month"
      : offset === 1
        ? "Last Month"
        : `${MONTH_NAMES_SHORT[d.getMonth()]} ${d.getFullYear()}`;
  return { offset, label };
});

function niceCeil(v: number): number {
  if (v <= 0) return 1000;
  const pow = Math.pow(10, Math.floor(Math.log10(v)));
  const n = v / pow;
  const step = n <= 1 ? 1 : n <= 2 ? 2 : n <= 5 ? 5 : 10;
  return step * pow;
}

function compactInr(v: number): string {
  if (v >= 1_00_00_000) return `₹${(v / 1_00_00_000).toFixed(v % 1_00_00_000 ? 1 : 0)}Cr`;
  if (v >= 1_00_000) return `₹${(v / 1_00_000).toFixed(v % 1_00_000 ? 1 : 0)}L`;
  if (v >= 1000) return `₹${Math.round(v / 1000)}K`;
  return `₹${Math.round(v)}`;
}

function RevenueOverviewChart({ points }: { points: RevenueOverviewData["points"] }) {
  const H = 150;
  const values = points.map((p) => p.amountInr);
  const niceMax = niceCeil(Math.max(...values, 0));
  const yTicks = [1, 0.75, 0.5, 0.25, 0].map((f) => niceMax * f);

  const n = points.length;
  const xPct = (i: number) => (n <= 1 ? 50 : (i / (n - 1)) * 100);
  const yPx = (v: number) => H - (v / niceMax) * H;

  const linePath = values
    .map((v, i) => `${i === 0 ? "M" : "L"}${xPct(i).toFixed(2)},${yPx(v).toFixed(2)}`)
    .join(" ");
  const areaPath = `${linePath} L${xPct(n - 1).toFixed(2)},${H} L${xPct(0).toFixed(2)},${H} Z`;

  const xTickCount = Math.min(6, n);
  const xTickIdx = Array.from({ length: xTickCount }, (_, k) =>
    xTickCount <= 1 ? 0 : Math.round((k / (xTickCount - 1)) * (n - 1)),
  );

  return (
    <div className="space-y-1">
      <div className="flex gap-2">
        <div className="flex w-12 shrink-0 flex-col justify-between py-0 text-right text-[10px] text-muted-foreground" style={{ height: H }}>
          {yTicks.map((t, i) => (
            <span key={i}>{compactInr(t)}</span>
          ))}
        </div>
        <div className="relative min-w-0 flex-1" style={{ height: H }}>
          {yTicks.map((_, i) => (
            <div
              key={i}
              className="absolute inset-x-0 border-t border-border/40"
              style={{ top: (i / (yTicks.length - 1)) * H }}
            />
          ))}
          <svg
            viewBox={`0 0 100 ${H}`}
            preserveAspectRatio="none"
            className="absolute inset-0 h-full w-full"
            role="img"
            aria-label="Revenue trend for the month"
          >
            <defs>
              <linearGradient id="revenue-fill" x1="0" x2="0" y1="0" y2="1">
                <stop offset="0%" stopColor="hsl(var(--primary))" stopOpacity="0.35" />
                <stop offset="100%" stopColor="hsl(var(--primary))" stopOpacity="0" />
              </linearGradient>
            </defs>
            <path className="chart-area-wipe" d={areaPath} fill="url(#revenue-fill)" />
            {/* pathLength=1 normalises the dash maths, so the line draws
                itself left-to-right without measuring the real path. */}
            <path
              className="chart-line-draw"
              d={linePath}
              fill="none"
              stroke="hsl(var(--primary))"
              strokeWidth={2}
              strokeLinejoin="round"
              vectorEffect="non-scaling-stroke"
              pathLength={1}
              strokeDasharray={1}
            />
          </svg>
        </div>
      </div>
      <div className="relative ml-14 h-4">
        {xTickIdx.map((idx) => {
          const parts = points[idx]!.date.split("-");
          const m = Number(parts[1] ?? 1);
          const d = Number(parts[2] ?? 1);
          return (
            <span
              key={idx}
              className="absolute -translate-x-1/2 whitespace-nowrap text-[10px] text-muted-foreground first:translate-x-0 last:-translate-x-full"
              style={{ left: `${xPct(idx)}%` }}
            >
              {d} {MONTH_NAMES_SHORT[m - 1]}
            </span>
          );
        })}
      </div>
    </div>
  );
}

function RevenueOverviewPanel({ overview }: { overview: RevenueOverviewData }) {
  const up = overview.changePercent !== null && overview.changePercent > 0;
  const down = overview.changePercent !== null && overview.changePercent < 0;
  return (
    <div className="grid grid-cols-1 gap-4 lg:grid-cols-2 lg:gap-6">
      <div className="min-w-0 space-y-3">
        <div className="flex flex-wrap items-start justify-between gap-2">
          <div>
            <p className="text-2xl font-semibold text-foreground">{formatCurrencyINR(overview.totalInr)}</p>
            <p className="text-xs text-muted-foreground">Total Revenue · {overview.monthLabel}</p>
          </div>
          {overview.changePercent !== null && (
            <span
              className={cn(
                "rounded-full px-2 py-0.5 text-xs font-medium",
                up && "bg-success/15 text-success",
                down && "bg-destructive/15 text-destructive",
                !up && !down && "bg-secondary text-muted-foreground",
              )}
            >
              {up ? "↑" : down ? "↓" : "→"} {Math.abs(overview.changePercent).toFixed(1)}% vs last month
            </span>
          )}
        </div>
        {/* Keyed on the month so paging replays the draw-in. */}
        <RevenueOverviewChart key={overview.monthLabel} points={overview.points} />
      </div>
      <div className="min-w-0 border-t border-border pt-3 lg:border-l lg:border-t-0 lg:pl-6 lg:pt-0">
        <p className="mb-2 text-sm font-semibold">Revenue Breakdown</p>
        <RevenueBreakdownChart key={overview.monthLabel} segments={overview.breakdown} total={overview.totalInr} />
      </div>
    </div>
  );
}

const BREAKDOWN_COLORS: Record<string, string> = {
  bookings: "#00D084",
  memberships: "#5B6CFF",
  coaching: "#FFB020",
  other: "#8B5CF6",
};

function RevenueBreakdownChart({
  segments,
  total,
}: {
  segments: RevenueOverviewData["breakdown"];
  total: number;
}) {
  const R = 42;
  const C = 2 * Math.PI * R;
  const drawTotal = total > 0 ? total : 1;
  let offset = 0;

  return (
    <div className="flex items-center gap-4">
      <svg viewBox="0 0 100 100" className="h-28 w-28 shrink-0 -rotate-90" role="img" aria-label="Revenue breakdown">
        <circle cx="50" cy="50" r={R} fill="none" stroke="hsl(var(--secondary))" strokeWidth="14" />
        {total > 0 &&
          segments.map((seg, i) => {
            if (seg.amountInr <= 0) return null;
            const len = (seg.amountInr / drawTotal) * C;
            const dash = `${len} ${C - len}`;
            // Shifting the dash offset by the arc's own length hides it
            // entirely, so animating back to -offset sweeps it open.
            const el = (
              <circle
                key={seg.key}
                className="donut-sweep"
                cx="50"
                cy="50"
                r={R}
                fill="none"
                stroke={BREAKDOWN_COLORS[seg.key]}
                strokeWidth="14"
                strokeDasharray={dash}
                strokeDashoffset={-offset}
                style={
                  {
                    "--dash-from": -offset + len,
                    "--dash-to": -offset,
                    "--sweep-delay": `${120 + i * 110}ms`,
                  } as React.CSSProperties
                }
              />
            );
            offset += len;
            return el;
          })}
      </svg>
      <ul className="min-w-0 flex-1 space-y-1.5">
        {segments.map((seg) => {
          const pct = total > 0 ? Math.round((seg.amountInr / total) * 100) : 0;
          return (
            <li key={seg.key} className="flex items-center justify-between gap-2 text-xs">
              <span className="flex min-w-0 items-center gap-1.5">
                <span
                  className="h-2 w-2 shrink-0 rounded-full"
                  style={{ backgroundColor: BREAKDOWN_COLORS[seg.key] }}
                />
                <span className="truncate text-foreground">{seg.label}</span>
                {seg.count !== null && <span className="text-muted-foreground">· {seg.count}</span>}
              </span>
              <span className="flex shrink-0 items-center gap-2">
                <span className="text-muted-foreground">
                  {seg.unavailable ? "—" : formatCurrencyINR(seg.amountInr)}
                </span>
                <span className="w-8 text-right font-medium text-foreground">{pct}%</span>
              </span>
            </li>
          );
        })}
      </ul>
    </div>
  );
}
