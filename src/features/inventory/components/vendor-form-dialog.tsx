"use client";

import { useState } from "react";
import {
  Dialog,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Textarea } from "@/components/ui/textarea";
import { ServiceError } from "@/services/shared/service-error";
import { getInventoryService } from "@/services/inventory";
import type { VendorDetail, VendorInput } from "@/features/inventory/types";

export function VendorFormDialog({
  facilityId,
  existing,
  onClose,
  onSaved,
}: {
  facilityId: string;
  existing?: VendorDetail | null;
  onClose: () => void;
  onSaved: (vendorId?: string) => void;
}) {
  const [form, setForm] = useState<VendorInput>({
    name: existing?.name ?? "",
    contactPerson: existing?.contactPerson ?? "",
    phone: existing?.phone ?? "",
    email: existing?.email ?? "",
    address: existing?.address ?? "",
    gstNumber: existing?.gstNumber ?? "",
    panNumber: existing?.panNumber ?? "",
    notes: existing?.notes ?? "",
    status: existing?.status ?? "ACTIVE",
  });
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  function set<K extends keyof VendorInput>(k: K, v: VendorInput[K]) {
    setForm((f) => ({ ...f, [k]: v }));
  }

  async function save() {
    if (!form.name.trim()) {
      setError("A vendor needs a name.");
      return;
    }
    setBusy(true);
    setError(null);
    try {
      if (existing) {
        await getInventoryService().updateVendor(existing.id, form);
        onSaved();
      } else {
        const id = await getInventoryService().createVendor(facilityId, form);
        onSaved(id);
      }
    } catch (e) {
      setError(e instanceof ServiceError ? e.message : "Could not save the vendor.");
      setBusy(false);
    }
  }

  return (
    <Dialog open onOpenChange={(v) => !v && !busy && onClose()}>
      <DialogContent className="max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>{existing ? "Edit vendor" : "Add vendor"}</DialogTitle>
        </DialogHeader>
        <div className="space-y-3">
          <F label="Vendor name"><Input value={form.name} onChange={(e) => set("name", e.target.value)} /></F>
          <F label="Contact person"><Input value={form.contactPerson ?? ""} onChange={(e) => set("contactPerson", e.target.value)} /></F>
          <div className="grid grid-cols-2 gap-3">
            <F label="Phone"><Input value={form.phone ?? ""} onChange={(e) => set("phone", e.target.value)} /></F>
            <F label="Email"><Input value={form.email ?? ""} onChange={(e) => set("email", e.target.value)} /></F>
          </div>
          <F label="Address"><Textarea rows={2} value={form.address ?? ""} onChange={(e) => set("address", e.target.value)} /></F>
          <div className="grid grid-cols-2 gap-3">
            <F label="GST number"><Input value={form.gstNumber ?? ""} onChange={(e) => set("gstNumber", e.target.value)} /></F>
            <F label="PAN number"><Input value={form.panNumber ?? ""} onChange={(e) => set("panNumber", e.target.value)} /></F>
          </div>
          <F label="Notes"><Textarea rows={2} value={form.notes ?? ""} onChange={(e) => set("notes", e.target.value)} /></F>
          {existing && (
            <F label="Status">
              <Select value={form.status ?? "ACTIVE"} onValueChange={(v) => set("status", v as VendorInput["status"])}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="ACTIVE">Active</SelectItem>
                  <SelectItem value="INACTIVE">Inactive</SelectItem>
                </SelectContent>
              </Select>
            </F>
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

function F({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="space-y-1.5">
      <Label>{label}</Label>
      {children}
    </div>
  );
}
