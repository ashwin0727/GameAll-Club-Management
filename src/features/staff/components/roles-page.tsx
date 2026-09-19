"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import Link from "next/link";
import { Plus, Sparkles } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { cn } from "@/lib/utils";
import { ServiceError } from "@/services/shared/service-error";
import { getStaffService } from "@/services/staff";
import { usePermissionContext } from "@/features/auth/context/permission-provider";
import { PermissionDenied } from "@/features/staff/components/permission-denied";
import type { Permission, RoleRow, RoleTemplate } from "@/features/staff/types";

export function RolesPage() {
  const perms = usePermissionContext();
  const facilityId = perms?.facilityId ?? null;
  const canManage = perms?.can("USERS_MANAGE_ROLES") ?? false;

  const [tab, setTab] = useState<"roles" | "permissions">("roles");
  const [roles, setRoles] = useState<RoleRow[] | null>(null);
  const [templates, setTemplates] = useState<RoleTemplate[]>([]);
  const [catalog, setCatalog] = useState<Permission[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState<string | null>(null);

  const load = useCallback(async () => {
    if (!facilityId) return;
    setError(null);
    try {
      const [r, c] = await Promise.all([getStaffService().listRoles(facilityId), getStaffService().listPermissions()]);
      setRoles(r);
      setCatalog(c);
      if (canManage) setTemplates(await getStaffService().listRoleTemplates());
    } catch (e) {
      setError(e instanceof ServiceError ? e.message : "Unable to load roles.");
      setRoles([]);
    }
  }, [facilityId, canManage]);

  useEffect(() => {
    void load();
  }, [load]);

  const catalogByModule = useMemo(() => {
    const m = new Map<string, Permission[]>();
    for (const p of catalog) m.set(p.module, [...(m.get(p.module) ?? []), p]);
    return [...m.entries()];
  }, [catalog]);

  if (!perms?.can("USERS_VIEW")) return <PermissionDenied message="You don't have permission to view roles." />;

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h1 className="text-xl font-semibold">Roles &amp; Permissions</h1>
          <p className="text-sm text-muted-foreground">Manage roles and module permissions for your facility.</p>
        </div>
        {canManage && (
          <Button asChild size="sm">
            <Link href="/users-roles/roles/new">
              <Plus className="h-4 w-4" aria-hidden /> Create Role
            </Link>
          </Button>
        )}
      </div>

      <div className="flex gap-1 border-b border-border text-sm">
        <TabButton active={tab === "roles"} onClick={() => setTab("roles")}>
          Roles {roles ? `(${roles.length})` : ""}
        </TabButton>
        <TabButton active={tab === "permissions"} onClick={() => setTab("permissions")}>
          Permissions
        </TabButton>
      </div>

      {error && <p className="text-sm text-destructive">{error}</p>}

      {tab === "roles" && (
        <>
          <Card className="p-0">
            {roles === null ? (
              <div className="space-y-2 p-4">
                {Array.from({ length: 5 }).map((_, i) => (
                  <Skeleton key={i} className="h-10 w-full rounded-lg" />
                ))}
              </div>
            ) : (
              <div className="overflow-x-auto">
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>Role Name</TableHead>
                      <TableHead>Description</TableHead>
                      <TableHead className="text-right">Staff</TableHead>
                      <TableHead>Status</TableHead>
                      <TableHead />
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {roles.map((r) => (
                      <TableRow key={r.id}>
                        <TableCell className="font-medium">
                          {r.name}
                          {r.isSystem && <Badge variant="outline" className="ml-2">System</Badge>}
                        </TableCell>
                        <TableCell className="max-w-[22rem] truncate text-muted-foreground">{r.description ?? "—"}</TableCell>
                        <TableCell className="text-right tabular-nums">{r.staffCount}</TableCell>
                        <TableCell>
                          <Badge variant={r.isActive ? "success" : "destructive"}>{r.isActive ? "Active" : "Inactive"}</Badge>
                        </TableCell>
                        <TableCell className="text-right">
                          {canManage ? (
                            <div className="flex justify-end gap-1.5">
                              <Button asChild size="sm" variant="outline">
                                <Link href={`/users-roles/roles/${r.id}/edit`}>Edit</Link>
                              </Button>
                              {r.isCustom && r.staffCount === 0 && (
                                <Button
                                  type="button"
                                  size="sm"
                                  variant="outline"
                                  disabled={busy === r.id}
                                  onClick={async () => {
                                    setBusy(r.id);
                                    try {
                                      await getStaffService().deleteRole(r.id, facilityId!);
                                      await load();
                                    } catch (e) {
                                      setError(e instanceof ServiceError ? e.message : "Could not delete this role.");
                                    } finally {
                                      setBusy(null);
                                    }
                                  }}
                                >
                                  {busy === r.id ? "Deleting…" : "Delete"}
                                </Button>
                              )}
                            </div>
                          ) : (
                            <Button asChild size="sm" variant="outline">
                              <Link href={`/users-roles/roles/${r.id}/edit`}>View</Link>
                            </Button>
                          )}
                        </TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              </div>
            )}
          </Card>

          {canManage && templates.length > 0 && (
            <Card className="p-4">
              <div className="flex items-center gap-2">
                <Sparkles className="h-4 w-4 text-primary" aria-hidden />
                <h2 className="text-sm font-semibold">Need a custom role?</h2>
              </div>
              <p className="mt-1 text-sm text-muted-foreground">
                Start from a pre-configured template and adjust the permissions.
              </p>
              <div className="mt-3 flex flex-wrap gap-2">
                {templates.map((t) => (
                  <Button key={t.id} asChild variant="outline" size="sm">
                    <Link href={`/users-roles/roles/new?template=${t.id}`}>{t.name}</Link>
                  </Button>
                ))}
              </div>
            </Card>
          )}
        </>
      )}

      {tab === "permissions" && (
        <Card className="space-y-4 p-4">
          <p className="text-sm text-muted-foreground">
            Every permission the platform can grant, grouped by module. Assign them to roles on the Roles tab.
          </p>
          {catalogByModule.map(([mod, list]) => (
            <div key={mod}>
              <p className="text-xs font-semibold text-muted-foreground">{mod}</p>
              <ul className="mt-1 space-y-1">
                {list.map((p) => (
                  <li key={p.key} className="flex items-start gap-2 text-sm">
                    <span className={cn("mt-1 h-1.5 w-1.5 shrink-0 rounded-full", p.isDangerous ? "bg-warning" : "bg-muted-foreground/40")} />
                    <span>
                      <span className="font-medium">{p.label}</span>
                      {p.description && <span className="block text-xs text-muted-foreground">{p.description}</span>}
                    </span>
                  </li>
                ))}
              </ul>
            </div>
          ))}
        </Card>
      )}
    </div>
  );
}

function TabButton({ active, onClick, children }: { active: boolean; onClick: () => void; children: React.ReactNode }) {
  return (
    <button
      type="button"
      onClick={onClick}
      className={cn(
        "border-b-2 px-3 py-2 font-medium transition-colors",
        active ? "border-primary text-foreground" : "border-transparent text-muted-foreground hover:text-foreground",
      )}
    >
      {children}
    </button>
  );
}
