"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { CalendarRange, CheckCircle2, CheckCheck, Clock, Download, Plus, TrendingUp, Wallet, XCircle } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Skeleton } from "@/components/ui/skeleton";
import { cn } from "@/lib/utils";
import { StatCard } from "@/components/shared/stat-card";
import { DateRangePicker } from "@/features/bookings/components/date-range-picker";
import { GuestBookingActions } from "@/features/bookings/components/guest-booking-actions";
import { ShareBookingLink } from "@/features/public-booking/components/share-booking-link";
import { getFacilityService } from "@/services/facility";
import { getSportsService } from "@/services/sports";
import { getPlayingAreasService } from "@/services/playing-areas";
import { getBookingService } from "@/services/bookings";
import { formatCurrency } from "@/features/pricing/money";
import type {
  BookingStatus,
  GuestBookingRow,
  GuestBookingsSummary,
  PaymentStatus,
} from "@/features/bookings/types";
import type { FacilitySport, Sport } from "@/features/sports-setup/types";
import type { PlayingArea } from "@/features/courts-setup/types";

const PER_PAGE = 10;
const STATUS_OPTIONS: { value: BookingStatus | ""; label: string }[] = [
  { value: "", label: "All Status" },
  { value: "confirmed", label: "Confirmed" },
  { value: "completed", label: "Completed" },
  { value: "cancelled", label: "Cancelled" },
  { value: "pending", label: "Pending" },
];
const PAYMENT_OPTIONS: { value: PaymentStatus | ""; label: string }[] = [
  { value: "", label: "All Payment Status" },
  { value: "PAID", label: "Paid" },
  { value: "PENDING", label: "Pending" },
  { value: "REFUNDED", label: "Refunded" },
];
const selectCls = "h-9 rounded-md border border-input bg-secondary/60 px-2 text-sm";

function iso(d: Date): string {
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
}
function fmtDate(d: string): string {
  return new Date(d).toLocaleDateString("en-IN", { day: "2-digit", month: "short", year: "numeric" });
}
function fmtTime(d: string): string {
  return new Date(d).toLocaleTimeString("en-IN", { hour: "numeric", minute: "2-digit", hour12: true });
}
function money(minor: number | null | undefined, currency = "INR"): string {
  return minor == null ? "—" : formatCurrency(minor, currency);
}

function statusBadge(s: BookingStatus) {
  if (s === "confirmed") return <Badge variant="success">Confirmed</Badge>;
  if (s === "completed") return <Badge variant="secondary">Completed</Badge>;
  if (s === "cancelled") return <Badge variant="destructive">Cancelled</Badge>;
  return <Badge variant="warning">Pending</Badge>;
}
function paymentBadge(s: PaymentStatus) {
  if (s === "PAID") return <Badge variant="success">Paid</Badge>;
  if (s === "REFUNDED") return <Badge variant="destructive">Refunded</Badge>;
  return <Badge variant="warning">Pending</Badge>;
}

