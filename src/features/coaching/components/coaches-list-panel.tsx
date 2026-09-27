"use client";

import { useCallback, useEffect, useState } from "react";
import Link from "next/link";
import { LayoutGrid, List, Plus, Search, Star } from "lucide-react";
import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { ServiceError } from "@/services/shared/service-error";
import { getCoachingService } from "@/services/coaching";
import { useFacilitySportOptions } from "@/features/facility/hooks/use-facility-sport-options";
import { usePermissionContext } from "@/features/auth/context/permission-provider";
import { AddCoachSheet } from "@/features/coaching/components/add-coach-sheet";
import type { CoachRow, CoachSort, CoachStatus } from "@/features/coaching/types";
import {
  EmptyState,
  ErrorState,
  Pagination,
  TableSkeleton,
  Tabs,
  coachStatusBadge,
  initials,
} from "@/features/coaching/components/shared";

const PAGE_SIZE = 20;
const ALL = "ALL";
const STATUS_TABS = ["All Coaches", "Active", "Inactive"] as const;
type StatusTab = (typeof STATUS_TABS)[number];

const STATUS_OPTIONS: { value: string; label: string }[] = [
  { value: ALL, label: "All Status" },
  { value: "ACTIVE", label: "Active" },
  { value: "INACTIVE", label: "Inactive" },
];

const SORT_OPTIONS: { value: CoachSort; label: string }[] = [
  { value: "name_asc", label: "Name (A-Z)" },
  { value: "name_desc", label: "Name (Z-A)" },
  { value: "experience_desc", label: "Most Experience" },
  { value: "sessions_desc", label: "Most Sessions" },
];

function tabForStatus(status: CoachStatus | null): StatusTab {
  if (status === "ACTIVE") return "Active";
  if (status === "INACTIVE") return "Inactive";
  return "All Coaches";
}

function statusForTab(tab: StatusTab): CoachStatus | null {
  if (tab === "Active") return "ACTIVE";
  if (tab === "Inactive") return "INACTIVE";
  return null;
}

function RatingCell({ rating }: { rating: number | null }) {
  if (rating == null) return <span className="text-muted-foreground">—</span>;
  return (
    <span className="inline-flex items-center gap-1 tabular-nums">
      <Star className="h-3.5 w-3.5 fill-warning text-warning" aria-hidden />
      {rating.toFixed(1)}
    </span>
  );
}

/**
 * The searchable/filterable coach roster: tabs, search, status/sport/sort filters, a list/grid
 * toggle, the table itself, and pagination. Shared by the standalone /coaching/coaches page and
 * the Coaching landing page (which embeds it directly, same pattern the Membership Dashboard
 * uses for its own member list) — one filter/pagination implementation, not two.
 *
 * The status Tabs and the "All Status" dropdown are two views onto the same filter (the reference
 * design shows both at once) — they stay in sync rather than being independent filters.
 */
