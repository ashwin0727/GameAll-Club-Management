"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import Link from "next/link";
import { ChevronLeft, ChevronRight, Plus, Search } from "lucide-react";
import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Skeleton } from "@/components/ui/skeleton";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { cn } from "@/lib/utils";
import { ServiceError } from "@/services/shared/service-error";
import { getStaffService } from "@/services/staff";
import { usePermissionContext } from "@/features/auth/context/permission-provider";
import type { RoleRow, StaffRow, StaffStatus } from "@/features/staff/types";

const PAGE_SIZE = 20;
const ALL = "ALL";

export function statusBadge(status: StaffStatus) {
  const map = { ACTIVE: "success", INACTIVE: "destructive", INVITED: "warning" } as const;
  const label = { ACTIVE: "Active", INACTIVE: "Inactive", INVITED: "Pending" }[status];
  return <Badge variant={map[status]}>{label}</Badge>;
}

export function initials(name: string): string {
  const parts = name.trim().split(/\s+/).filter(Boolean);
  if (!parts.length) return "?";
  const first = parts[0] ?? "";
  const last = parts.length > 1 ? (parts[parts.length - 1] ?? "") : "";
  return ((first[0] ?? "") + (last[0] ?? "")).toUpperCase() || "?";
}

export function fmtDate(iso: string | null): string {
  if (!iso) return "—";
  return new Date(iso).toLocaleDateString("en-IN", { day: "2-digit", month: "short", year: "numeric" });
}

export function fmtRelative(iso: string | null): string {
  if (!iso) return "—";
  const diff = Date.now() - new Date(iso).getTime();
  const h = diff / 3_600_000;
  if (h < 1) return "Just now";
  if (h < 24) return new Date(iso).toLocaleTimeString("en-IN", { hour: "2-digit", minute: "2-digit" });
  if (h < 48) return "Yesterday";
  return fmtDate(iso);
}

