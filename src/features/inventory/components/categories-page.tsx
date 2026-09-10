"use client";

import { useCallback, useEffect, useState } from "react";
import { Plus } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import {
  Dialog,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { ServiceError } from "@/services/shared/service-error";
import { getInventoryService } from "@/services/inventory";
import { usePermissionContext } from "@/features/auth/context/permission-provider";
import type { CategoryRow } from "@/features/inventory/types";
import { EmptyState, ErrorState, PageHeader, TableSkeleton, money } from "@/features/inventory/components/shared";

export function CategoriesPage() {
  const perms = usePermissionContext();
  const facilityId = perms?.facilityId ?? null;

  const [rows, setRows] = useState<CategoryRow[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [editing, setEditing] = useState<CategoryRow | "new" | null>(null);

  const canManage = perms?.can("INVENTORY_MANAGE_CATEGORIES") ?? false;

  const load = useCallback(async () => {
    if (!facilityId) return;
    setError(null);
    try {
      setRows(await getInventoryService().listCategories(facilityId));
    } catch (e) {
      setError(e instanceof ServiceError ? e.message : "Unable to load categories.");
      setRows([]);
    }
  }, [facilityId]);

  useEffect(() => {
    void load();
  }, [load]);

  return (
    <div className="space-y-4">
      <PageHeader
        title="Categories"
        subtitle="Group items for reporting and filtering."
        action={
          canManage && (
            <Button size="sm" onClick={() => setEditing("new")}>
              <Plus className="h-4 w-4" aria-hidden /> Add Category
            </Button>
          )
        }
      />

      <Card className="p-0">
        {error ? (
          <ErrorState message={error} onRetry={() => void load()} />
        ) : rows === null ? (
          <TableSkeleton rows={5} />
        ) : rows.length === 0 ? (
          <EmptyState message="No categories yet." />
        ) : (
          <div className="overflow-x-auto">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Category</TableHead>
                  <TableHead>Description</TableHead>
                  <TableHead className="text-right">Items</TableHead>
                  <TableHead className="text-right">Value</TableHead>
                  <TableHead>Status</TableHead>
                  {canManage && <TableHead />}
                </TableRow>
              </TableHeader>
              <TableBody>
                {rows.map((c) => (
                  <TableRow key={c.id}>
                    <TableCell className="font-medium">{c.name}</TableCell>
                    <TableCell className="text-muted-foreground">{c.description ?? "—"}</TableCell>
                    <TableCell className="text-right tabular-nums">{c.itemCount}</TableCell>
                    <TableCell className="text-right tabular-nums">{money(c.inventoryValueMinor)}</TableCell>
                    <TableCell>
                      <Badge variant={c.isActive ? "success" : "secondary"}>{c.isActive ? "Active" : "Inactive"}</Badge>
                    </TableCell>
                    {canManage && (
                      <TableCell className="text-right">
                        <Button size="sm" variant="outline" onClick={() => setEditing(c)}>
                          Edit
                        </Button>
                      </TableCell>
                    )}
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </div>
        )}
      </Card>

      {editing && facilityId && (
        <CategoryDialog
          facilityId={facilityId}
          existing={editing === "new" ? null : editing}
          onClose={() => setEditing(null)}
          onSaved={() => {
            setEditing(null);
            void load();
          }}
        />
      )}
    </div>
  );
}

function CategoryDialog({
  facilityId,
  existing,
  onClose,
  onSaved,
}: {
  facilityId: string;
  existing: CategoryRow | null;
  onClose: () => void;
  onSaved: () => void;
}) {
  const [name, setName] = useState(existing?.name ?? "");
  const [description, setDescription] = useState(existing?.description ?? "");
  const [isActive, setIsActive] = useState(existing?.isActive ?? true);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function save() {
    if (!name.trim()) {
      setError("A category needs a name.");
      return;
    }
    setBusy(true);
    setError(null);
    try {
      if (existing) {
        await getInventoryService().updateCategory({
          categoryId: existing.id,
          name: name.trim(),
          description: description.trim() || null,
          isActive,
        });
      } else {
        await getInventoryService().createCategory({ facilityId, name: name.trim(), description: description.trim() || null });
      }
      onSaved();
    } catch (e) {
      setError(e instanceof ServiceError ? e.message : "Could not save the category.");
      setBusy(false);
    }
  }

  return (
    <Dialog open onOpenChange={(v) => !v && !busy && onClose()}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>{existing ? "Edit category" : "Add category"}</DialogTitle>
        </DialogHeader>
        <div className="space-y-3">
          <div className="space-y-1.5">
            <Label htmlFor="cat-name">Name</Label>
            <Input id="cat-name" value={name} onChange={(e) => setName(e.target.value)} />
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="cat-desc">Description (optional)</Label>
            <Textarea id="cat-desc" rows={2} value={description} onChange={(e) => setDescription(e.target.value)} />
          </div>
          {existing && (
            <label className="flex items-center gap-2 text-sm">
              <input type="checkbox" checked={isActive} onChange={(e) => setIsActive(e.target.checked)} />
              Active
            </label>
          )}
          {error && <p className="text-sm text-destructive">{error}</p>}
        </div>
        <DialogFooter>
          <Button variant="outline" disabled={busy} onClick={onClose}>
            Cancel
          </Button>
          <Button disabled={busy} onClick={() => void save()}>
            {busy ? "Saving…" : "Save"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