function StatusDonut({ summary }: { summary: GuestBookingsSummary }) {
  const size = 128;
  const stroke = 16;
  const r = (size - stroke) / 2;
  const circ = 2 * Math.PI * r;
  const segs = [
    { value: summary.confirmed, color: "#00D084", label: "Confirmed" },
    { value: summary.completed, color: "#5B6CFF", label: "Completed" },
    { value: summary.cancelled, color: "#FF4D67", label: "Cancelled" },
    { value: summary.pending, color: "#FFB020", label: "Pending" },
  ];
  const total = Math.max(segs.reduce((a, s) => a + s.value, 0), 1);
  let offset = 0;
  return (
    <div className="flex items-center gap-4">
      <div className="relative shrink-0" style={{ width: size, height: size }}>
        <svg width={size} height={size} viewBox={`0 0 ${size} ${size}`} className="-rotate-90">
          <circle cx={size / 2} cy={size / 2} r={r} fill="none" stroke="var(--border,#e5e7eb)" strokeWidth={stroke} />
          {segs.map((s, i) => {
            const len = (s.value / total) * circ;
            // Shifting the dash offset by the arc's own length hides it
            // entirely, so animating back to -offset sweeps it open.
            const el = (
              <circle
                key={i}
                className="donut-sweep"
                cx={size / 2}
                cy={size / 2}
                r={r}
                fill="none"
                stroke={s.color}
                strokeWidth={stroke}
                strokeDasharray={`${len} ${circ - len}`}
                strokeDashoffset={-offset}
                style={
                  {
                    "--dash-from": -offset + len,
                    "--dash-to": -offset,
                    "--sweep-delay": `${520 + i * 110}ms`,
                  } as React.CSSProperties
                }
              />
            );
            offset += len;
            return el;
          })}
        </svg>
        <div className="absolute inset-0 flex flex-col items-center justify-center">
          <span className="text-xl font-semibold">{summary.total}</span>
          <span className="text-[10px] text-muted-foreground">Total</span>
        </div>
      </div>
      <ul className="space-y-1.5 text-xs">
        {segs.map((s) => (
          <li key={s.label} className="flex items-center gap-2">
            <span className="h-2.5 w-2.5 rounded-full" style={{ backgroundColor: s.color }} />
            <span className="text-muted-foreground">{s.label}</span>
            <span className="ml-auto font-medium text-foreground">
              {s.value} ({Math.round((s.value / total) * 100)}%)
            </span>
          </li>
        ))}
      </ul>
    </div>
  );
}

function Sparkline({ points }: { points: number[] }) {
  if (points.length < 2) return <div className="h-16 rounded bg-secondary/40" />;
  const max = Math.max(...points, 1);
  const w = 240;
  const h = 56;
  const step = w / (points.length - 1);
  const d = points.map((p, i) => `${i * step},${h - (p / max) * h}`).join(" ");
  return (
    <svg width="100%" height={h} viewBox={`0 0 ${w} ${h}`} preserveAspectRatio="none" className="text-success">
      {/* pathLength=1 normalises the dash maths, so the trend draws itself
          left-to-right without measuring the real path. */}
      <polyline
        className="chart-line-draw"
        points={d}
        fill="none"
        stroke="currentColor"
        strokeWidth={2}
        vectorEffect="non-scaling-stroke"
        pathLength={1}
        strokeDasharray={1}
        style={{ "--draw-delay": "600ms" } as React.CSSProperties}
      />
    </svg>
  );
}