export function StaffPage() {
  const perms = usePermissionContext();
  const facilityId = perms?.facilityId ?? null;

  const [search, setSearch] = useState("");
  const [debounced, setDebounced] = useState("");
  const [status, setStatus] = useState<string>(ALL);
  const [roleId, setRoleId] = useState<string>(ALL);
  const [page, setPage] = useState(0);

  const [roles, setRoles] = useState<RoleRow[]>([]);
  const [staff, setStaff] = useState<StaffRow[] | null>(null);
  const [totalCount, setTotalCount] = useState(0);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    const t = setTimeout(() => setDebounced(search), 300);
    return () => clearTimeout(t);
  }, [search]);
  useEffect(() => setPage(0), [debounced, status, roleId]);

  useEffect(() => {
    if (!facilityId) return;
    getStaffService()
      .listRoles(facilityId)
      .then(setRoles)
      .catch(() => setRoles([]));
  }, [facilityId]);

  const load = useCallback(async () => {
    if (!facilityId) return;
    setError(null);
    const result = await getStaffService().listStaff({
      facilityId,
      filters: {
        search: debounced,
        status: status === ALL ? null : (status as StaffStatus),
        roleId: roleId === ALL ? null : roleId,
      },
      limit: PAGE_SIZE,
      offset: page * PAGE_SIZE,
    });
    setStaff(result.staff);
    setTotalCount(result.totalCount);
  }, [facilityId, debounced, status, roleId, page]);

  useEffect(() => {
    let cancelled = false;
    setStaff(null);
    load().catch((e) => {
      if (cancelled) return;
      setError(e instanceof ServiceError ? e.message : "Unable to load staff.");
      setStaff([]);
    });
    return () => {
      cancelled = true;
    };
  }, [load]);

  const counts = useMemo(() => {
    const all = staff ?? [];
    return {
      all: totalCount,
      active: all.filter((s) => s.status === "ACTIVE").length,
      inactive: all.filter((s) => s.status === "INACTIVE").length,
      pending: all.filter((s) => s.status === "INVITED").length,
    };
  }, [staff, totalCount]);

  const totalPages = Math.max(1, Math.ceil(totalCount / PAGE_SIZE));
  const canAdd = perms?.can("USERS_CREATE") ?? false;

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h1 className="text-xl font-semibold">Staff</h1>
          <p className="text-sm text-muted-foreground">Manage your facility staff, roles and access.</p>
        </div>
        {canAdd && (
          <Button asChild size="sm">
            <Link href="/users-roles/staff/add">
              <Plus className="h-4 w-4" aria-hidden /> Add Staff
            </Link>
          </Button>
        )}
      </div>

      <Card className="p-4">
        <div className="flex flex-wrap items-end gap-3">
          <div className="relative min-w-[14rem] flex-1">
            <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" aria-hidden />
            <Input
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              placeholder="Search staff by name, email or phone…"
              aria-label="Search staff"
              className="h-10 pl-9"
            />
          </div>
          <FilterSelect
            label="Role"
            value={roleId}
            onChange={setRoleId}
            options={[{ value: ALL, label: "All Roles" }, ...roles.map((r) => ({ value: r.id, label: r.name }))]}
          />
          <FilterSelect
            label="Status"
            value={status}
            onChange={setStatus}
            options={[
              { value: ALL, label: "All Status" },
              { value: "ACTIVE", label: "Active" },
              { value: "INACTIVE", label: "Inactive" },
              { value: "INVITED", label: "Pending" },
            ]}
          />
        </div>
        <div className="mt-3 flex flex-wrap gap-2">
          <QuickTab active={status === ALL} onClick={() => setStatus(ALL)}>
            All ({counts.all})
          </QuickTab>
          <QuickTab active={status === "ACTIVE"} onClick={() => setStatus("ACTIVE")}>
            Active
          </QuickTab>
          <QuickTab active={status === "INACTIVE"} onClick={() => setStatus("INACTIVE")}>
            Inactive
          </QuickTab>
          <QuickTab active={status === "INVITED"} onClick={() => setStatus("INVITED")}>
            Pending Invitation
          </QuickTab>
        </div>
      </Card>

      <Card className="p-0">
        {error ? (
          <div className="p-10 text-center">
            <p className="text-sm font-semibold text-destructive">Unable to load staff</p>
            <p className="mt-1 text-sm text-muted-foreground">{error}</p>
            <Button type="button" variant="outline" className="mt-4" onClick={() => void load()}>
              Try again
            </Button>
          </div>
        ) : staff === null ? (
          <div className="space-y-2 p-4">
            {Array.from({ length: 6 }).map((_, i) => (
              <Skeleton key={i} className="h-12 w-full rounded-lg" />
            ))}
          </div>
        ) : staff.length === 0 ? (
          <div className="p-10 text-center text-sm text-muted-foreground">
            No staff match these filters.
          </div>
        ) : (
          <>
            <div className="hidden overflow-x-auto md:block">
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Staff</TableHead>
                    <TableHead>Role</TableHead>
                    <TableHead>Facility Access</TableHead>
                    <TableHead>Status</TableHead>
                    <TableHead>Last Active</TableHead>
                    <TableHead>Joined</TableHead>
                    <TableHead />
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {staff.map((s) => (
                    <TableRow key={s.assignmentId}>
                      <TableCell>
                        <Link href={`/users-roles/staff/${s.userId}`} className="flex items-center gap-3">
                          <Avatar className="h-8 w-8">
                            {s.avatarUrl && <AvatarImage src={s.avatarUrl} alt="" />}
                            <AvatarFallback className="text-xs">{initials(s.fullName)}</AvatarFallback>
                          </Avatar>
                          <span className="min-w-0">
                            <span className="block truncate font-medium hover:underline">{s.fullName}</span>
                            <span className="block truncate text-xs text-muted-foreground">{s.email}</span>
                          </span>
                        </Link>
                      </TableCell>
                      <TableCell>{s.roleName}</TableCell>
                      <TableCell className="text-muted-foreground">
                        {s.facilityCount > 1 ? `${s.facilityCount} Facilities` : perms?.facilityName ?? "—"}
                      </TableCell>
                      <TableCell>{statusBadge(s.status)}</TableCell>
                      <TableCell className="text-muted-foreground">{fmtRelative(s.lastLoginAt)}</TableCell>
                      <TableCell className="text-muted-foreground">{fmtDate(s.joinedAt)}</TableCell>
                      <TableCell className="text-right">
                        <Button asChild size="sm" variant="outline">
                          <Link href={`/users-roles/staff/${s.userId}`}>View</Link>
                        </Button>
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </div>

            <ul className="divide-y divide-border md:hidden">
              {staff.map((s) => (
                <li key={s.assignmentId} className="p-3">
                  <Link href={`/users-roles/staff/${s.userId}`} className="flex items-center gap-3">
                    <Avatar className="h-9 w-9">
                      {s.avatarUrl && <AvatarImage src={s.avatarUrl} alt="" />}
                      <AvatarFallback className="text-xs">{initials(s.fullName)}</AvatarFallback>
                    </Avatar>
                    <span className="min-w-0 flex-1">
                      <span className="block truncate font-medium">{s.fullName}</span>
                      <span className="block truncate text-xs text-muted-foreground">
                        {s.roleName} · {s.email}
                      </span>
                    </span>
                    {statusBadge(s.status)}
                  </Link>
                </li>
              ))}
            </ul>
          </>
        )}

        {totalCount > 0 && (
          <div className="flex items-center justify-between gap-3 border-t border-border p-3">
            <p className="text-xs text-muted-foreground">
              Showing {page * PAGE_SIZE + 1} to {Math.min((page + 1) * PAGE_SIZE, totalCount)} of {totalCount} staff members
            </p>
            <div className="flex items-center gap-1">
              <Button type="button" variant="outline" size="sm" aria-label="Previous page" disabled={page === 0} onClick={() => setPage((p) => p - 1)}>
                <ChevronLeft className="h-4 w-4" aria-hidden />
              </Button>
              <span className="px-2 text-xs text-muted-foreground">{page + 1} / {totalPages}</span>
              <Button type="button" variant="outline" size="sm" aria-label="Next page" disabled={page + 1 >= totalPages} onClick={() => setPage((p) => p + 1)}>
                <ChevronRight className="h-4 w-4" aria-hidden />
              </Button>
            </div>
          </div>
        )}
      </Card>
    </div>
  );
}

function FilterSelect({
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
        <SelectTrigger className="w-[11rem]">
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

function QuickTab({ active, onClick, children }: { active: boolean; onClick: () => void; children: React.ReactNode }) {
  return (
    <button
      type="button"
      onClick={onClick}
      className={cn(
        "rounded-full border px-3 py-1 text-xs font-medium transition-colors",
        active ? "border-primary bg-primary/10 text-primary" : "border-border text-muted-foreground hover:bg-accent",
      )}
    >
      {children}
    </button>
  );
}
