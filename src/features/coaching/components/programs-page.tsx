"use client";

import { useCallback, useEffect, useState } from "react";
import Link from "next/link";
import { Plus, Search } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { ServiceError } from "@/services/shared/service-error";
import { getCoachingService } from "@/services/coaching";
import { usePermissionContext } from "@/features/auth/context/permission-provider";
import type { ProgramRow, ProgramStatus } from "@/features/coaching/types";
import {
  EmptyState,
  ErrorState,
  PageHeader,
  Pagination,
  TableSkeleton,
  money,
} from "@/features/coaching/components/shared";

const PAGE_SIZE = 20;
const ALL = "ALL";

export function ProgramsPage() {
  const perms = usePermissionContext();
  const facilityId = perms?.facilityId ?? null;

  const [search, setSearch] = useState("");
  const [debounced, setDebounced] = useState("");
  const [status, setStatus] = useState(ALL);
  const [page, setPage] = useState(0);
  const [rows, setRows] = useState<ProgramRow[] | null>(null);
  const [totalCount, setTotalCount] = useState(0);
  const [error, setError] = useState<string | null>(null);

  const canCreate = perms?.can("COACHING_MANAGE_PROGRAMS") ?? false;

  useEffect(() => {
    const t = setTimeout(() => setDebounced(search), 300);
    return () => clearTimeout(t);
  }, [search]);
  useEffect(() => setPage(0), [debounced, status]);

  const load = useCallback(async () => {
    if (!facilityId) return;
    setError(null);
    const result = await getCoachingService().listPrograms({
      facilityId,
      filters: { search: debounced, status: status === ALL ? null : (status as ProgramStatus) },
      limit: PAGE_SIZE,
      offset: page * PAGE_SIZE,
    });
    setRows(result.programs);
    setTotalCount(result.totalCount);
  }, [facilityId, debounced, status, page]);

  useEffect(() => {
    let cancelled = false;
    setRows(null);
    load().catch((e) => {
      if (cancelled) return;
      setError(e instanceof ServiceError ? e.message : "Unable to load programs.");
      setRows([]);
    });
    return () => {
      cancelled = true;
    };
  }, [load]);

  return (
    <div className="space-y-4">
      <PageHeader
        title="Coaching Programs"
        subtitle="Create and manage coaching programs and class types."
        action={
          canCreate && (
            <Button asChild size="sm">
              <Link href="/coaching/programs/new">
                <Plus className="h-4 w-4" aria-hidden /> Create Program
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
              placeholder="Search programs…"
              aria-label="Search programs"
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
          <EmptyState message="No coaching programs yet." />
        ) : (
          <div className="overflow-x-auto">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Program Name</TableHead>
                  <TableHead>Level</TableHead>
                  <TableHead>Age Group</TableHead>
                  <TableHead className="text-right">Sessions</TableHead>
                  <TableHead className="text-right">Students</TableHead>
                  <TableHead className="text-right">Price</TableHead>
                  <TableHead>Status</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {rows.map((p) => (
                  <TableRow key={p.id}>
                    <TableCell>
                      <Link href={`/coaching/programs/${p.id}`} className="font-medium hover:underline">
                        {p.name}
                      </Link>
                      <span className="block text-xs text-muted-foreground">{p.category}</span>
                    </TableCell>
                    <TableCell className="text-muted-foreground">{p.level}</TableCell>
                    <TableCell className="text-muted-foreground">{p.ageGroup}</TableCell>
                    <TableCell className="text-right tabular-nums text-muted-foreground">
                      {p.sessionCount ?? "—"}
                    </TableCell>
                    <TableCell className="text-right tabular-nums">{p.studentCount}</TableCell>
                    <TableCell className="text-right tabular-nums">
                      {p.isMembershipIncluded ? "Included" : p.defaultPriceMinor != null ? money(p.defaultPriceMinor) : "—"}
                    </TableCell>
                    <TableCell>
                      <Badge variant={p.status === "ACTIVE" ? "success" : "secondary"}>
                        {p.status === "ACTIVE" ? "Active" : "Inactive"}
                      </Badge>
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </div>
        )}
        <Pagination page={page} pageSize={PAGE_SIZE} totalCount={totalCount} onPage={setPage} unit="programs" />
      </Card>
    </div>
  );
}
