"use client";

import { useEffect, useState } from "react";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { cn } from "@/lib/utils";
import { MAINTENANCE_ICON_KEYS, type MaintenanceIconKey, type MaintenanceIssueCategory } from "@/features/maintenance/types";
import { maintenanceIcon } from "@/features/maintenance/icons";
import { getMaintenanceService } from "@/services/maintenance";
import { ServiceError } from "@/services/shared/service-error";

const ICON_LABEL: Record<MaintenanceIconKey, string> = {
  court: "Net / Court",
  lightbulb: "Lighting",
  grid: "Floor Surface",
  snowflake: "AC / HVAC",
  cog: "Equipment",
  droplet: "Water Leakage",
  lock: "Door / Lock",
  paint: "Painting",
  wrench: "General Repair",
  more: "Others",
};

export function CategoryFormDialog({
  facilityId,
  category,
  open,
  onOpenChange,
  onSaved,
}: {
  facilityId: string;
  category: MaintenanceIssueCategory | null;
  open: boolean;
  onOpenChange: (open: boolean) => void;
  onSaved: () => void;
}) {
  const [name, setName] = useState("");
  const [icon, setIcon] = useState<MaintenanceIconKey>("wrench");
  const [description, setDescription] = useState("");
  const [sortOrder, setSortOrder] = useState(0);
  const [isActive, setIsActive] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    if (!open) return;
    setName(category?.name ?? "");
    setIcon((category?.icon as MaintenanceIconKey) ?? "wrench");
    setDescription(category?.description ?? "");
    setSortOrder(category?.sortOrder ?? 0);
    setIsActive(category?.isActive ?? true);
    setError(null);
  }, [open, category]);

  async function handleSave() {
    if (!name.trim()) {
      setError("Category name is required.");
      return;
    }
    setSaving(true);
    setError(null);
    try {
      if (category) {
        await getMaintenanceService().updateIssueCategory({ categoryId: category.id, name, icon, description, sortOrder, isActive });
      } else {
        await getMaintenanceService().createIssueCategory({ facilityId, name, icon, description, sortOrder });
      }
      onOpenChange(false);
      onSaved();
    } catch (e) {
      setError(e instanceof ServiceError ? e.message : "Unable to save this category.");
    } finally {
      setSaving(false);
    }
  }

  const PreviewIcon = maintenanceIcon(icon);

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-lg">
        <DialogHeader>
          <DialogTitle>{category ? "Edit Issue Category" : "Add Issue Category"}</DialogTitle>
        </DialogHeader>

        <div className="grid gap-4 sm:grid-cols-2">
          <div className="space-y-3 sm:col-span-1">
            <div className="space-y-1.5">
              <Label htmlFor="cat-name">Category Name</Label>
              <Input id="cat-name" value={name} onChange={(e) => setName(e.target.value)} placeholder="e.g. Net Damaged" maxLength={60} />
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="cat-desc">Description</Label>
              <Textarea id="cat-desc" value={description} onChange={(e) => setDescription(e.target.value.slice(0, 200))} rows={4} placeholder="Brief description of this category" />
              <p className="text-right text-[11px] text-muted-foreground">{description.length}/200</p>
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="cat-sort">Sort Order</Label>
              <Input id="cat-sort" type="number" value={sortOrder} onChange={(e) => setSortOrder(Number(e.target.value) || 0)} />
              <p className="text-[11px] text-muted-foreground">Lower numbers appear first in the list.</p>
            </div>
            {category && (
              <label className="flex items-center gap-2 text-sm">
                <input type="checkbox" checked={isActive} onChange={(e) => setIsActive(e.target.checked)} className="h-4 w-4 rounded border-input" />
                Active
              </label>
            )}
          </div>

          <div className="space-y-3">
            <Label>Icon Selection</Label>
            <div className="grid grid-cols-5 gap-2">
              {MAINTENANCE_ICON_KEYS.map((key) => {
                const Icon = maintenanceIcon(key);
                return (
                  <button
                    key={key}
                    type="button"
                    onClick={() => setIcon(key)}
                    title={ICON_LABEL[key]}
                    className={cn(
                      "flex flex-col items-center gap-1 rounded-lg border p-2 text-[10px] transition-colors",
                      icon === key ? "border-primary bg-primary/10 text-primary" : "border-border text-muted-foreground hover:bg-secondary",
                    )}
                  >
                    <Icon className="h-4 w-4" aria-hidden />
                    <span className="truncate w-full text-center">{ICON_LABEL[key]}</span>
                  </button>
                );
              })}
            </div>

            <div className="rounded-lg border border-border p-3">
              <p className="mb-2 text-[11px] text-muted-foreground">Preview</p>
              <div className="flex items-center gap-2">
                <span className="flex h-8 w-8 items-center justify-center rounded-md bg-primary/15 text-primary">
                  <PreviewIcon className="h-4 w-4" aria-hidden />
                </span>
                <div className="min-w-0">
                  <p className="truncate text-sm font-medium">{name || "Category name"}</p>
                  <p className="text-[11px] text-muted-foreground">{isActive ? "Active" : "Inactive"}</p>
                </div>
              </div>
            </div>
          </div>
        </div>

        {error && <p className="text-sm text-destructive" role="alert">{error}</p>}

        <DialogFooter>
          <Button variant="outline" onClick={() => onOpenChange(false)} disabled={saving}>
            Cancel
          </Button>
          <Button onClick={handleSave} disabled={saving}>
            {saving ? "Saving…" : "Save Category"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
