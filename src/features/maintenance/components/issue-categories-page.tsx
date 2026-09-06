"use client";

import { useCallback, useEffect, useState } from "react";
import { Plus, Search } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Skeleton } from "@/components/ui/skeleton";
import { StatCard } from "@/components/shared/stat-card";
import { maintenanceIcon } from "@/features/maintenance/icons";
import type { MaintenanceIssueCategory } from "@/features/maintenance/types";
import { CategoryFormDialog } from "@/features/maintenance/components/category-form-dialog";
import { getFacilityService } from "@/services/facility";
import { getMaintenanceService } from "@/services/maintenance";
import { ServiceError } from "@/services/shared/service-error";

/**
 * Issue Categories — the taxonomy every Maintenance Ticket is classified
 * by. Shared defaults (facility_id null) plus a facility's own additions;
 * referenced categories are deactivated, never deleted (spec §9/§29).
 */
export function IssueCategoriesPage() {
  const [facilityId, setFacilityId] = useState<string | null>(null);
  const [loadState, setLoadState] = useState<"loading" | "ready" | "none" | "error">("loading");
  const [categories, setCategories] = useState<MaintenanceIssueCategory[] | null>(null);
  const [search, setSearch] = useState("");
  const [statusFilter, setStatusFilter] = useState<"ALL" | "ACTIVE" | "INACTIVE">("ALL");
  const [dialogOpen, setDialogOpen] = useState(false);
  const [editing, setEditing] = useState<MaintenanceIssueCategory | null>(null);
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

  const load = useCallback(async () => {
    if (!facilityId) return;
    setError(null);
    try {
      const rows = await getMaintenanceService().listIssueCategories(facilityId, true);
      setCategories(rows);
    } catch (e) {
      setCategories([]);
      setError(e instanceof ServiceError ? e.message : "Unable to load issue categories.");
    }
  }, [facilityId]);

  useEffect(() => {
    void load();
  }, [load]);

  if (loadState === "loading") return <Skeleton className="h-96 w-full rounded-xl" />;
  if (loadState === "none") return <p className="text-sm text-muted-foreground">No facility found for this account yet.</p>;
  if (loadState === "error") return <p className="text-sm text-destructive">Unable to load this page. Please try again.</p>;

  const all = categories ?? [];
  const filtered = all.filter((c) => {
    if (statusFilter === "ACTIVE" && !c.isActive) return false;
    if (statusFilter === "INACTIVE" && c.isActive) return false;
    if (search.trim() && !c.name.toLowerCase().includes(search.trim().toLowerCase())) return false;
    return true;
  });
  const totalIssues = all.reduce((sum, c) => sum + c.issueCount, 0);

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h1 className="text-xl font-semibold">Issue Categories</h1>
          <p className="text-sm text-muted-foreground">Manage and organize maintenance issue categories for better tracking and reporting.</p>
        </div>
        <Button
          onClick={() => {
            setEditing(null);
            setDialogOpen(true);
          }}
        >
          <Plus className="mr-1.5 h-4 w-4" /> Add Issue Category
        </Button>
      </div>

      <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
        <StatCard label="Total Categories" value={String(all.length)} accent="#5B6CFF" />
        <StatCard label="Active" value={String(all.filter((c) => c.isActive).length)} accent="#00D084" />
        <StatCard label="Inactive" value={String(all.filter((c) => !c.isActive).length)} accent="#AAB5C7" />
        <StatCard label="Total Issues This Month" value={String(totalIssues)} accent="#8B5CF6" />
      </div>

      {error && <p className="text-sm text-destructive">{error}</p>}

      <div className="flex flex-wrap items-center gap-2">
        <div className="relative max-w-xs flex-1">
          <Search className="pointer-events-none absolute left-2.5 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" aria-hidden />
          <Input value={search} onChange={(e) => setSearch(e.target.value)} placeholder="Search categories…" className="pl-8" />
        </div>
        <div className="flex gap-1">
          {(["ALL", "ACTIVE", "INACTIVE"] as const).map((s) => (
            <button
              key={s}
              onClick={() => setStatusFilter(s)}
              className={
                "rounded-md px-2.5 py-1.5 text-xs font-medium " +
                (statusFilter === s ? "bg-primary text-primary-foreground" : "bg-secondary text-muted-foreground hover:bg-secondary/80")
              }
            >
              {s === "ALL" ? "All Status" : s === "ACTIVE" ? "Active" : "Inactive"}
            </button>
          ))}
        </div>
      </div>

      {categories === null ? (
        <Skeleton className="h-64 w-full rounded-xl" />
      ) : filtered.length === 0 ? (
        <Card className="p-8 text-center text-sm text-muted-foreground">No issue categories match this filter.</Card>
      ) : (
        <Card className="overflow-hidden p-0">
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead className="border-b border-border bg-secondary/40 text-left text-xs text-muted-foreground">
                <tr>
                  <th className="px-4 py-2.5 font-medium">#</th>
                  <th className="px-4 py-2.5 font-medium">Category Name</th>
                  <th className="px-4 py-2.5 font-medium">Description</th>
                  <th className="px-4 py-2.5 font-medium">Issue Count</th>
                  <th className="px-4 py-2.5 font-medium">Status</th>
                  <th className="px-4 py-2.5 font-medium text-right">Actions</th>
                </tr>
              </thead>
              <tbody>
                {filtered.map((c, i) => {
                  const Icon = maintenanceIcon(c.icon);
                  return (
                    <tr key={c.id} className="border-b border-border last:border-0 hover:bg-secondary/20">
                      <td className="px-4 py-2.5 text-muted-foreground">{i + 1}</td>
                      <td className="px-4 py-2.5">
                        <div className="flex items-center gap-2">
                          <span className="flex h-7 w-7 shrink-0 items-center justify-center rounded-md bg-primary/15 text-primary">
                            <Icon className="h-3.5 w-3.5" aria-hidden />
                          </span>
                          <span className="font-medium">{c.name}</span>
                          {c.isShared && <Badge variant="outline" className="text-[10px]">Default</Badge>}
                        </div>
                      </td>
                      <td className="max-w-[280px] truncate px-4 py-2.5 text-muted-foreground">{c.description || "—"}</td>
                      <td className="px-4 py-2.5">{c.issueCount}</td>
                      <td className="px-4 py-2.5">
                        <Badge className={c.isActive ? "border-transparent bg-success/15 text-success" : "border-transparent bg-secondary text-muted-foreground"}>
                          {c.isActive ? "Active" : "Inactive"}
                        </Badge>
                      </td>
                      <td className="px-4 py-2.5 text-right">
                        <Button
                          variant="ghost"
                          size="sm"
                          disabled={c.isShared}
                          title={c.isShared ? "Default categories cannot be edited" : "Edit"}
                          onClick={() => {
                            setEditing(c);
                            setDialogOpen(true);
                          }}
                        >
                          Edit
                        </Button>
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        </Card>
      )}

      {facilityId && (
        <CategoryFormDialog facilityId={facilityId} category={editing} open={dialogOpen} onOpenChange={setDialogOpen} onSaved={() => void load()} />
      )}
    </div>
  );
}
