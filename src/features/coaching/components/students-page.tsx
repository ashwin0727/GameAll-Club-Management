"use client";

import { useCallback, useEffect, useState } from "react";
import Link from "next/link";
import { ChevronRight, Plus, Search } from "lucide-react";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { getCoachingService } from "@/services/coaching";
import { ServiceError } from "@/services/shared/service-error";
import { usePermissionContext } from "@/features/auth/context/permission-provider";
import type { EnrollmentRow, EnrollmentStatus, ProgramOption } from "@/features/coaching/types";
import {
  EmptyState,
  ErrorState,
  KpiCard,
  Pagination,
  TableSkeleton,
  enrollmentStatusBadge,
  fmtDate,
  money,
  paymentStatusBadge,
} from "@/features/coaching/components/shared";

const PAGE_SIZE = 10;
const ALL = "ALL";

/**
 * Manage Students — the coaching module's student roster, one row per program enrollment (the
 * existing `coaching_enrollments` relationship; no new Student entity). Add Student routes to the
 * dedicated wizard instead of the older quick-add dialog still used from Program Details.
 */
export function CoachingStudentsPage() {
  const perms = usePermissionContext();
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

  const [kpis, setKpis] = useState<{ total: number; active: number; pendingPayment: number; programCount: number } | null>(null);

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

  const loadKpis = useCallback(async () => {
    if (!facilityId) return;
    try {
      const [totalPage, activePage, programPage] = await Promise.all([
        getCoachingService().listEnrollments({ facilityId, limit: 1 }),
        getCoachingService().listEnrollments({ facilityId, filters: { status: "ACTIVE" }, limit: 1 }),
        getCoachingService().listPrograms({ facilityId, limit: 1 }),
      ]);
      // Payment Pending needs a real per-row status, not just a count — page through active
      // enrollments (bounded) to count PENDING/PARTIAL rather than adding a new aggregate RPC.
      const activeRows = await getCoachingService().listEnrollments({ facilityId, filters: { status: "ACTIVE" }, limit: 200 });
      const pendingPayment = activeRows.enrollments.filter((e) => e.paymentStatus === "PENDING" || e.paymentStatus === "PARTIAL").length;
      setKpis({ total: totalPage.totalCount, active: activePage.totalCount, pendingPayment, programCount: programPage.totalCount });
    } catch {
      setKpis(null);
    }
  }, [facilityId]);

  useEffect(() => {
    void loadKpis();
  }, [loadKpis]);

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
      setError(e instanceof ServiceError ? e.message : "Unable to load students.");
      setRows([]);
    });
    return () => {
      cancelled = true;
    };
  }, [load]);

  return (
    <div className="space-y-4">
      <nav aria-label="Breadcrumb" className="flex items-center gap-1 text-xs text-muted-foreground">
        <Link href="/dashboard" className="hover:text-foreground">
          Home
        </Link>
        <ChevronRight className="h-3.5 w-3.5" aria-hidden />
        <Link href="/coaching" className="hover:text-foreground">
          Coaching
        </Link>
        <ChevronRight className="h-3.5 w-3.5" aria-hidden />
        <span className="font-medium text-foreground">Manage Students</span>
      </nav>

      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h1 className="text-2xl font-bold">Manage Students</h1>
          <p className="text-sm text-muted-foreground">Manage students enrolled in your coaching programs.</p>
        </div>
        {canManage && (
          <Link href="/coaching/students/new" className="flex h-10 items-center gap-2 rounded-lg bg-[#0B7A55] px-4 text-sm font-semibold text-white transition-opacity hover:opacity-90">
            <Plus className="h-4 w-4" aria-hidden /> Add Student
          </Link>
        )}
      </div>

      <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
        <KpiCard label="Total Students" value={kpis ? String(kpis.total) : "—"} />
        <KpiCard label="Active Students" value={kpis ? String(kpis.active) : "—"} />
        <KpiCard label="Pending Payment" value={kpis ? String(kpis.pendingPayment) : "—"} />
        <KpiCard label="Programs" value={kpis ? String(kpis.programCount) : "—"} />
      </div>

      <Card className="p-4">
        <div className="flex flex-wrap items-end gap-3">
          <div className="relative min-w-[14rem] flex-1">
            <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" aria-hidden />
            <Input value={search} onChange={(e) => setSearch(e.target.value)} placeholder="Search student by name or phone…" aria-label="Search students" className="h-10 pl-9" />
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
          <EmptyState message="Start by adding your first student." />
        ) : (
          <div className="overflow-x-auto">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Student</TableHead>
                  <TableHead>Program</TableHead>
                  <TableHead>Batch</TableHead>
                  <TableHead>Enrolled</TableHead>
                  <TableHead className="text-right">Fee</TableHead>
                  <TableHead>Payment</TableHead>
                  <TableHead>Status</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {rows.map((e) => (
                  <TableRow key={e.id}>
                    <TableCell>
                      <Link href={`/coaching/enrollments/${e.id}`} className="font-medium hover:underline">
                        {e.studentName}
                      </Link>
                      {e.studentPhone && <span className="block text-xs text-muted-foreground">{e.studentPhone}</span>}
                    </TableCell>
                    <TableCell className="text-muted-foreground">{e.programName}</TableCell>
                    <TableCell className="text-muted-foreground">{e.batchName ?? "—"}</TableCell>
                    <TableCell className="text-muted-foreground">{fmtDate(e.startDate)}</TableCell>
                    <TableCell className="text-right tabular-nums">{e.priceMinor === 0 ? "Included" : money(e.priceMinor)}</TableCell>
                    <TableCell>{paymentStatusBadge(e.paymentStatus)}</TableCell>
                    <TableCell>{enrollmentStatusBadge(e.status)}</TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </div>
        )}
        <Pagination page={page} pageSize={PAGE_SIZE} totalCount={totalCount} onPage={setPage} unit="students" />
      </Card>
    </div>
  );
}

function Filter({ label, value, onChange, options }: { label: string; value: string; onChange: (v: string) => void; options: { value: string; label: string }[] }) {
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
