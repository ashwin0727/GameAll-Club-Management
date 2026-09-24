"use client";

import { useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { ChevronLeft, ChevronRight, Download, MoreHorizontal, Pencil, Search, Eye } from "lucide-react";
import { Card } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { SelectField } from "@/components/shared/select-field";
import { Avatar, AvatarFallback } from "@/components/ui/avatar";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { cn } from "@/lib/utils";
import { bucketForRow, rowStatus, type PlanBucket, type RowStatus } from "@/features/memberships/dashboard-stats";
import { formatClock, formatDayRange } from "@/features/memberships/slot-format";
import type { MembershipListRow } from "@/features/memberships/types";

type Tab = "all" | "active" | "expiring" | "inactive";
type Sort = "recent" | "name" | "ending";

const PAGE_SIZES = [8, 15, 25, 50];

const SORTS: { value: Sort; label: string }[] = [
  { value: "recent", label: "Recent First" },
  { value: "name", label: "Name (A–Z)" },
  { value: "ending", label: "Ending Soonest" },
];

const STATUS_FILTERS: { value: "" | RowStatus; label: string }[] = [
  { value: "", label: "All Status" },
  { value: "active", label: "Active" },
  { value: "expiring", label: "Expiring Soon" },
  { value: "payment_incomplete", label: "Payment Incomplete" },
  { value: "inactive", label: "Inactive" },
];

const PLAN_TONES: Record<PlanBucket, string> = {
  Monthly: "bg-success/15 text-success",
  "3 Months": "bg-blue-500/15 text-blue-600 dark:text-blue-400",
  "6 Months": "bg-warning/15 text-warning",
  "1 Year": "bg-purple-500/15 text-purple-600 dark:text-purple-400",
  Others: "bg-muted text-muted-foreground",
};

const STATUS_TONES: Record<RowStatus, { label: string; tone: string }> = {
  active: { label: "Active", tone: "bg-success/15 text-success" },
  expiring: { label: "Expiring Soon", tone: "bg-warning/15 text-warning" },
  payment_incomplete: { label: "Payment Incomplete", tone: "bg-warning/15 text-warning" },
  inactive: { label: "Inactive", tone: "bg-destructive/15 text-destructive" },
};

const CONTROL =
  "h-9 rounded-lg border border-input bg-card px-3 text-sm outline-none transition-colors hover:border-foreground/30 focus-visible:border-foreground/40";

function inr(v: number): string {
  return `₹${v.toLocaleString("en-IN")}`;
}
function fmtDate(iso: string): string {
  return new Date(iso).toLocaleDateString("en-IN", { day: "2-digit", month: "short", year: "numeric" });
}
function initials(name: string): string {
  return name.split(" ").filter(Boolean).slice(0, 2).map((p) => p[0]!.toUpperCase()).join("");
}
function matches(row: MembershipListRow, q: string): boolean {
  const needle = q.trim().toLowerCase();
  if (!needle) return true;
  return (
    row.memberName.toLowerCase().includes(needle) ||
    row.memberPhone.includes(needle) ||
    (row.memberEmail ?? "").toLowerCase().includes(needle)
  );
}

function Pill({ tone, children }: { tone: string; children: React.ReactNode }) {
  return (
    <span className={cn("inline-flex items-center gap-1.5 whitespace-nowrap rounded-full px-2.5 py-1 text-xs font-medium", tone)}>
      {children}
    </span>
  );
}

/** Comma-separated values, with anything containing a comma or quote escaped for a CSV cell. */
function csvCell(v: string | number): string {
  const s = String(v);
  return /[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
}

/**
 * The members list on the Membership Dashboard: status tabs with counts, a search / plan /
 * status / sort toolbar, the table itself, and paging along the bottom.
 */
export function MembershipListTable({ rows }: { rows: MembershipListRow[] | undefined }) {
  const router = useRouter();
  const now = useMemo(() => new Date(), []);

  const [tab, setTab] = useState<Tab>("all");
  const [search, setSearch] = useState("");
  const [plan, setPlan] = useState("");
  const [status, setStatus] = useState<"" | RowStatus>("");
  const [sort, setSort] = useState<Sort>("recent");
  const [page, setPage] = useState(1);
  const [perPage, setPerPage] = useState(PAGE_SIZES[0]!);
  const [selected, setSelected] = useState<Set<string>>(new Set());

  // Kept stable so the memos below don't recompute on every render.
  const all = useMemo(() => rows ?? [], [rows]);
  const counts = useMemo(() => {
    const byStatus = all.map((r) => rowStatus(r, now));
    return {
      all: all.length,
      active: byStatus.filter((s) => s === "active").length,
      expiring: byStatus.filter((s) => s === "expiring").length,
      inactive: byStatus.filter((s) => s === "inactive").length,
    };
  }, [all, now]);

  const plans = useMemo(() => [...new Set(all.map((r) => r.planName))].sort((a, b) => a.localeCompare(b)), [all]);

  const filtered = useMemo(() => {
    const list = all.filter((r) => {
      const s = rowStatus(r, now);
      if (tab !== "all" && s !== tab) return false;
      if (status && s !== status) return false;
      if (plan && r.planName !== plan) return false;
      return matches(r, search);
    });
    return [...list].sort((a, b) => {
      if (sort === "name") return a.memberName.localeCompare(b.memberName);
      if (sort === "ending") return a.endDate.localeCompare(b.endDate);
      return b.startDate.localeCompare(a.startDate);
    });
  }, [all, tab, status, plan, search, sort, now]);

  useEffect(() => {
    setPage(1);
  }, [tab, search, plan, status, sort, perPage]);

  const total = filtered.length;
  const pages = Math.max(1, Math.ceil(total / perPage));
  const safePage = Math.min(page, pages);
  const pageRows = filtered.slice((safePage - 1) * perPage, safePage * perPage);
  const from = total === 0 ? 0 : (safePage - 1) * perPage + 1;
  const to = Math.min(safePage * perPage, total);

  const pageAllSelected = pageRows.length > 0 && pageRows.every((r) => selected.has(r.membershipId));
  const chosen = filtered.filter((r) => selected.has(r.membershipId));

  function toggle(id: string) {
    setSelected((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  }

  /** Downloads the given rows as a CSV the club can open in a spreadsheet. */
  function exportCsv(list: MembershipListRow[]) {
    const header = ["Member", "Phone", "Email", "Plan", "Fee (INR)", "Schedule", "Court", "Start Date", "End Date", "Status"];
    const body = list.map((r) =>
      [
        r.memberName,
        r.memberPhone,
        r.memberEmail ?? "",
        r.planName,
        r.monthlyPriceInr,
        r.slot ? `${formatDayRange(r.slot.daysOfWeek)} ${formatClock(r.slot.startTime)}–${formatClock(r.slot.endTime)}` : "",
        r.slot?.courtName ?? "",
        r.startDate,
        r.endDate,
        STATUS_TONES[rowStatus(r, now)].label,
      ].map(csvCell).join(","),
    );
    const blob = new Blob([[header.join(","), ...body].join("\n")], { type: "text/csv;charset=utf-8" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = `members-${new Date().toISOString().slice(0, 10)}.csv`;
    a.click();
    URL.revokeObjectURL(url);
  }

  const tabs: { key: Tab; label: string; count: number }[] = [
    { key: "all", label: "All Members", count: counts.all },
    { key: "active", label: "Active", count: counts.active },
    { key: "expiring", label: "Expiring Soon", count: counts.expiring },
    { key: "inactive", label: "Inactive", count: counts.inactive },
  ];

  if (!rows) {
    return (
      <Card className="stat-enter space-y-4 rounded-xl p-4" style={{ "--stat-delay": "380ms" } as React.CSSProperties}>
        <Skeleton className="h-9 w-72" />
        <Skeleton className="h-9 w-full" />
        <Skeleton className="h-80 w-full" />
      </Card>
    );
  }

  return (
    <Card className="stat-enter overflow-hidden rounded-xl p-0" style={{ "--stat-delay": "380ms" } as React.CSSProperties}>
      <div className="flex flex-wrap items-center justify-between gap-3 p-4">
        <div className="flex flex-wrap gap-2">
          {tabs.map((t) => (
            <button
              key={t.key}
              type="button"
              onClick={() => setTab(t.key)}
              className={cn(
                "flex h-9 items-center gap-2 whitespace-nowrap rounded-lg border px-3 text-sm transition-colors",
                tab === t.key
                  ? "border-[#0B7A55] bg-success/10 font-semibold text-[#0B7A55]"
                  : "border-input bg-card text-muted-foreground hover:bg-accent",
              )}
            >
              {t.label}
              <span
                className={cn(
                  "rounded-full px-1.5 py-0.5 text-[11px] font-medium tabular-nums",
                  tab === t.key ? "bg-success/20 text-[#0B7A55]" : "bg-muted text-muted-foreground",
                )}
              >
                {t.count}
              </span>
            </button>
          ))}
        </div>

        <div className="flex items-center gap-2">
          <DropdownMenu>
            <DropdownMenuTrigger asChild>
              <button type="button" className={cn(CONTROL, "flex items-center gap-2 font-medium hover:bg-accent")}>
                Bulk Actions
                <span className="text-muted-foreground">▾</span>
              </button>
            </DropdownMenuTrigger>
            <DropdownMenuContent align="end" className="w-56">
              <DropdownMenuItem disabled={chosen.length === 0} onClick={() => exportCsv(chosen)}>
                <Download className="mr-2 h-4 w-4" />
                Export selected ({chosen.length})
              </DropdownMenuItem>
              <DropdownMenuItem disabled={chosen.length === 0} onClick={() => setSelected(new Set())}>
                Clear selection
              </DropdownMenuItem>
            </DropdownMenuContent>
          </DropdownMenu>

          <button
            type="button"
            onClick={() => exportCsv(filtered)}
            className={cn(CONTROL, "flex items-center gap-2 font-medium hover:bg-accent")}
          >
            <Download className="h-4 w-4" aria-hidden />
            Export
          </button>
        </div>
      </div>

      <div className="flex flex-wrap items-end gap-3 px-4 pb-4">
        <div className="relative min-w-[240px] flex-1">
          <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" aria-hidden />
          <input
            type="text"
            aria-label="Search members"
            placeholder="Search by name, phone or email..."
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            className={cn(CONTROL, "w-full pl-9")}
          />
        </div>

        <div className="space-y-1">
          <p className="text-xs text-muted-foreground">Membership Plan</p>
          <SelectField
            wrapperClassName="w-[170px]"
            ariaLabel="Membership plan"
            value={plan}
            onValueChange={setPlan}
            options={[{ value: "", label: "All Plans" }, ...plans.map((p) => ({ value: p, label: p }))]}
            className={CONTROL}
          />
        </div>

        <div className="space-y-1">
          <p className="text-xs text-muted-foreground">Status</p>
          <SelectField
            wrapperClassName="w-[170px]"
            ariaLabel="Status"
            value={status}
            onValueChange={(v) => setStatus(v as "" | RowStatus)}
            options={STATUS_FILTERS}
            className={CONTROL}
          />
        </div>

        <div className="space-y-1">
          <p className="text-xs text-muted-foreground">Sort by</p>
          <SelectField
            wrapperClassName="w-[170px]"
            ariaLabel="Sort by"
            value={sort}
            onValueChange={(v) => setSort(v as Sort)}
            options={SORTS}
            className={CONTROL}
          />
        </div>
      </div>

      <div className="overflow-x-auto border-t border-border">
        <table className="w-full text-sm">
          <thead className="bg-muted/40 text-left text-xs text-muted-foreground">
            <tr>
              <th className="w-10 px-4 py-3">
                <input
                  type="checkbox"
                  aria-label="Select all on this page"
                  checked={pageAllSelected}
                  onChange={(e) =>
                    setSelected((prev) => {
                      const next = new Set(prev);
                      for (const r of pageRows) {
                        if (e.target.checked) next.add(r.membershipId);
                        else next.delete(r.membershipId);
                      }
                      return next;
                    })
                  }
                  className="h-4 w-4 cursor-pointer rounded border-input accent-[#0B7A55]"
                />
              </th>
              <th className="px-4 py-3 font-medium">Member</th>
              <th className="px-4 py-3 font-medium">Plan</th>
              <th className="px-4 py-3 font-medium">Playing Schedule</th>
              <th className="px-4 py-3 font-medium">Court</th>
              <th className="px-4 py-3 font-medium">Start Date</th>
              <th className="px-4 py-3 font-medium">End Date</th>
              <th className="px-4 py-3 font-medium">Status</th>
              <th className="px-4 py-3 text-center font-medium">Actions</th>
            </tr>
          </thead>
          <tbody>
            {pageRows.length === 0 ? (
              <tr>
                <td colSpan={9} className="px-4 py-12 text-center text-sm text-muted-foreground">
                  No members match these filters.
                </td>
              </tr>
            ) : (
              pageRows.map((row) => {
                const s = rowStatus(row, now);
                const bucket = bucketForRow(row);
                const isSelected = selected.has(row.membershipId);
                return (
                  <tr
                    key={row.membershipId}
                    className={cn("border-b border-border/60 transition-colors last:border-b-0 hover:bg-accent/40", isSelected && "bg-primary/[0.04]")}
                  >
                    <td className="px-4 py-3">
                      <input
                        type="checkbox"
                        aria-label={`Select ${row.memberName}`}
                        checked={isSelected}
                        onChange={() => toggle(row.membershipId)}
                        className="h-4 w-4 cursor-pointer rounded border-input accent-[#0B7A55]"
                      />
                    </td>
                    <td className="px-4 py-3">
                      <div className="flex items-center gap-3">
                        <Avatar className="h-9 w-9">
                          <AvatarFallback className="text-xs">{initials(row.memberName)}</AvatarFallback>
                        </Avatar>
                        <div className="min-w-0">
                          <p className="max-w-[11rem] truncate font-medium text-foreground">{row.memberName}</p>
                          <p className="truncate text-xs tabular-nums text-muted-foreground">{row.memberPhone}</p>
                        </div>
                      </div>
                    </td>
                    <td className="px-4 py-3">
                      <Pill tone={PLAN_TONES[bucket]}>{row.planName}</Pill>
                      <p className="mt-1 text-xs tabular-nums text-muted-foreground">{inr(row.monthlyPriceInr)}</p>
                    </td>
                    <td className="px-4 py-3">
                      {row.slot ? (
                        <>
                          <p className="whitespace-nowrap text-foreground">{formatDayRange(row.slot.daysOfWeek)}</p>
                          <p className="whitespace-nowrap text-xs text-muted-foreground">
                            {formatClock(row.slot.startTime)} - {formatClock(row.slot.endTime)}
                          </p>
                        </>
                      ) : (
                        <span className="text-muted-foreground">—</span>
                      )}
                    </td>
                    <td className="px-4 py-3">
                      {row.slot?.courtName ? (
                        <Pill tone="bg-muted text-foreground">{row.slot.courtName}</Pill>
                      ) : (
                        <span className="text-muted-foreground">—</span>
                      )}
                    </td>
                    <td className="whitespace-nowrap px-4 py-3 text-muted-foreground">{fmtDate(row.startDate)}</td>
                    <td className="whitespace-nowrap px-4 py-3 text-muted-foreground">{fmtDate(row.endDate)}</td>
                    <td className="px-4 py-3">
                      <Pill tone={STATUS_TONES[s].tone}>
                        <span className="h-1.5 w-1.5 shrink-0 rounded-full bg-current" aria-hidden />
                        {STATUS_TONES[s].label}
                      </Pill>
                    </td>
                    <td className="px-4 py-3">
                      <div className="flex justify-center">
                        <DropdownMenu>
                          <DropdownMenuTrigger asChild>
                            <button
                              type="button"
                              aria-label={`Actions for ${row.memberName}`}
                              className="flex h-8 w-8 items-center justify-center rounded-lg border border-input text-muted-foreground outline-none transition-colors hover:bg-accent hover:text-foreground"
                            >
                              <MoreHorizontal className="h-4 w-4" />
                            </button>
                          </DropdownMenuTrigger>
                          <DropdownMenuContent align="end" className="w-44">
                            <DropdownMenuItem onClick={() => router.push(`/memberships/${row.membershipId}`)}>
                              <Eye className="mr-2 h-4 w-4" />
                              View details
                            </DropdownMenuItem>
                            <DropdownMenuItem onClick={() => router.push(`/memberships/${row.membershipId}/edit`)}>
                              <Pencil className="mr-2 h-4 w-4" />
                              Edit membership
                            </DropdownMenuItem>
                          </DropdownMenuContent>
                        </DropdownMenu>
                      </div>
                    </td>
                  </tr>
                );
              })
            )}
          </tbody>
        </table>
      </div>

      <div className="flex flex-wrap items-center justify-between gap-3 border-t border-border px-4 py-3">
        <p className="text-xs text-muted-foreground">
          {total === 0 ? "No members" : `Showing ${from}–${to} of ${total} members`}
        </p>

        <div className="flex items-center gap-1">
          <button
            type="button"
            aria-label="Previous page"
            disabled={safePage <= 1}
            onClick={() => setPage(safePage - 1)}
            className="flex h-8 w-8 items-center justify-center rounded-lg border border-input transition-colors hover:bg-accent disabled:opacity-40"
          >
            <ChevronLeft className="h-4 w-4" />
          </button>
          {Array.from({ length: Math.min(pages, 5) }, (_, i) => {
            // Keep the current page in view once there are more pages than buttons.
            const start = Math.min(Math.max(1, safePage - 2), Math.max(1, pages - 4));
            return start + i;
          }).map((p) => (
            <button
              key={p}
              type="button"
              onClick={() => setPage(p)}
              aria-current={p === safePage ? "page" : undefined}
              className={cn(
                "flex h-8 min-w-8 items-center justify-center rounded-lg border px-2 text-sm tabular-nums transition-colors",
                p === safePage ? "border-[#0B7A55] bg-[#0B7A55] text-white" : "border-input hover:bg-accent",
              )}
            >
              {p}
            </button>
          ))}
          <button
            type="button"
            aria-label="Next page"
            disabled={safePage >= pages}
            onClick={() => setPage(safePage + 1)}
            className="flex h-8 w-8 items-center justify-center rounded-lg border border-input transition-colors hover:bg-accent disabled:opacity-40"
          >
            <ChevronRight className="h-4 w-4" />
          </button>
        </div>

        <div className="flex items-center gap-2 text-xs text-muted-foreground">
          Show
          <SelectField
            wrapperClassName="w-[72px]"
            ariaLabel="Rows per page"
            // Opens upward: the card clips its overflow, so a list dropping below would be cut off.
            placement="top"
            value={String(perPage)}
            onValueChange={(v) => setPerPage(Number(v))}
            options={PAGE_SIZES.map((n) => ({ value: String(n), label: String(n) }))}
            className="h-8 w-full rounded-lg border border-input bg-card px-2 text-sm text-foreground outline-none transition-colors hover:border-foreground/30"
          />
          per page
        </div>
      </div>
    </Card>
  );
}
