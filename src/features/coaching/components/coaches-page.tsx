"use client";

import { useCallback, useEffect, useState } from "react";
import Link from "next/link";
import { Plus, Search } from "lucide-react";
import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { ServiceError } from "@/services/shared/service-error";
import { getCoachingService } from "@/services/coaching";
import { usePermissionContext } from "@/features/auth/context/permission-provider";
import type { CoachRow, CoachStatus } from "@/features/coaching/types";
import {
  EmptyState,
  ErrorState,
  PageHeader,
  Pagination,
  TableSkeleton,
  coachStatusBadge,
  initials,
} from "@/features/coaching/components/shared";

const PAGE_SIZE = 20;
const ALL = "ALL";

export function CoachesPage() {
  const perms = usePermissionContext();
  const facilityId = perms?.facilityId ?? null;

  const [search, setSearch] = useState("");
  const [debounced, setDebounced] = useState("");
  const [status, setStatus] = useState(ALL);
  const [page, setPage] = useState(0);
  const [rows, setRows] = useState<CoachRow[] | null>(null);
  const [totalCount, setTotalCount] = useState(0);
  const [error, setError] = useState<string | null>(null);

  const canAdd = perms?.can("COACHING_MANAGE_COACHES") ?? false;

  useEffect(() => {
    const t = setTimeout(() => setDebounced(search), 300);
    return () => clearTimeout(t);
  }, [search]);
  useEffect(() => setPage(0), [debounced, status]);

  const load = useCallback(async () => {
    if (!facilityId) return;
    setError(null);
    const result = await getCoachingService().listCoaches({
      facilityId,
      filters: { search: debounced, status: status === ALL ? null : (status as CoachStatus) },
      limit: PAGE_SIZE,
      offset: page * PAGE_SIZE,
    });
    setRows(result.coaches);
    setTotalCount(result.totalCount);
  }, [facilityId, debounced, status, page]);

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
      <PageHeader
        title="Coaches"
        subtitle="Manage your coaching team, their schedules and availability."
        action={
          canAdd && (
            <Button asChild size="sm">
              <Link href="/coaching/coaches/add">
                <Plus className="h-4 w-4" aria-hidden /> Add Coach
              </Link>
            </Button>
          )
        }
      />

      <Card className="p-4">
        <div className="flex flex-wrap items-end gap-3">
          <div className="relative min-w-[14rem] flex-1">
            <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" aria-hidden />
            <Input
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              placeholder="Search coaches by name, email or phone…"
              aria-label="Search coaches"
              className="h-10 pl-9"
            />
          </div>
          <div className="space-y-1.5">
            <span className="block text-xs text-muted-foreground">Status</span>
            <Select value={status} onValueChange={setStatus}>
              <SelectTrigger className="w-[11rem]">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value={ALL}>All Status</SelectItem>
                <SelectItem value="ACTIVE">Active</SelectItem>
                <SelectItem value="ON_LEAVE">On Leave</SelectItem>
                <SelectItem value="INACTIVE">Inactive</SelectItem>
              </SelectContent>
            </Select>
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
        ) : (
          <div className="overflow-x-auto">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Coach</TableHead>
                  <TableHead>Specialization</TableHead>
                  <TableHead className="text-right">Experience</TableHead>
                  <TableHead className="text-right">Programs</TableHead>
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
                          {c.email && <span className="block truncate text-xs text-muted-foreground">{c.email}</span>}
                        </span>
                      </Link>
                    </TableCell>
                    <TableCell className="text-muted-foreground">{c.specialization ?? "—"}</TableCell>
                    <TableCell className="text-right tabular-nums text-muted-foreground">
                      {c.experienceYears != null ? `${c.experienceYears} yrs` : "—"}
                    </TableCell>
                    <TableCell className="text-right tabular-nums">{c.programCount}</TableCell>
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
    </div>
  );
}
