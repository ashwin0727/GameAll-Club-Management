"use client";

import { useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import {
  ArrowRight,
  BadgeIndianRupee,
  CalendarCheck2,
  CalendarClock,
  CalendarPlus,
  ChevronRight,
  Dumbbell,
  Gauge,
  GraduationCap,
  Hourglass,
  MoreHorizontal,
  Receipt,
  ShieldBan,
  TriangleAlert,
  Trophy,
  UserPlus,
  UserRoundCheck,
  Users,
  UserRoundX,
  UserRound,
  type LucideIcon,
} from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { useFacility } from "@/features/facility/hooks/use-facility";
import { useDashboardSummary } from "@/features/dashboard/hooks/use-dashboard-summary";
import type {
  DashboardSummary,
  DateRangePreset,
  KpiValue,
  RevenueOverview as RevenueOverviewData,
  ScheduleBlock,
  ScheduleBlockType,
  ScheduleCourtRow,
} from "@/features/dashboard/types";
import { useUiStore } from "@/stores/ui-store";
import { cn, formatCurrencyINR } from "@/lib/utils";

/** The Home page always reports on today. */
const PRESET: DateRangePreset = "TODAY";

const COMPARE_LABEL: Record<DateRangePreset, string> = {
  TODAY: "vs yesterday",
  YESTERDAY: "vs day before",
  THIS_WEEK: "vs last week",
  THIS_MONTH: "vs last month",
  CUSTOM: "",
};

/** Every quick action points at a route that already exists. */
const QUICK_ACTIONS: { label: string; href: string; icon: LucideIcon }[] = [
  { label: "Guest Booking", href: "/guest-bookings", icon: UserRound },
  { label: "Add Member", href: "/memberships", icon: UserPlus },
  { label: "Add Expense", href: "/finance/expenses", icon: Receipt },
  { label: "Block Court", href: "/maintenance/court-schedule", icon: ShieldBan },
  { label: "Create Coaching Session", href: "/coaching/sessions", icon: GraduationCap },
  { label: "Open Tournament App", href: "/tournaments", icon: Trophy },
];

/** Same 3-up proportions the design uses for every content row. */
const ROW_GRID = "grid grid-cols-1 gap-3 lg:grid-cols-[333fr_181fr_183fr]";

function greeting(): string {
  const hour = new Date().getHours();
  if (hour < 12) return "Good morning";
  if (hour < 17) return "Good afternoon";
  return "Good evening";
}

function formatMinute(minute: number): string {
  const m = ((minute % 1440) + 1440) % 1440;
  const h = Math.floor(m / 60);
  const h12 = h % 12 === 0 ? 12 : h % 12;
  return `${String(h12).padStart(2, "0")}:${String(m % 60).padStart(2, "0")} ${h < 12 ? "AM" : "PM"}`;
}

const TYPE_LABEL: Record<ScheduleBlockType, string> = {
  MEMBER: "Member",
  GUEST: "Guest",
  SESSION: "Session",
};

const TYPE_TAG: Record<ScheduleBlockType, string> = {
  MEMBER: "bg-emerald-500/15 text-emerald-700 dark:text-emerald-300",
  GUEST: "bg-blue-500/15 text-blue-700 dark:text-blue-300",
  SESSION: "bg-purple-500/15 text-purple-700 dark:text-purple-300",
};

function DashCard({
  title,
  action,
  children,
  className,
  delay = 0,
}: {
  title: string;
  action?: React.ReactNode;
  children: React.ReactNode;
  className?: string;
  delay?: number;
}) {
  return (
    <Card
      className={cn("stat-enter flex min-w-0 flex-col p-4", className)}
      style={{ "--stat-delay": `${delay}ms` } as React.CSSProperties}
    >
      <div className="mb-3 flex items-center justify-between gap-2">
        <h3 className="text-sm font-semibold">{title}</h3>
        {action}
      </div>
      {children}
    </Card>
  );
}

function CardLink({ href, children }: { href: string; children: React.ReactNode }) {
  return (
    <Link href={href} className="flex items-center gap-1 text-[11px] font-medium text-primary hover:underline">
      {children}
      <ArrowRight className="h-3 w-3" aria-hidden />
    </Link>
  );
}

function EmptyNote({ children }: { children: React.ReactNode }) {
  return <p className="py-6 text-center text-xs text-muted-foreground">{children}</p>;
}

function DashKpi({
  icon: Icon,
  tone,
  label,
  value,
  sub,
  subClass,
  href,
  children,
  delay,
}: {
  icon: LucideIcon;
  /** Tailwind classes for the icon chip (background + glyph colour). */
  tone: string;
  label: string;
  value: string;
  sub?: React.ReactNode;
  subClass?: string;
  href?: string;
  children?: React.ReactNode;
  delay: number;
}) {
  const body = (
    <Card
      className="stat-enter flex h-full min-w-0 items-center gap-3 p-4 transition-shadow hover:shadow-md"
      style={{ "--stat-delay": `${delay}ms` } as React.CSSProperties}
    >
      <span className={cn("flex h-11 w-11 shrink-0 items-center justify-center rounded-xl", tone)}>
        <Icon className="h-5 w-5" aria-hidden />
      </span>
      <div className="min-w-0 flex-1 space-y-1">
        <p className="truncate text-xs text-muted-foreground">{label}</p>
        <p className="truncate text-xl font-semibold leading-tight tabular-nums text-foreground">{value}</p>
        {sub && <p className={cn("truncate text-[11px]", subClass ?? "text-muted-foreground")}>{sub}</p>}
        {children}
      </div>
      {href && <ChevronRight className="h-4 w-4 shrink-0 text-muted-foreground" aria-hidden />}
    </Card>
  );
  return href ? (
    <Link href={href} className="block min-w-0">
      {body}
    </Link>
  ) : (
    body
  );
}

function trendText(kpi: KpiValue, compare: string): { text: string; cls: string } | null {
  if (kpi.changePercent === null) return null;
  const up = kpi.changePercent > 0;
  const down = kpi.changePercent < 0;
  return {
    text: `${up ? "↑" : down ? "↓" : "→"} ${Math.abs(kpi.changePercent).toFixed(1)}% ${compare}`.trim(),
    cls: up ? "text-success" : down ? "text-destructive" : "text-muted-foreground",
  };
}

type ActivityStatus = "live" | "next" | "booked" | "available";

interface CourtNow {
  court: ScheduleCourtRow;
  block: ScheduleBlock | null;
  status: ActivityStatus;
  /** Until when a live court stays busy, in minutes from midnight. */
  busyUntil: number | null;
}

/** Per court: what is on right now, else what is next, else it is free. */
function courtsNow(courts: ScheduleCourtRow[], nowMinute: number, isToday: boolean): CourtNow[] {
  let nextClaimed = false;
  return courts.map((court) => {
    const sorted = [...court.blocks].sort((a, b) => a.startMinute - b.startMinute);
    const live = isToday ? sorted.find((b) => b.startMinute <= nowMinute && nowMinute < b.endMinute) : undefined;
    if (live) return { court, block: live, status: "live", busyUntil: live.endMinute };
    const upcoming = sorted.find((b) => b.startMinute > (isToday ? nowMinute : -1));
    if (upcoming) {
      const status: ActivityStatus = nextClaimed ? "booked" : "next";
      nextClaimed = true;
      return { court, block: upcoming, status, busyUntil: null };
    }
    return { court, block: null, status: "available", busyUntil: null };
  });
}

const STATUS_DOT: Record<ActivityStatus, string> = {
  live: "bg-success",
  next: "bg-blue-500",
  booked: "bg-blue-500",
  available: "bg-success",
};

const STATUS_TEXT: Record<ActivityStatus, { label: string; cls: string }> = {
  live: { label: "Live", cls: "text-success" },
  next: { label: "Next", cls: "text-blue-600 dark:text-blue-400" },
  booked: { label: "Booked", cls: "text-blue-600 dark:text-blue-400" },
  available: { label: "Available", cls: "text-success" },
};

function CourtActivityCard({ rows, delay }: { rows: CourtNow[]; delay: number }) {
  return (
    <DashCard
      title="Today's Court Activity"
      delay={delay}
      action={<CardLink href="/bookings">View Calendar</CardLink>}
    >
      {rows.length === 0 ? (
        <EmptyNote>No courts configured yet.</EmptyNote>
      ) : (
        <ul className="divide-y divide-border/60">
          {rows.slice(0, 6).map(({ court, block, status }) => (
            <li
              key={court.courtId}
              className="grid grid-cols-[4.25rem_3.25rem_minmax(0,1fr)_auto_4.25rem] items-center gap-2 py-2 text-xs"
            >
              <span className="tabular-nums text-muted-foreground">{block ? formatMinute(block.startMinute) : "—"}</span>
              <span className="truncate rounded-md bg-secondary px-1.5 py-0.5 text-center text-[11px] font-medium">
                {court.courtName}
              </span>
              <span className="truncate text-foreground">{block?.label ?? "—"}</span>
              {block ? (
                <span className={cn("rounded-md px-1.5 py-0.5 text-[11px] font-medium", TYPE_TAG[block.type])}>
                  {TYPE_LABEL[block.type]}
                </span>
              ) : (
                <span />
              )}
              <span className={cn("flex items-center justify-end gap-1.5 text-[11px] font-medium", STATUS_TEXT[status].cls)}>
                <span className={cn("h-1.5 w-1.5 rounded-full", STATUS_DOT[status])} />
                {STATUS_TEXT[status].label}
              </span>
            </li>
          ))}
        </ul>
      )}
    </DashCard>
  );
}

function CourtStatusCard({ rows, delay }: { rows: CourtNow[]; delay: number }) {
  return (
    <DashCard title="Court Status" delay={delay} action={<CardLink href="/maintenance/court-schedule">View All</CardLink>}>
      {rows.length === 0 ? (
        <EmptyNote>No courts configured yet.</EmptyNote>
      ) : (
        <ul className="space-y-2.5">
          {rows.slice(0, 7).map(({ court, status, busyUntil }) => {
            const busy = status === "live";
            return (
              <li key={court.courtId} className="flex items-center justify-between gap-2 text-xs">
                <span className="w-16 shrink-0 truncate font-medium">{court.courtName}</span>
                <span className="flex min-w-0 flex-1 items-center gap-1.5">
                  <span className={cn("h-1.5 w-1.5 shrink-0 rounded-full", busy ? "bg-destructive" : "bg-success")} />
                  <span className={busy ? "text-destructive" : "text-success"}>{busy ? "Busy" : "Available"}</span>
                </span>
                {busy && busyUntil !== null && (
                  <span className="shrink-0 text-[11px] text-muted-foreground">Until {formatMinute(busyUntil)}</span>
                )}
              </li>
            );
          })}
        </ul>
      )}
    </DashCard>
  );
}

function QuickActionsCard({ onGo, delay }: { onGo: (href: string) => void; delay: number }) {
  return (
    <DashCard title="Quick Actions" delay={delay}>
      <div className="space-y-2">
        <Button type="button" className="h-11 w-full justify-between" onClick={() => onGo("/bookings")}>
          <span className="flex items-center gap-2">
            <CalendarPlus className="h-4 w-4" aria-hidden />
            New Booking
          </span>
          <ChevronRight className="h-4 w-4" aria-hidden />
        </Button>
        <div className="grid grid-cols-2 gap-2">
          {QUICK_ACTIONS.map(({ label, href, icon: Icon }) => (
            <button
              key={href}
              type="button"
              onClick={() => onGo(href)}
              className="flex min-h-[3.25rem] flex-col items-start justify-center gap-1 rounded-lg border border-border bg-secondary/40 px-2.5 py-2 text-left text-[11px] font-medium leading-tight transition-colors hover:bg-accent"
            >
              <Icon className="h-3.5 w-3.5 text-muted-foreground" aria-hidden />
              {label}
            </button>
          ))}
        </div>
      </div>
    </DashCard>
  );
}

function paymentChip(block: ScheduleBlock): { label: string; cls: string } | null {
  switch (block.paymentStatus) {
    case "PAID":
      return { label: "Paid", cls: "bg-success/15 text-success" };
    case "PENDING":
      return { label: "Pending", cls: "bg-warning/15 text-warning" };
    case "REFUNDED":
      return { label: "Refunded", cls: "bg-secondary text-muted-foreground" };
    default:
      return null;
  }
}

function statusChip(block: ScheduleBlock): { label: string; cls: string } {
  switch (block.bookingStatus) {
    case "pending":
      return { label: "Pending", cls: "bg-warning/15 text-warning" };
    case "completed":
      return { label: "Completed", cls: "bg-secondary text-muted-foreground" };
    default:
      return { label: "Confirmed", cls: "bg-success/15 text-success" };
  }
}

function TodaysBookingsCard({ blocks, delay }: { blocks: { block: ScheduleBlock; court: string }[]; delay: number }) {
  return (
    <DashCard title="Today's Bookings" delay={delay} action={<CardLink href="/bookings">View All</CardLink>}>
      {blocks.length === 0 ? (
        <EmptyNote>No bookings today.</EmptyNote>
      ) : (
        <div className="overflow-x-auto">
          <table className="w-full min-w-[440px] text-left text-xs">
            <thead>
              <tr className="border-b border-border/60 text-[11px] text-muted-foreground">
                {["Time", "Court", "Customer", "Type", "Payment", "Status", "Actions"].map((h) => (
                  <th key={h} className="pb-2 pr-2 font-medium last:pr-0 last:text-right">
                    {h}
                  </th>
                ))}
              </tr>
            </thead>
            <tbody className="divide-y divide-border/50">
              {blocks.slice(0, 5).map(({ block, court }) => {
                const pay = paymentChip(block);
                const status = statusChip(block);
                return (
                  <tr key={block.id}>
                    <td className="py-2 pr-2 tabular-nums text-muted-foreground">{formatMinute(block.startMinute)}</td>
                    <td className="py-2 pr-2">{court}</td>
                    <td className="max-w-[7rem] truncate py-2 pr-2">{block.label}</td>
                    <td className="py-2 pr-2">
                      <span className={cn("rounded-md px-1.5 py-0.5 text-[11px] font-medium", TYPE_TAG[block.type])}>
                        {TYPE_LABEL[block.type]}
                      </span>
                    </td>
                    <td className="py-2 pr-2">
                      {pay ? (
                        <span className={cn("rounded-md px-1.5 py-0.5 text-[11px] font-medium", pay.cls)}>{pay.label}</span>
                      ) : (
                        <span className="text-muted-foreground">—</span>
                      )}
                    </td>
                    <td className="py-2 pr-2">
                      <span className={cn("rounded-md px-1.5 py-0.5 text-[11px] font-medium", status.cls)}>{status.label}</span>
                    </td>
                    <td className="py-2 text-right">
                      <Link
                        href="/bookings"
                        aria-label="Open bookings"
                        className="inline-flex text-muted-foreground hover:text-foreground"
                      >
                        <MoreHorizontal className="h-4 w-4" />
                      </Link>
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      )}
    </DashCard>
  );
}

function MembershipCard({ summary, delay }: { summary: DashboardSummary; delay: number }) {
  const m = summary.memberships;
  const rows: { icon: LucideIcon; tone: string; label: string; value: number }[] = [
    { icon: UserRoundCheck, tone: "bg-success/15 text-success", label: "Active Members", value: m.active },
    { icon: Hourglass, tone: "bg-warning/15 text-warning", label: "Expiring Soon", value: m.expiringSoon },
    { icon: UserPlus, tone: "bg-blue-500/15 text-blue-600 dark:text-blue-400", label: "New This Month", value: m.newThisMonth },
    { icon: UserRoundX, tone: "bg-destructive/15 text-destructive", label: "Expired", value: m.expired },
  ];
  return (
    <DashCard title="Membership" delay={delay} action={<CardLink href="/memberships">View Members</CardLink>}>
      <ul className="space-y-2.5">
        {rows.map(({ icon: Icon, tone, label, value }) => (
          <li key={label} className="flex items-center gap-2.5 text-xs">
            <span className={cn("flex h-8 w-8 shrink-0 items-center justify-center rounded-lg", tone)}>
              <Icon className="h-4 w-4" aria-hidden />
            </span>
            <span className="flex-1 truncate text-muted-foreground">{label}</span>
            <span className="text-sm font-semibold tabular-nums text-foreground">{value}</span>
          </li>
        ))}
      </ul>
    </DashCard>
  );
}

function AttentionCard({ summary, onGo, delay }: { summary: DashboardSummary; onGo: (href: string) => void; delay: number }) {
  const items = summary.attentionItems;
  return (
    <DashCard
      title="Attention Required"
      delay={delay}
      action={
        items.length > 0 ? (
          <span className="rounded-full bg-destructive px-1.5 py-0.5 text-[10px] font-semibold text-white">{items.length}</span>
        ) : undefined
      }
    >
      {items.length === 0 ? (
        <p className="py-4 text-xs text-success">You&apos;re all caught up. No immediate attention required.</p>
      ) : (
        <ul className="space-y-3">
          {items.map((item) => (
            <li key={item.id} className="flex items-start gap-2 text-xs">
              <TriangleAlert className="mt-0.5 h-3.5 w-3.5 shrink-0 text-warning" aria-hidden />
              <div className="min-w-0 flex-1 space-y-0.5">
                <p className="leading-snug text-foreground">{item.message}</p>
                {item.actionHref && item.actionLabel && (
                  <button
                    type="button"
                    onClick={() => onGo(item.actionHref!)}
                    className="flex items-center gap-1 text-[11px] font-medium text-primary hover:underline"
                  >
                    {item.actionLabel}
                    <ChevronRight className="h-3 w-3" aria-hidden />
                  </button>
                )}
              </div>
            </li>
          ))}
        </ul>
      )}
    </DashCard>
  );
}

export function OwnerDashboard({ ownerFirstName }: { ownerFirstName: string | null }) {
  const router = useRouter();
  const { data: facility, isLoading: facilityLoading } = useFacility();
  const activeFacilitySportId = useUiStore((s) => s.activeFacilitySportId);
  const [revenueMonthOffset, setRevenueMonthOffset] = useState(0);

  // Passing the already-fetched facility through means the summary query
  // doesn't need to look it up again itself, cutting a stage out of what was
  // otherwise a facility-fetch -> summary-fetch waterfall.
  const { data: summary, isLoading, isError, refetch } = useDashboardSummary(facility ?? null, {
    // null = the facility's first sport; the dashboard always shows exactly one.
    facilitySportId: activeFacilitySportId,
    preset: PRESET,
    revenueMonthOffset,
  });

  if (facilityLoading || isLoading) {
    return (
      <div className="space-y-3">
        <Skeleton className="h-24 w-full rounded-xl" />
        <div className="relative z-10 grid grid-cols-2 gap-3 lg:grid-cols-5">
          {Array.from({ length: 5 }).map((_, i) => (
            <Skeleton key={i} className="h-24 rounded-xl" />
          ))}
        </div>
        <Skeleton className="h-64 w-full rounded-xl" />
      </div>
    );
  }

  if (!facility) {
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

  const now = new Date();
  const nowMinute = now.getHours() * 60 + now.getMinutes();
  const isToday = true;
  const courts = summary.scheduleTimeline.courts;
  const courtRows = courtsNow(courts, nowMinute, isToday);
  const allBlocks = courts
    .flatMap((court) => court.blocks.map((block) => ({ block, court: court.courtName })))
    .sort((a, b) => a.block.startMinute - b.block.startMinute);
  const bookingBlocks = allBlocks.filter(({ block }) => block.type !== "SESSION");
  const upcomingCount = bookingBlocks.filter(({ block }) => block.startMinute > nowMinute).length;
  const occupied = courtRows.filter((r) => r.status === "live").length;
  const utilization = summary.kpis.utilizationPercent.value;

  const compare = COMPARE_LABEL[PRESET];
  const revenueTrend = trendText(summary.kpis.revenueInr, compare);

  return (
    <div className="space-y-3">
      {/* Hero: no card, no border. The artwork bleeds to the page edges under the
          top bar. The strip is 144px tall but the KPI row (z-10, pulled up by
          the negative bottom margin) starts at 96px, so the lower 48px runs
          behind the cards and only shows in the gaps, fading out. The 3:1
          artwork is 144px tall and lifted 48px, so the athlete's head sits near
          the top and her body disappears behind the cards, as in the design;
          it is offset so she lands ~65% across (~75% into the image:
          2.25 x 144px = 324px). One file per theme. */}
      <div className="relative -mx-4 -mt-4 -mb-[3.75rem] h-36 lg:-mx-6 lg:-mt-6">
        <div
          aria-hidden
          className="absolute inset-0 overflow-hidden bg-[linear-gradient(to_right,var(--light-page-bg)_0%,var(--light-page-bg)_45%,var(--hero-gradient-start)_72%,var(--hero-gradient-end)_100%)] [mask-image:linear-gradient(to_bottom,black_62%,transparent)] dark:bg-[linear-gradient(to_right,#020b1f,#020b1f,#031a1a)]"
        >
          <div
            className="pointer-events-none absolute -top-12 hidden h-36 aspect-[3/1] bg-cover bg-center bg-no-repeat [mask-image:linear-gradient(to_right,transparent,black_30%,black_80%,transparent)] md:block dark:md:hidden"
            style={{ backgroundImage: "url(/assets/Dashboard_Hero_Light_Mode.png)", left: "calc(65% - 324px)" }}
          />
          <div
            className="pointer-events-none absolute -top-12 hidden h-36 aspect-[3/1] bg-cover bg-center bg-no-repeat [mask-image:linear-gradient(to_right,transparent,black_30%,black_80%,transparent)] dark:md:block"
            style={{ backgroundImage: "url(/assets/Dashboard-Hero.png)", left: "calc(65% - 324px)" }}
          />
        </div>
        <div className="relative flex items-start justify-between gap-4 px-4 pt-5 lg:px-6">
          <div className="min-w-0">
            <h1 className="truncate text-[28px] font-semibold leading-tight text-foreground">
              {ownerFirstName ? `${greeting()}, ${ownerFirstName} 👋` : greeting()}
            </h1>
            <p className="truncate text-sm text-muted-foreground">
              Here&apos;s what&apos;s happening at {summary.facility.name || "your club"} today.
            </p>
          </div>
          <div className="hidden h-[4.5rem] w-[300px] shrink-0 flex-col justify-center lg:flex">
            <p className="text-[15px] font-semibold leading-snug text-foreground">
              Great clubs build
              <br />
              healthier communities.
            </p>
            <p className="mt-1 text-[10px] text-muted-foreground">More Play. More People. A Healthier Tomorrow.</p>
          </div>
        </div>
      </div>

      {/* KPI row */}
      <div className="grid grid-cols-2 gap-3 lg:grid-cols-5">
        <DashKpi
          delay={0}
          icon={BadgeIndianRupee}
          tone="bg-success/15 text-success"
          label={isToday ? "Today's Revenue" : "Revenue"}
          value={formatCurrencyINR(summary.kpis.revenueInr.value)}
          sub={revenueTrend?.text}
          subClass={revenueTrend?.cls}
        />
        <DashKpi
          delay={60}
          icon={CalendarClock}
          tone="bg-blue-500/15 text-blue-600 dark:text-blue-400"
          label="Total Bookings"
          value={String(bookingBlocks.length)}
          sub={isToday ? `${upcomingCount} upcoming` : undefined}
          subClass="text-blue-600 dark:text-blue-400"
          href="/bookings"
        />
        <DashKpi
          delay={120}
          icon={Gauge}
          tone="bg-purple-500/15 text-purple-600 dark:text-purple-400"
          label="Courts Occupied"
          value={`${occupied} / ${courts.length}`}
          sub={`${utilization}% utilization`}
        >
          <div className="h-1 overflow-hidden rounded-full bg-secondary">
            <div
              className="h-full rounded-full bg-purple-500"
              style={{ width: `${Math.min(Math.max(utilization, 0), 100)}%` }}
            />
          </div>
        </DashKpi>
        <DashKpi
          delay={180}
          icon={Users}
          tone="bg-success/15 text-success"
          label="Active Members"
          value={String(summary.kpis.activeMemberships.value)}
          sub={summary.memberships.expiringSoon > 0 ? `${summary.memberships.expiringSoon} expiring soon` : undefined}
          subClass="text-warning"
          href="/memberships"
        />
        <DashKpi
          delay={240}
          icon={Dumbbell}
          tone="bg-warning/15 text-warning"
          label="Coaching Sessions"
          value="—"
          sub="Open coaching"
          subClass="text-warning"
          href="/coaching/sessions"
        />
      </div>

      {/* Court activity | Court status | Quick actions */}
      <div className={ROW_GRID}>
        <CourtActivityCard rows={courtRows} delay={300} />
        <CourtStatusCard rows={courtRows} delay={340} />
        <QuickActionsCard onGo={(href) => router.push(href)} delay={380} />
      </div>

      {/* Bookings | Membership | Attention */}
      <div className={ROW_GRID}>
        <TodaysBookingsCard blocks={allBlocks} delay={420} />
        <MembershipCard summary={summary} delay={460} />
        <AttentionCard summary={summary} onGo={(href) => router.push(href)} delay={500} />
      </div>

      {/* Revenue | Recent activity | Upcoming */}
      <div className={ROW_GRID}>
        <DashCard
          title="Revenue Overview"
          delay={540}
          action={
            <select
              aria-label="Revenue month"
              value={revenueMonthOffset}
              onChange={(e) => setRevenueMonthOffset(Number(e.target.value))}
              className="h-7 rounded-md border border-input bg-secondary/60 px-2 text-[11px]"
            >
              {MONTH_OPTIONS.map((opt) => (
                <option key={opt.offset} value={opt.offset}>
                  {opt.label}
                </option>
              ))}
            </select>
          }
        >
          <RevenueOverviewPanel overview={summary.revenueOverview} />
        </DashCard>
        <DashCard title="Recent Activity" delay={580}>
          <EmptyNote>Activity feed isn&apos;t tracked yet.</EmptyNote>
        </DashCard>
        <DashCard title="Upcoming" delay={620}>
          <div className="flex flex-col items-center gap-2 py-6 text-center">
            <CalendarCheck2 className="h-5 w-5 text-muted-foreground" aria-hidden />
            <p className="text-xs text-muted-foreground">No upcoming events yet.</p>
            <CardLink href="/coaching/schedule">Coaching schedule</CardLink>
          </div>
        </DashCard>
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
  const H = 110;
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

  const xTickCount = Math.min(4, n);
  const xTickIdx = Array.from({ length: xTickCount }, (_, k) =>
    xTickCount <= 1 ? 0 : Math.round((k / (xTickCount - 1)) * (n - 1)),
  );

  return (
    <div className="space-y-1">
      <div className="flex gap-2">
        <div className="flex w-10 shrink-0 flex-col justify-between text-right text-[10px] text-muted-foreground" style={{ height: H }}>
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
      <div className="relative ml-12 h-4">
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
    <div className="space-y-3">
      <div className="flex flex-wrap items-end justify-between gap-2">
        <div>
          <p className="text-2xl font-semibold leading-tight text-foreground">{formatCurrencyINR(overview.totalInr)}</p>
          <p className="text-[11px] text-muted-foreground">Total Revenue · {overview.monthLabel}</p>
        </div>
        {overview.changePercent !== null && (
          <span
            className={cn(
              "text-[11px] font-medium",
              up && "text-success",
              down && "text-destructive",
              !up && !down && "text-muted-foreground",
            )}
          >
            {up ? "↑" : down ? "↓" : "→"} {Math.abs(overview.changePercent).toFixed(1)}% vs last month
          </span>
        )}
      </div>
      <div className="grid grid-cols-1 gap-3 sm:grid-cols-[minmax(0,1fr)_minmax(0,0.9fr)]">
        {/* Keyed on the month so paging replays the draw-in. */}
        <RevenueOverviewChart key={overview.monthLabel} points={overview.points} />
        <RevenueBreakdownList segments={overview.breakdown} total={overview.totalInr} />
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

function RevenueBreakdownList({
  segments,
  total,
}: {
  segments: RevenueOverviewData["breakdown"];
  total: number;
}) {
  return (
    <ul className="min-w-0 space-y-2 self-center">
      {segments.map((seg) => {
        const pct = total > 0 ? Math.round((seg.amountInr / total) * 100) : 0;
        return (
          <li key={seg.key} className="flex items-center justify-between gap-2 text-[11px]">
            <span className="flex min-w-0 items-center gap-1.5">
              <span className="h-2 w-2 shrink-0 rounded-full" style={{ backgroundColor: BREAKDOWN_COLORS[seg.key] }} />
              <span className="truncate text-foreground">{seg.label}</span>
            </span>
            <span className="flex shrink-0 items-center gap-2">
              <span className="text-muted-foreground">{seg.unavailable ? "—" : formatCurrencyINR(seg.amountInr)}</span>
              <span className="w-7 text-right font-medium text-foreground">{pct}%</span>
            </span>
          </li>
        );
      })}
    </ul>
  );
}
