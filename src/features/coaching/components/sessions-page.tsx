"use client";

import { useCallback, useEffect, useState } from "react";
import Link from "next/link";
import { Plus } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { ServiceError } from "@/services/shared/service-error";
import { getCoachingService } from "@/services/coaching";
import { usePermissionContext } from "@/features/auth/context/permission-provider";
import type { CoachOption, ProgramOption, SessionRow, SessionStatus } from "@/features/coaching/types";
import {
  EmptyState,
  ErrorState,
  PageHeader,
  Pagination,
  SESSION_STATUS_LABEL,
  TableSkeleton,
  fmtDateTime,
  sessionStatusBadge,
} from "@/features/coaching/components/shared";

const PAGE_SIZE = 20;
const ALL = "ALL";

export function SessionsPage() {
  const perms = usePermissionContext();
  const facilityId = perms?.facilityId ?? null;

  const [status, setStatus] = useState(ALL);
  const [coachId, setCoachId] = useState(ALL);
  const [programId, setProgramId] = useState(ALL);
  const [page, setPage] = useState(0);
  const [rows, setRows] = useState<SessionRow[] | null>(null);
  const [totalCount, setTotalCount] = useState(0);
  const [error, setError] = useState<string | null>(null);
  const [coaches, setCoaches] = useState<CoachOption[]>([]);
  const [programs, setPrograms] = useState<ProgramOption[]>([]);

  const canCreate = perms?.can("COACHING_CREATE_SESSION") ?? false;

  useEffect(() => setPage(0), [status, coachId, programId]);

  useEffect(() => {
    if (!facilityId) return;
    getCoachingService().listCoachOptions(facilityId).then(setCoaches).catch(() => setCoaches([]));
    getCoachingService().listProgramOptions(facilityId).then(setPrograms).catch(() => setPrograms([]));
  }, [facilityId]);

  const load = useCallback(async () => {
    if (!facilityId) return;
    setError(null);
    const result = await getCoachingService().listSessions({
      facilityId,
      filters: {
        status: status === ALL ? null : (status as SessionStatus),
        coachId: coachId === ALL ? null : coachId,
        programId: programId === ALL ? null : programId,
      },
      limit: PAGE_SIZE,
      offset: page * PAGE_SIZE,
    });
    setRows(result.sessions);
    setTotalCount(result.totalCount);
  }, [facilityId, status, coachId, programId, page]);

  useEffect(() => {
    let cancelled = false;
    setRows(null);
    load().catch((e) => {
      if (cancelled) return;
      setError(e instanceof ServiceError ? e.message : "Unable to load sessions.");
      setRows([]);
    });
    return () => {
      cancelled = true;
    };
  }, [load]);

  return (
    <div className="space-y-4">
      <PageHeader
        title="Coaching Sessions"
        subtitle="Every scheduled, completed and cancelled coaching session."
        action={
          canCreate && (
            <Button asChild size="sm">
              <Link href="/coaching/sessions/new">
                <Plus className="h-4 w-4" aria-hidden /> New Session
              </Link>
            </Button>
          )
        }
      />

      <Card className="p-4">
        <div className="flex flex-wrap items-end gap-3">
          <Filter label="Status" value={status} onChange={setStatus} options={[{ value: ALL, label: "All Status" }, ...(Object.keys(SESSION_STATUS_LABEL) as SessionStatus[]).map((s) => ({ value: s, label: SESSION_STATUS_LABEL[s] }))]} />
          <Filter label="Coach" value={coachId} onChange={setCoachId} options={[{ value: ALL, label: "All Coaches" }, ...coaches.map((c) => ({ value: c.id, label: c.name }))]} />
          <Filter label="Program" value={programId} onChange={setProgramId} options={[{ value: ALL, label: "All Programs" }, ...programs.map((p) => ({ value: p.id, label: p.name }))]} />
        </div>
      </Card>

      <Card className="p-0">
        {error ? (
          <ErrorState message={error} onRetry={() => void load()} />
        ) : rows === null ? (
          <TableSkeleton />
        ) : rows.length === 0 ? (
          <EmptyState message="No sessions match these filters." />
        ) : (
          <div className="overflow-x-auto">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>When</TableHead>
                  <TableHead>Program</TableHead>
                  <TableHead>Coach</TableHead>
                  <TableHead>Court</TableHead>
                  <TableHead className="text-right">Students</TableHead>
                  <TableHead>Status</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {rows.map((s) => (
                  <TableRow key={s.id}>
                    <TableCell className="whitespace-nowrap text-muted-foreground">{fmtDateTime(s.startAt)}</TableCell>
                    <TableCell>
                      <Link href={`/coaching/sessions/${s.id}`} className="font-medium hover:underline">
                        {s.programName}
                      </Link>
                    </TableCell>
                    <TableCell className="text-muted-foreground">{s.coachName}</TableCell>
                    <TableCell className="text-muted-foreground">{s.courtName}</TableCell>
                    <TableCell className="text-right tabular-nums">
                      {s.enrolledCount} / {s.capacity}
                    </TableCell>
                    <TableCell>{sessionStatusBadge(s.status)}</TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </div>
        )}
        <Pagination page={page} pageSize={PAGE_SIZE} totalCount={totalCount} onPage={setPage} unit="sessions" />
      </Card>
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
