"use client";

import { useCallback, useEffect, useState } from "react";
import Link from "next/link";
import { ChevronLeft, ChevronRight, Plus, Search } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Skeleton } from "@/components/ui/skeleton";
import { formatDate, formatMoney, PRIORITY_BADGE_CLASS, PRIORITY_LABEL, STATUS_BADGE_CLASS, STATUS_LABEL } from "@/features/maintenance/status";
import type { MaintenancePriority, MaintenanceStatus, MaintenanceTicketFilters, MaintenanceTicketListRow } from "@/features/maintenance/types";
import { getFacilityService } from "@/services/facility";
import { getMaintenanceService } from "@/services/maintenance";
import { ServiceError } from "@/services/shared/service-error";

const PAGE_SIZE = 20;
const STATUSES: MaintenanceStatus[] = ["REPORTED", "ASSIGNED", "SCHEDULED", "IN_PROGRESS", "RESOLVED", "CLOSED"];
const PRIORITIES: MaintenancePriority[] = ["LOW", "MEDIUM", "HIGH", "CRITICAL"];

export function MaintenanceTicketsPage() {
  const [facilityId, setFacilityId] = useState<string | null>(null);
  const [loadState, setLoadState] = useState<"loading" | "ready" | "none" | "error">("loading");
  const [rows, setRows] = useState<MaintenanceTicketListRow[] | null>(null);
  const [totalCount, setTotalCount] = useState(0);
  const [page, setPage] = useState(0);
  const [filters, setFilters] = useState<MaintenanceTicketFilters>({});
  const [search, setSearch] = useState("");
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    getFacilityService()
      .getFacility()
      .then((f) => {
        if (cancelled) return;
        if (!f) return setLoadState("none");
        setFacilityId(f.id);
        setLoadState("ready");
      })
      .catch(() => !cancelled && setLoadState("error"));
    return () => {
      cancelled = true;
    };
  }, []);

  useEffect(() => setPage(0), [filters, search]);

  const load = useCallback(async () => {
    if (!facilityId) return;
    setError(null);
    try {
      const result = await getMaintenanceService().listTickets(facilityId, { ...filters, search }, PAGE_SIZE, page * PAGE_SIZE);
      setRows(result.tickets);
      setTotalCount(result.totalCount);
    } catch (e) {
      setRows([]);
      setError(e instanceof ServiceError ? e.message : "Unable to load maintenance tickets.");
    }
  }, [facilityId, filters, search, page]);

  useEffect(() => {
    void load();
  }, [load]);

  if (loadState === "loading") return <Skeleton className="h-96 w-full rounded-xl" />;
  if (loadState === "none") return <p className="text-sm text-muted-foreground">No facility found for this account yet.</p>;
  if (loadState === "error") return <p className="text-sm text-destructive">Unable to load this page. Please try again.</p>;

  const totalPages = Math.max(1, Math.ceil(totalCount / PAGE_SIZE));

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h1 className="text-xl font-semibold">Maintenance Tickets</h1>
          <p className="text-sm text-muted-foreground">Track, assign and resolve court maintenance issues.</p>
        </div>
        <Button asChild>
          <Link href="/maintenance/tickets/new">
            <Plus className="mr-1.5 h-4 w-4" /> New Ticket
          </Link>
        </Button>
      </div>

      <div className="flex flex-wrap items-center gap-2">
        <div className="relative max-w-xs flex-1">
          <Search className="pointer-events-none absolute left-2.5 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" aria-hidden />
          <Input value={search} onChange={(e) => setSearch(e.target.value)} placeholder="Search ticket, court…" className="pl-8" />
        </div>
        <FilterSelect
          label="Status"
          value={filters.status ?? ""}
          options={STATUSES.map((s) => ({ value: s, label: STATUS_LABEL[s] }))}
          onChange={(v) => setFilters((f) => ({ ...f, status: (v || undefined) as MaintenanceStatus | undefined }))}
        />
        <FilterSelect
          label="Priority"
          value={filters.priority ?? ""}
          options={PRIORITIES.map((p) => ({ value: p, label: PRIORITY_LABEL[p] }))}
          onChange={(v) => setFilters((f) => ({ ...f, priority: (v || undefined) as MaintenancePriority | undefined }))}
        />
      </div>

      {error && <p className="text-sm text-destructive">{error}</p>}

      {rows === null ? (
        <Skeleton className="h-64 w-full rounded-xl" />
      ) : rows.length === 0 ? (
        <Card className="p-8 text-center text-sm text-muted-foreground">No maintenance tickets match this filter.</Card>
      ) : (
        <Card className="overflow-hidden p-0">
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead className="border-b border-border bg-secondary/40 text-left text-xs text-muted-foreground">
                <tr>
                  <th className="px-4 py-2.5 font-medium">#</th>
                  <th className="px-4 py-2.5 font-medium">Court</th>
                  <th className="px-4 py-2.5 font-medium">Issue</th>
                  <th className="px-4 py-2.5 font-medium">Priority</th>
                  <th className="px-4 py-2.5 font-medium">Status</th>
                  <th className="px-4 py-2.5 font-medium">Reported On</th>
                  <th className="px-4 py-2.5 font-medium">Assigned To</th>
                  <th className="px-4 py-2.5 font-medium">Cost</th>
                  <th className="px-4 py-2.5" />
                </tr>
              </thead>
              <tbody>
                {rows.map((t) => (
                  <tr key={t.ticketId} className="border-b border-border last:border-0 hover:bg-secondary/20">
                    <td className="px-4 py-2.5 font-medium text-foreground">{t.code}</td>
                    <td className="px-4 py-2.5">
                      {t.courtName}
                      {t.sportName && <span className="ml-1 text-xs text-muted-foreground">· {t.sportName}</span>}
                    </td>
                    <td className="max-w-[220px] truncate px-4 py-2.5">{t.title}</td>
                    <td className="px-4 py-2.5">
                      <Badge className={PRIORITY_BADGE_CLASS[t.priority]}>{PRIORITY_LABEL[t.priority]}</Badge>
                    </td>
                    <td className="px-4 py-2.5">
                      <Badge className={STATUS_BADGE_CLASS[t.status]}>{STATUS_LABEL[t.status]}</Badge>
                    </td>
                    <td className="px-4 py-2.5 text-muted-foreground">{formatDate(t.reportedAt)}</td>
                    <td className="px-4 py-2.5 text-muted-foreground">{t.assignedToName ?? "Unassigned"}</td>
                    <td className="px-4 py-2.5 text-muted-foreground">{formatMoney(t.actualCostMinor ?? t.estimatedCostMinor)}</td>
                    <td className="px-4 py-2.5 text-right">
                      <Button variant="ghost" size="sm" asChild>
                        <Link href={`/maintenance/tickets/${t.ticketId}`}>View</Link>
                      </Button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>

          <div className="flex items-center justify-between border-t border-border px-4 py-2.5 text-xs text-muted-foreground">
            <span>
              Page {page + 1} of {totalPages} · {totalCount} tickets
            </span>
            <div className="flex gap-1">
              <Button variant="outline" size="sm" disabled={page === 0} onClick={() => setPage((p) => p - 1)}>
                <ChevronLeft className="h-4 w-4" />
              </Button>
              <Button variant="outline" size="sm" disabled={page + 1 >= totalPages} onClick={() => setPage((p) => p + 1)}>
                <ChevronRight className="h-4 w-4" />
              </Button>
            </div>
          </div>
        </Card>
      )}
    </div>
  );
}

function FilterSelect({
  label,
  value,
  options,
  onChange,
}: {
  label: string;
  value: string;
  options: { value: string; label: string }[];
  onChange: (value: string) => void;
}) {
  return (
    <select
      aria-label={label}
      value={value}
      onChange={(e) => onChange(e.target.value)}
      className="h-9 rounded-md border border-input bg-background px-2.5 text-sm text-foreground"
    >
      <option value="">All {label}</option>
      {options.map((o) => (
        <option key={o.value} value={o.value}>
          {o.label}
        </option>
      ))}
    </select>
  );
}
