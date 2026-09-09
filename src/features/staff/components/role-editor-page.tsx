"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import { AlertTriangle, ChevronRight } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { Skeleton } from "@/components/ui/skeleton";
import { cn } from "@/lib/utils";
import { ServiceError } from "@/services/shared/service-error";
import { getStaffService } from "@/services/staff";
import { usePermissionContext } from "@/features/auth/context/permission-provider";
import { PermissionDenied } from "@/features/staff/components/permission-denied";
import type { Permission, RoleDetail } from "@/features/staff/types";

const STEPS = ["Role Details", "Permissions", "Review"] as const;

export function RoleEditorPage({ mode, roleId }: { mode: "create" | "edit"; roleId?: string }) {
  const perms = usePermissionContext();
  const router = useRouter();
  const params = useSearchParams();
  const facilityId = perms?.facilityId ?? null;
  const templateId = params.get("template");

  const [step, setStep] = useState(0);
  const [catalog, setCatalog] = useState<Permission[]>([]);
  const [existing, setExisting] = useState<RoleDetail | null>(null);
  const [activeModule, setActiveModule] = useState<string>("Dashboard");
  const [state, setState] = useState<"loading" | "ready" | "error">("loading");
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const [name, setName] = useState("");
  const [description, setDescription] = useState("");
  const [isActive, setIsActive] = useState(true);
  const [selected, setSelected] = useState<Set<string>>(new Set());

  const load = useCallback(async () => {
    if (!facilityId) return;
    try {
      const c = await getStaffService().listPermissions();
      setCatalog(c);
      setActiveModule(c[0]?.module ?? "Dashboard");
      if (mode === "edit" && roleId) {
        const r = await getStaffService().getRole(roleId);
        setExisting(r);
        setName(r.name);
        setDescription(r.description ?? "");
        setIsActive(r.isActive);
        setSelected(new Set(r.permissionKeys));
      } else if (templateId) {
        const t = (await getStaffService().listRoleTemplates()).find((x) => x.id === templateId);
        if (t) {
          setName(t.name);
          setDescription(t.description ?? "");
          setSelected(new Set(t.permissionKeys));
        }
      }
      setState("ready");
    } catch (e) {
      setError(e instanceof ServiceError ? e.message : "Unable to load the role editor.");
      setState("error");
    }
  }, [facilityId, mode, roleId, templateId]);

  useEffect(() => {
    void load();
  }, [load]);

  const byModule = useMemo(() => {
    const m = new Map<string, Permission[]>();
    for (const p of catalog) m.set(p.module, [...(m.get(p.module) ?? []), p]);
    return m;
  }, [catalog]);
  const modules = [...byModule.keys()];
  const heldByCaller = perms?.permissions ?? new Set<string>();

  const canManage = perms?.can("USERS_MANAGE_ROLES") ?? false;
  const dangerousSelected = catalog.filter((p) => p.isDangerous && selected.has(p.key));

  if (!canManage) return <PermissionDenied message="You don't have permission to manage roles." />;
  if (state === "loading") return <Skeleton className="h-96 w-full rounded-xl" />;
  if (state === "error")
    return (
      <div className="space-y-3">
        <p className="text-sm text-destructive">{error}</p>
        <Button variant="outline" onClick={() => void load()}>
          Try again
        </Button>
      </div>
    );

  function toggle(key: string) {
    setSelected((prev) => {
      const n = new Set(prev);
      if (n.has(key)) n.delete(key);
      else n.add(key);
      return n;
    });
  }
  function setModule(mod: string, on: boolean) {
    setSelected((prev) => {
      const n = new Set(prev);
      for (const p of byModule.get(mod) ?? []) {
        if (on) n.add(p.key);
        else n.delete(p.key);
      }
      return n;
    });
  }

  async function save() {
    if (!facilityId || busy) return;
    if (!name.trim()) {
      setError("A role needs a name.");
      setStep(0);
      return;
    }
    // Escalation guard mirrored client-side for a friendlier message; the DB enforces it.
    const disallowed = [...selected].filter((k) => perms?.baseRole !== "owner" && !heldByCaller.has(k));
    if (disallowed.length) {
      setError("You can only grant permissions you hold yourself.");
      setStep(1);
      return;
    }
    setBusy(true);
    setError(null);
    try {
      if (mode === "create") {
        await getStaffService().createRole({
          facilityId,
          name: name.trim(),
          description: description.trim() || null,
          permissionKeys: [...selected],
        });
      } else if (roleId) {
        await getStaffService().updateRole({
          roleId,
          facilityId,
          name: existing?.isSystem ? null : name.trim(),
          description: existing?.isSystem ? null : description.trim() || null,
          isActive,
          permissionKeys: [...selected],
          expectedVersion: existing?.version ?? null,
        });
      }
      router.push("/users-roles/roles");
      router.refresh();
    } catch (e) {
      setError(e instanceof ServiceError ? e.message : "Could not save this role.");
    } finally {
      setBusy(false);
    }
  }

  const modulePerms = byModule.get(activeModule) ?? [];

  return (
    <div className="mx-auto max-w-3xl space-y-4">
      <nav aria-label="Breadcrumb" className="flex items-center gap-1 text-xs text-muted-foreground">
        <Link href="/users-roles/staff" className="hover:text-foreground">
          Users &amp; Roles
        </Link>
        <ChevronRight className="h-3 w-3" aria-hidden />
        <Link href="/users-roles/roles" className="hover:text-foreground">
          Roles &amp; Permissions
        </Link>
        <ChevronRight className="h-3 w-3" aria-hidden />
        <span className="text-foreground">{mode === "create" ? "Create Role" : "Edit Role"}</span>
      </nav>

      <div>
        <h1 className="text-xl font-semibold">{mode === "create" ? "Create Role" : `Edit ${existing?.name ?? "Role"}`}</h1>
        <p className="text-sm text-muted-foreground">Configure what this role can do in your facility.</p>
      </div>

      <ol className="flex items-center gap-2 text-xs">
        {STEPS.map((s, i) => (
          <li key={s} className="flex items-center gap-2">
            <span
              className={cn(
                "flex h-6 w-6 items-center justify-center rounded-full border text-[11px] font-semibold",
                i === step ? "border-primary bg-primary text-primary-foreground" : i < step ? "border-primary bg-primary/10 text-primary" : "border-border text-muted-foreground",
              )}
            >
              {i + 1}
            </span>
            <span className={cn(i === step ? "font-medium text-foreground" : "text-muted-foreground")}>{s}</span>
            {i < STEPS.length - 1 && <ChevronRight className="h-3 w-3 text-muted-foreground" aria-hidden />}
          </li>
        ))}
      </ol>

      <Card className="p-5">
        {step === 0 && (
          <div className="space-y-3">
            <div className="space-y-1.5">
              <Label htmlFor="r-name" className="text-xs font-medium">
                Role name
              </Label>
              <Input id="r-name" value={name} onChange={(e) => setName(e.target.value)} disabled={existing?.isSystem} />
              {existing?.isSystem && (
                <p className="text-xs text-muted-foreground">
                  System role names can&apos;t be changed — you can still adjust its permissions for this facility.
                </p>
              )}
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="r-desc" className="text-xs font-medium">
                Description
              </Label>
              <Textarea id="r-desc" rows={2} value={description} onChange={(e) => setDescription(e.target.value)} disabled={existing?.isSystem} />
            </div>
            {mode === "edit" && !existing?.isSystem && (
              <label className="flex items-center gap-2 text-sm">
                <input type="checkbox" checked={isActive} onChange={(e) => setIsActive(e.target.checked)} className="h-4 w-4" />
                Active — staff can be assigned this role
              </label>
            )}
          </div>
        )}

        {step === 1 && (
          <div className="grid gap-4 sm:grid-cols-[10rem_1fr]">
            <ul className="space-y-0.5 text-sm">
              {modules.map((m) => {
                const list = byModule.get(m) ?? [];
                const on = list.filter((p) => selected.has(p.key)).length;
                return (
                  <li key={m}>
                    <button
                      type="button"
                      onClick={() => setActiveModule(m)}
                      className={cn(
                        "flex w-full items-center justify-between rounded-md px-2 py-1.5 text-left transition-colors",
                        activeModule === m ? "bg-primary/10 font-medium text-primary" : "text-muted-foreground hover:bg-accent",
                      )}
                    >
                      <span>{m}</span>
                      {on > 0 && <span className="text-[11px]">{on}</span>}
                    </button>
                  </li>
                );
              })}
            </ul>
            <div className="space-y-2">
              <div className="flex items-center justify-between">
                <h3 className="text-sm font-semibold">{activeModule} permissions</h3>
                <div className="flex gap-1.5">
                  <Button type="button" size="sm" variant="outline" onClick={() => setModule(activeModule, true)}>
                    Select all
                  </Button>
                  <Button type="button" size="sm" variant="outline" onClick={() => setModule(activeModule, false)}>
                    Clear
                  </Button>
                </div>
              </div>
              <ul className="space-y-1.5">
                {modulePerms.map((p) => {
                  const cannotGrant = perms?.baseRole !== "owner" && !heldByCaller.has(p.key);
                  return (
                    <li key={p.key}>
                      <label className={cn("flex items-start gap-2 rounded-md border border-border p-2.5 text-sm", cannotGrant && "opacity-50")}>
                        <input
                          type="checkbox"
                          className="mt-0.5 h-4 w-4"
                          checked={selected.has(p.key)}
                          disabled={cannotGrant}
                          onChange={() => toggle(p.key)}
                        />
                        <span>
                          <span className="flex items-center gap-1.5 font-medium">
                            {p.label}
                            {p.isDangerous && <Badge variant="warning">Sensitive</Badge>}
                          </span>
                          {p.description && <span className="block text-xs text-muted-foreground">{p.description}</span>}
                          {cannotGrant && (
                            <span className="block text-xs text-muted-foreground">
                              You don&apos;t hold this permission yourself.
                            </span>
                          )}
                        </span>
                      </label>
                    </li>
                  );
                })}
              </ul>
            </div>
          </div>
        )}

        {step === 2 && (
          <div className="space-y-3 text-sm">
            <div>
              <p className="text-xs text-muted-foreground">Role</p>
              <p className="font-medium">{name || "—"}</p>
            </div>
            <div>
              <p className="text-xs text-muted-foreground">Permissions ({selected.size})</p>
              <div className="mt-1 flex flex-wrap gap-1.5">
                {catalog.filter((p) => selected.has(p.key)).map((p) => (
                  <Badge key={p.key} variant={p.isDangerous ? "warning" : "secondary"}>
                    {p.label}
                  </Badge>
                ))}
                {selected.size === 0 && <span className="text-xs text-muted-foreground">No permissions selected.</span>}
              </div>
            </div>
            {dangerousSelected.length > 0 && (
              <div className="flex items-start gap-2 rounded-md border border-warning/40 bg-warning/10 p-3 text-xs">
                <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0 text-warning" aria-hidden />
                <span>
                  This role includes sensitive permissions: {dangerousSelected.map((p) => p.label).join(", ")}. Anyone
                  assigned this role will be able to perform these actions.
                </span>
              </div>
            )}
          </div>
        )}

        {error && (
          <p role="alert" className="mt-3 text-sm text-destructive">
            {error}
          </p>
        )}

        <div className="mt-4 flex items-center justify-between">
          <Button
            type="button"
            variant="outline"
            disabled={busy}
            onClick={() => (step === 0 ? router.push("/users-roles/roles") : setStep((s) => s - 1))}
          >
            {step === 0 ? "Cancel" : "Back"}
          </Button>
          {step < STEPS.length - 1 ? (
            <Button type="button" onClick={() => setStep((s) => s + 1)}>
              Next <ChevronRight className="h-4 w-4" aria-hidden />
            </Button>
          ) : (
            <Button type="button" onClick={save} disabled={busy}>
              {busy ? "Saving…" : mode === "create" ? "Create role" : "Save changes"}
            </Button>
          )}
        </div>
      </Card>
    </div>
  );
}
