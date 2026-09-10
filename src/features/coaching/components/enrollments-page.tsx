"use client";

import { useCallback, useEffect, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { Plus, Search } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { ServiceError } from "@/services/shared/service-error";
import { getCoachingService } from "@/services/coaching";
import { usePermissionContext } from "@/features/auth/context/permission-provider";
import type { EnrollmentRow, EnrollmentStatus, ProgramOption } from "@/features/coaching/types";
import {
  EmptyState,
  ErrorState,
  PageHeader,
  Pagination,
  TableSkeleton,
  enrollmentStatusBadge,
  fmtDate,
  money,
  paymentStatusBadge,
} from "@/features/coaching/components/shared";
import { EnrollmentFormDialog } from "@/features/coaching/components/enrollment-form-dialog";

const PAGE_SIZE = 20;
const ALL = "ALL";

export function EnrollmentsPage() {
  const perms = usePermissionContext();
  const router = useRouter();
  const facilityId = perms?.facilityId ?? null;

  const [search, setSearch] = useState("");
  const [debounced, setDebounced] = useState("");
  const [status, setStatus] = useState(ALL);
  const [programId, setProgramId] = useState(ALL);
  const [page, setPage] = useState(0);
  const [rows, setRows] = useState<EnrollmentRow[] | null>(null);
  const [totalCount, setTotalCount] = useState(0);
  const [error, setError] = useState<string | null>(null);
  const [programs, setPrograms] = useState<ProgramOption[]>([]);
  const [adding, setAdding] = useState(false);

  const canManage = perms?.can("COACHING_MANAGE_ENROLLMENTS") ?? false;

  useEffect(() => {
    const t = setTimeout(() => setDebounced(search), 300);
    return () => clearTimeout(t);
  }, [search]);
  useEffect(() => setPage(0), [debounced, status, programId]);

  useEffect(() => {
    if (!facilityId) return;
    getCoachingService().listProgramOptions(facilityId).then(setPrograms).catch(() => setPrograms([]));
  }, [facilityId]);

  const load = useCallback(async () => {
    if (!facilityId) return;
    setError(null);
    const result = await getCoachingService().listEnrollments({
      facilityId,
      filters: {
        search: debounced,
        status: status === ALL ? null : (status as EnrollmentStatus),
        programId: programId === ALL ? null : programId,
      },
      limit: PAGE_SIZE,
      offset: page * PAGE_SIZE,
    });
    setRows(result.enrollments);
    setTotalCount(result.totalCount);
  }, [facilityId, debounced, status, programId, page]);

  useEffect(() => {
    let cancelled = false;
    setRows(null);
    load().catch((e) => {
      if (cancelled) return;
      setError(e instanceof ServiceError ? e.message : "Unable to load enrollments.");
      setRows([]);
    });
    return () => {
      cancelled = true;
    };
  }, [load]);

  return (
    <div className="space-y-4">
      <PageHeader
        title="Student Enrollments"
        subtitle="Manage student enrollments across programs."
        action={
          canManage && (
            <Button size="sm" onClick={() => setAdding(true)}>
              <Plus className="h-4 w-4" aria-hidden /> Add Enrollment
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
              placeholder="Search students…"
              aria-label="Search enrollments"
              className="h-10 pl-9"
            />
          </div>
          <Filter label="Program" value={programId} onChange={setProgramId} options={[{ value: ALL, label: "All Programs" }, ...programs.map((p) => ({ value: p.id, label: p.name }))]} />
          <Filter
            label="Status"
            value={status}
            onChange={setStatus}
            options={[
              { value: ALL, label: "All Status" },
              { value: "ACTIVE", label: "Active" },
              { value: "PAUSED", label: "Paused" },
              { value: "COMPLETED", label: "Completed" },
              { value: "CANCELLED", label: "Cancelled" },
            ]}
          />
        </div>
      </Card>

      <Card className="p-0">
        {error ? (
          <ErrorState message={error} onRetry={() => void load()} />
        ) : rows === null ? (
          <TableSkeleton />
        ) : rows.length === 0 ? (
          <EmptyState message="No enrollments match these filters." />
        ) : (
          <div className="overflow-x-auto">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Student</TableHead>
                  <TableHead>Program</TableHead>
                  <TableHead>Start Date</TableHead>
                  <TableHead>End Date</TableHead>
                  <TableHead className="text-right">Fee</TableHead>
                  <TableHead>Status</TableHead>
                  <TableHead>Payment</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {rows.map((e) => (
                  <TableRow key={e.id}>
                    <TableCell>
                      <Link href={`/coaching/enrollments/${e.id}`} className="font-medium hover:underline">
                        {e.studentName}
                      </Link>
                    </TableCell>
                    <TableCell className="text-muted-foreground">{e.programName}</TableCell>
                    <TableCell className="text-muted-foreground">{fmtDate(e.startDate)}</TableCell>
                    <TableCell className="text-muted-foreground">{fmtDate(e.endDate)}</TableCell>
                    <TableCell className="text-right tabular-nums">
                      {e.priceMinor === 0 ? "Included" : money(e.priceMinor)}
                    </TableCell>
                    <TableCell>{enrollmentStatusBadge(e.status)}</TableCell>
                    <TableCell>{paymentStatusBadge(e.paymentStatus)}</TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </div>
        )}
        <Pagination page={page} pageSize={PAGE_SIZE} totalCount={totalCount} onPage={setPage} unit="enrollments" />
      </Card>

      {adding && facilityId && (
        <EnrollmentFormDialog
          facilityId={facilityId}
          onClose={() => setAdding(false)}
          onSaved={(id) => {
            setAdding(false);
            router.push(`/coaching/enrollments/${id}`);
          }}
        />
      )}
    </div>
  );
}

function Filter({
  label,
  value,
  onChange,
  options,
}: {
  label: string;
  value: string;
  onChange: (v: string) => void;
  options: { value: string; label: string }[];
}) {
  return (
    <div className="space-y-1.5">
      <span className="block text-xs text-muted-foreground">{label}</span>
      <Select value={value} onValueChange={onChange}>
        <SelectTrigger className="w-[12rem]">
          <SelectValue />
        </SelectTrigger>
        <SelectContent>
          {options.map((o) => (
            <SelectItem key={o.value} value={o.value}>
              {o.label}
            </SelectItem>
          ))}
        </SelectContent>
      </Select>
    </div>
  );
}