export function GuestBookingsDashboard() {
  const router = useRouter();
  const [facilityId, setFacilityId] = useState<string | null>(null);
  const [facilityName, setFacilityName] = useState("");
  const [currency, setCurrency] = useState("INR");

  const [summary, setSummary] = useState<GuestBookingsSummary | null>(null);
  const [rows, setRows] = useState<GuestBookingRow[] | null>(null);
  const [totalCount, setTotalCount] = useState(0);

  const [search, setSearch] = useState("");
  const [debounced, setDebounced] = useState("");
  const [sportId, setSportId] = useState("");
  const [courtId, setCourtId] = useState("");
  const [status, setStatus] = useState<BookingStatus | "">("");
  const [payment, setPayment] = useState<PaymentStatus | "">("");
  const [from, setFrom] = useState(() => {
    const d = new Date();
    d.setDate(d.getDate() - 29);
    return iso(d);
  });
  const [to, setTo] = useState(() => iso(new Date()));
  const [page, setPage] = useState(1);

  const [facilitySports, setFacilitySports] = useState<FacilitySport[]>([]);
  const [sports, setSports] = useState<Sport[]>([]);
  const [areas, setAreas] = useState<PlayingArea[]>([]);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      const f = await getFacilityService().getFacility();
      if (cancelled || !f) return;
      setFacilityId(f.id);
      setFacilityName(f.name);
      const [fs, allSports, pa] = await Promise.all([
        getSportsService().getFacilitySports(f.id),
        getSportsService().getActiveSports(),
        getPlayingAreasService().getPlayingAreas(f.id),
      ]);
      if (cancelled) return;
      setFacilitySports(fs.filter((x) => x.enabled));
      setSports(allSports);
      setAreas(pa.filter((a) => !a.archived));
    })();
    return () => {
      cancelled = true;
    };
  }, []);

  useEffect(() => {
    const t = setTimeout(() => setDebounced(search), 300);
    return () => clearTimeout(t);
  }, [search]);

  useEffect(() => {
    setPage(1);
  }, [debounced, sportId, courtId, status, payment, from, to]);

  const reload = useCallback(async () => {
    if (!facilityId) return;
    setRows(null);
    const svc = getBookingService();
    const [sum, list] = await Promise.all([
      svc.getGuestBookingsSummary(facilityId, from, to),
      svc.listGuestBookings(facilityId, {
        search: debounced || undefined,
        facilitySportId: sportId || undefined,
        courtId: courtId || undefined,
        status: status || undefined,
        paymentStatus: payment || undefined,
        from,
        to,
        page,
        perPage: PER_PAGE,
      }),
    ]);
    setSummary(sum);
    setRows(list.rows);
    setTotalCount(list.totalCount);
    if (list.rows[0]?.currency) setCurrency(list.rows[0].currency);
  }, [facilityId, debounced, sportId, courtId, status, payment, from, to, page]);

  useEffect(() => {
    reload();
  }, [reload]);

  const totalPages = Math.max(1, Math.ceil(totalCount / PER_PAGE));
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

  const pct = (n: number) => (summary && summary.total ? `${Math.round((n / summary.total) * 100)}% of total` : "—");

  return (
    <div className="space-y-6">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <h1 className="text-xl font-semibold">Guest Bookings</h1>
          <p className="text-sm text-muted-foreground">Manage all guest court bookings and their status.</p>
        </div>
        <div className="flex flex-wrap items-center gap-2">
          <ShareBookingLink facilityId={facilityId} />
          <Button type="button" size="sm" onClick={() => router.push("/bookings/new")}>
            <Plus className="mr-1.5 h-4 w-4" /> New Guest Booking
          </Button>
        </div>
      </div>

      {/* KPIs */}
      <div className="grid grid-cols-2 gap-4 md:grid-cols-3 xl:grid-cols-6">
        {summary ? (
          <>
            <StatCard
              icon={CalendarRange}
              label="Total Bookings"
              value={String(summary.total)}
              countTo={summary.total}
              format={(v) => String(v)}
              accent="#5B6CFF"
              index={0}
              hint={
                summary.totalChangePct == null
                  ? undefined
                  : `${summary.totalChangePct >= 0 ? "+" : ""}${summary.totalChangePct}% vs last period`
              }
              hintClass={cn("font-medium", summary.totalChangePct != null && (summary.totalChangePct >= 0 ? "text-success" : "text-destructive"))}
            />
            <StatCard icon={CheckCircle2} label="Confirmed" value={String(summary.confirmed)} countTo={summary.confirmed} format={(v) => String(v)} accent="#00D084" index={1} hint={pct(summary.confirmed)} />
            <StatCard icon={CheckCheck} label="Completed" value={String(summary.completed)} countTo={summary.completed} format={(v) => String(v)} accent="#8B5CF6" index={2} hint={pct(summary.completed)} />
            <StatCard icon={XCircle} label="Cancelled" value={String(summary.cancelled)} countTo={summary.cancelled} format={(v) => String(v)} accent="#FF4D67" index={3} hint={pct(summary.cancelled)} />
            <StatCard icon={Clock} label="Pending" value={String(summary.pending)} countTo={summary.pending} format={(v) => String(v)} accent="#FFB020" index={4} hint={pct(summary.pending)} />
            <StatCard
              icon={Wallet}
              label="Total Revenue"
              value={money(summary.totalRevenueMinor, currency)}
              countTo={summary.totalRevenueMinor}
              format={(v) => money(v, currency)}
              accent="#00D084"
              index={5}
              hint="From guest bookings"
            />
          </>
        ) : (
          Array.from({ length: 6 }).map((_, i) => <Skeleton key={i} className="h-24 rounded-xl" />)
        )}
      </div>

      <div className="space-y-4">
        <div className="min-w-0 space-y-4">
          {/* Toolbar */}
          <div className="flex flex-wrap items-center gap-2">
            <Input
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              placeholder="Search by guest name, phone, booking ID…"
              className="h-9 w-full max-w-xs"
            />
            <select aria-label="Sport" value={sportId} onChange={(e) => { setSportId(e.target.value); setCourtId(""); }} className={selectCls}>
              <option value="">All Sports</option>
              {facilitySports.map((fs) => {
                const s = sports.find((sp) => sp.id === fs.sportId);
                return <option key={fs.id} value={fs.id}>{fs.customSportName ?? s?.name ?? "Sport"}</option>;
              })}
            </select>
            <select aria-label="Court" value={courtId} onChange={(e) => setCourtId(e.target.value)} className={selectCls}>
              <option value="">All Courts</option>
              {courtsForSport.map((a) => <option key={a.id} value={a.id}>{a.name}</option>)}
            </select>
            <select aria-label="Status" value={status} onChange={(e) => setStatus(e.target.value as BookingStatus | "")} className={selectCls}>
              {STATUS_OPTIONS.map((o) => <option key={o.value} value={o.value}>{o.label}</option>)}
            </select>
            <select aria-label="Payment" value={payment} onChange={(e) => setPayment(e.target.value as PaymentStatus | "")} className={selectCls}>
              {PAYMENT_OPTIONS.map((o) => <option key={o.value} value={o.value}>{o.label}</option>)}
            </select>
            <DateRangePicker
              from={from}
              to={to}
              onChange={(f, t) => {
                setFrom(f);
                setTo(t);
              }}
            />
            <Button type="button" variant="outline" size="sm" onClick={exportCsv}>
              <Download className="mr-1.5 h-4 w-4" /> Export
            </Button>
          </div>

          {/* Table */}
          <Card className="stat-enter overflow-hidden p-0" style={{ "--stat-delay": "420ms" } as React.CSSProperties}>
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead className="border-b border-border text-left text-xs text-muted-foreground">
                  <tr>
                    <th className="px-4 py-3 font-medium">Booking ID</th>
                    <th className="px-4 py-3 font-medium">Guest</th>
                    <th className="px-4 py-3 font-medium">Sport / Court</th>
                    <th className="px-4 py-3 font-medium">Date &amp; Time</th>
                    <th className="px-4 py-3 font-medium">Players</th>
                    <th className="px-4 py-3 font-medium">Amount</th>
                    <th className="px-4 py-3 font-medium">Payment</th>
                    <th className="px-4 py-3 font-medium">Status</th>
                    <th className="px-4 py-3 text-right font-medium">Actions</th>
                  </tr>
                </thead>
                <tbody>
                  {rows === null ? (
                    Array.from({ length: 6 }).map((_, i) => (
                      <tr key={i} className="border-b border-border/60">
                        <td colSpan={9} className="px-4 py-3"><Skeleton className="h-8 w-full" /></td>
                      </tr>
                    ))
                  ) : rows.length === 0 ? (
                    <tr>
                      <td colSpan={9} className="px-4 py-10 text-center text-sm text-muted-foreground">No guest bookings match these filters.</td>
                    </tr>
                  ) : (
                    rows.map((r) => {
                      const hours = (new Date(r.endTime).getTime() - new Date(r.startTime).getTime()) / 3_600_000;
                      const unit = r.amountMinor != null && hours > 0 ? Math.round(r.amountMinor / hours) : null;
                      return (
                        <tr key={r.bookingId} className="border-b border-border/60 last:border-b-0">
                          <td className="px-4 py-3">
                            <p className="font-medium text-foreground">{r.code}</p>
                            <p className="text-xs text-muted-foreground">{fmtDate(r.startTime)}</p>
                          </td>
                          <td className="px-4 py-3">
                            <p className="font-medium text-foreground">{r.guestName}</p>
                            {r.guestPhone && <p className="text-xs text-muted-foreground">{r.guestPhone}</p>}
                          </td>
                          <td className="px-4 py-3">
                            <p>{r.sportName ?? "—"}</p>
                            <p className="text-xs text-muted-foreground">{r.courtName}</p>
                          </td>
                          <td className="px-4 py-3">
                            <p>{fmtDate(r.startTime)}</p>
                            <p className="text-xs text-muted-foreground">{fmtTime(r.startTime)} - {fmtTime(r.endTime)}</p>
                          </td>
                          <td className="px-4 py-3 text-muted-foreground">{r.partySize}</td>
                          <td className="px-4 py-3">
                            <p className="font-medium text-foreground">{money(r.amountMinor, r.currency)}</p>
                            {unit != null && (
                              <p className="text-xs text-muted-foreground">
                                {money(unit, r.currency)} × {hours % 1 === 0 ? hours : hours.toFixed(1)}h
                              </p>
                            )}
                          </td>
                          <td className="px-4 py-3">
                            <div className="flex flex-col gap-0.5">
                              {paymentBadge(r.paymentStatus)}
                              {r.paymentMethod && <span className="text-xs text-muted-foreground">{r.paymentMethod}</span>}
                            </div>
                          </td>
                          <td className="px-4 py-3">{statusBadge(r.status)}</td>
                          <td className="px-4 py-3 text-right">
                            <GuestBookingActions row={r} facilityId={facilityId} facilityName={facilityName} onChanged={reload} />
                          </td>
                        </tr>
                      );
                    })
                  )}
                </tbody>
              </table>
            </div>
            <div className="flex flex-wrap items-center justify-between gap-2 border-t border-border px-4 py-3 text-xs text-muted-foreground">
              <span>
                {totalCount === 0
                  ? "No bookings"
                  : `Showing ${(page - 1) * PER_PAGE + 1} to ${Math.min(page * PER_PAGE, totalCount)} of ${totalCount} bookings`}
              </span>
              <div className="flex items-center gap-1">
                <Button type="button" variant="outline" size="sm" disabled={page <= 1} onClick={() => setPage((p) => p - 1)}>Prev</Button>
                <span className="px-2">Page {page} / {totalPages}</span>
                <Button type="button" variant="outline" size="sm" disabled={page >= totalPages} onClick={() => setPage((p) => p + 1)}>Next</Button>
              </div>
            </div>
          </Card>
        </div>

        {/* Overview — below the table, side by side */}
        <div className="grid gap-4 lg:grid-cols-2">
          <Card className="stat-enter p-4" style={{ "--stat-delay": "480ms" } as React.CSSProperties}>
            <p className="text-sm font-semibold">Booking Overview</p>
            <div className="mt-3">
              {summary ? <StatusDonut summary={summary} /> : <Skeleton className="h-32 w-full rounded-lg" />}
            </div>
          </Card>

          <Card className="stat-enter p-4" style={{ "--stat-delay": "540ms" } as React.CSSProperties}>
            <p className="text-sm font-semibold">Revenue Overview</p>
            {summary ? (
              <>
                <p className="mt-2 text-xl font-semibold text-success">{money(summary.totalRevenueMinor, currency)}</p>
                {summary.revenueChangePct != null && (
                  <p className={cn("flex items-center gap-1 text-xs", summary.revenueChangePct >= 0 ? "text-success" : "text-destructive")}>
                    <TrendingUp className="h-3 w-3" />
                    {summary.revenueChangePct >= 0 ? "+" : ""}
                    {summary.revenueChangePct}% vs last period
                  </p>
                )}
                <div className="mt-3">
                  <Sparkline points={summary.trend.map((t) => t.amountMinor)} />
                </div>
                <div className="mt-3 grid grid-cols-2 gap-3 text-xs">
                  <div>
                    <p className="text-muted-foreground">Average per booking</p>
                    <p className="font-medium text-foreground">{money(summary.avgPerBookingMinor, currency)}</p>
                  </div>
                  <div>
                    <p className="text-muted-foreground">Highest booking</p>
                    <p className="font-medium text-foreground">{money(summary.highestBookingMinor, currency)}</p>
                  </div>
                </div>
              </>
            ) : (
              <Skeleton className="mt-2 h-32 w-full rounded-lg" />
            )}
          </Card>
        </div>
      </div>
    </div>
  );
}