export function CoachesListPanel({ facilityId, showAddButton = false }: { facilityId: string; showAddButton?: boolean }) {
  const perms = usePermissionContext();
  const sportsQuery = useFacilitySportOptions(facilityId);

  const [status, setStatus] = useState<CoachStatus | null>(null);
  const [search, setSearch] = useState("");
  const [debounced, setDebounced] = useState("");
  const [sportId, setSportId] = useState(ALL);
  const [sort, setSort] = useState<CoachSort>("name_asc");
  const [view, setView] = useState<"list" | "grid">("list");
  const [page, setPage] = useState(0);
  const [rows, setRows] = useState<CoachRow[] | null>(null);
  const [totalCount, setTotalCount] = useState(0);
  const [error, setError] = useState<string | null>(null);
  const [addOpen, setAddOpen] = useState(false);

  const canAdd = perms?.can("COACHING_MANAGE_COACHES") ?? false;

  useEffect(() => {
    const t = setTimeout(() => setDebounced(search), 300);
    return () => clearTimeout(t);
  }, [search]);
  useEffect(() => setPage(0), [debounced, status, sportId, sort]);

  const load = useCallback(async () => {
    setError(null);
    const result = await getCoachingService().listCoaches({
      facilityId,
      filters: { search: debounced, status, sportId: sportId === ALL ? null : sportId },
      sort,
      limit: PAGE_SIZE,
      offset: page * PAGE_SIZE,
    });
    setRows(result.coaches);
    setTotalCount(result.totalCount);
  }, [facilityId, debounced, status, sportId, sort, page]);

  useEffect(() => {
    let cancelled = false;
    setRows(null);
    load().catch((e) => {
      if (cancelled) return;
      setError(e instanceof ServiceError ? e.message : "Unable to load coaches.");
      setRows([]);
    });
    return () => {
      cancelled = true;
    };
  }, [load]);

  return (
    <div className="space-y-4">
      <Card className="p-4">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <Tabs tabs={STATUS_TABS} active={tabForStatus(status)} onChange={(t) => setStatus(statusForTab(t))} />
          {showAddButton && canAdd && (
            <Button size="sm" onClick={() => setAddOpen(true)}>
              <Plus className="h-4 w-4" aria-hidden /> Add Coach
            </Button>
          )}
        </div>

        <div className="mt-3 flex flex-wrap items-end gap-3">
          <div className="relative min-w-[14rem] flex-1">
            <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" aria-hidden />
            <Input
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              placeholder="Search coach by name, sport, or phone…"
              aria-label="Search coaches"
              className="h-10 pl-9"
            />
          </div>
          <Select value={sportId} onValueChange={setSportId}>
            <SelectTrigger className="w-[10rem]" aria-label="Filter by sport">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value={ALL}>All Sports</SelectItem>
              {(sportsQuery.data ?? []).map((s) => (
                <SelectItem key={s.facilitySportId} value={s.facilitySportId}>
                  {s.name}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
          <Select value={status ?? ALL} onValueChange={(v) => setStatus(v === ALL ? null : (v as CoachStatus))}>
            <SelectTrigger className="w-[10rem]" aria-label="Filter by status">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              {STATUS_OPTIONS.map((o) => (
                <SelectItem key={o.value} value={o.value}>
                  {o.label}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
          <Select value={sort} onValueChange={(v) => setSort(v as CoachSort)}>
            <SelectTrigger className="w-[10rem]" aria-label="Sort by">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              {SORT_OPTIONS.map((o) => (
                <SelectItem key={o.value} value={o.value}>
                  {o.label}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
          <div className="flex items-center gap-1 rounded-lg border border-input p-1">
            <button
              type="button"
              aria-label="List view"
              aria-pressed={view === "list"}
              onClick={() => setView("list")}
              className={`flex h-8 w-8 items-center justify-center rounded-md ${view === "list" ? "bg-success text-success-foreground" : "text-muted-foreground"}`}
            >
              <List className="h-4 w-4" aria-hidden />
            </button>
            <button
              type="button"
              aria-label="Grid view"
              aria-pressed={view === "grid"}
              onClick={() => setView("grid")}
              className={`flex h-8 w-8 items-center justify-center rounded-md ${view === "grid" ? "bg-success text-success-foreground" : "text-muted-foreground"}`}
            >
              <LayoutGrid className="h-4 w-4" aria-hidden />
            </button>
          </div>
        </div>
      </Card>

      <Card className="p-0">
        {error ? (
          <ErrorState message={error} onRetry={() => void load()} />
        ) : rows === null ? (
          <TableSkeleton />
        ) : rows.length === 0 ? (
          <EmptyState message="No coaches match these filters." />
        ) : view === "grid" ? (
          <div className="grid grid-cols-1 gap-3 p-4 sm:grid-cols-2 lg:grid-cols-3">
            {rows.map((c) => (
              <Link
                key={c.id}
                href={`/coaching/coaches/${c.id}`}
                className="flex flex-col gap-2 rounded-xl border border-border p-4 transition-colors hover:bg-accent/40"
              >
                <div className="flex items-center gap-3">
                  <Avatar className="h-10 w-10">
                    {c.avatarUrl && <AvatarImage src={c.avatarUrl} alt="" />}
                    <AvatarFallback>{initials(c.fullName)}</AvatarFallback>
                  </Avatar>
                  <div className="min-w-0">
                    <p className="truncate font-medium">{c.fullName}</p>
                    <p className="truncate text-xs text-muted-foreground">{c.phone ?? c.email ?? "—"}</p>
                  </div>
                </div>
                <div className="flex flex-wrap gap-1">
                  {c.sports.map((s) => (
                    <Badge key={s.id} variant="outline" className="text-[11px]">
                      {s.name}
                    </Badge>
                  ))}
                </div>
                <div className="flex items-center justify-between text-xs text-muted-foreground">
                  <RatingCell rating={c.rating} />
                  <span>{c.sessionCount} sessions</span>
                  {coachStatusBadge(c.status)}
                </div>
              </Link>
            ))}
          </div>
        ) : (
          <div className="overflow-x-auto">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Coach</TableHead>
                  <TableHead>Sports</TableHead>
                  <TableHead>Expertise</TableHead>
                  <TableHead className="text-right">Experience</TableHead>
                  <TableHead>Rating</TableHead>
                  <TableHead className="text-right">Sessions</TableHead>
                  <TableHead className="text-right">Students</TableHead>
                  <TableHead>Status</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {rows.map((c) => (
                  <TableRow key={c.id}>
                    <TableCell>
                      <Link href={`/coaching/coaches/${c.id}`} className="flex items-center gap-3">
                        <Avatar className="h-8 w-8">
                          {c.avatarUrl && <AvatarImage src={c.avatarUrl} alt="" />}
                          <AvatarFallback className="text-xs">{initials(c.fullName)}</AvatarFallback>
                        </Avatar>
                        <span className="min-w-0">
                          <span className="block truncate font-medium hover:underline">{c.fullName}</span>
                          {c.phone && <span className="block truncate text-xs text-muted-foreground">{c.phone}</span>}
                        </span>
                      </Link>
                    </TableCell>
                    <TableCell>
                      <div className="flex flex-wrap gap-1">
                        {c.sports.length === 0 ? (
                          <span className="text-muted-foreground">—</span>
                        ) : (
                          c.sports.map((s) => (
                            <Badge key={s.id} variant="outline" className="text-[11px]">
                              {s.name}
                            </Badge>
                          ))
                        )}
                      </div>
                    </TableCell>
                    <TableCell className="text-muted-foreground">{c.expertiseLevels.join(", ") || "—"}</TableCell>
                    <TableCell className="text-right tabular-nums text-muted-foreground">
                      {c.experienceYears != null ? `${c.experienceYears} yrs` : "—"}
                    </TableCell>
                    <TableCell>
                      <RatingCell rating={c.rating} />
                    </TableCell>
                    <TableCell className="text-right tabular-nums">{c.sessionCount}</TableCell>
                    <TableCell className="text-right tabular-nums">{c.studentCount}</TableCell>
                    <TableCell>{coachStatusBadge(c.status)}</TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </div>
        )}
        <Pagination page={page} pageSize={PAGE_SIZE} totalCount={totalCount} onPage={setPage} unit="coaches" />
      </Card>

      {showAddButton && (
        <AddCoachSheet facilityId={facilityId} open={addOpen} onOpenChange={setAddOpen} onCoachAdded={() => void load()} />
      )}
    </div>
  );
}
