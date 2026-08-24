"use client";

import { useEffect, useState } from "react";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { getGuestService } from "@/services/guests";
import { validateGuestName, validateGuestPhone } from "@/features/guests/validation";
import type { GuestPlayer } from "@/features/guests/types";
import { ServiceError } from "@/services/shared/service-error";

export function GuestFormDialog({
  open,
  onOpenChange,
  facilityId,
  guest,
  onSaved,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  facilityId: string;
  /** Present = editing; absent = creating a new guest. */
  guest?: GuestPlayer | null;
  onSaved: (guest: GuestPlayer) => void;
}) {
  const [name, setName] = useState("");
  const [phone, setPhone] = useState("");
  const [email, setEmail] = useState("");
  const [notes, setNotes] = useState("");
  const [status, setStatus] = useState<"ACTIVE" | "INACTIVE">("ACTIVE");
  const [isSaving, setIsSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!open) return;
    setName(guest?.name ?? "");
    setPhone(guest?.phone ?? "");
    setEmail(guest?.email ?? "");
    setNotes(guest?.notes ?? "");
    setStatus(guest?.status ?? "ACTIVE");
    setError(null);
  }, [open, guest]);

  async function save() {
    const nameError = validateGuestName(name);
    if (nameError) {
      setError(nameError);
      return;
    }
    const phoneError = validateGuestPhone(phone);
    if (phoneError) {
      setError(phoneError);
      return;
    }

    setIsSaving(true);
    setError(null);
    try {
      const saved = guest
        ? await getGuestService().updateGuest(guest.id, {
            name,
            phone: phone.trim() || null,
            email: email.trim() || null,
            notes: notes.trim() || null,
            status,
          })
        : await getGuestService().findOrCreateGuest({
            facilityId,
            name,
            phone: phone.trim() || null,
            email: email.trim() || null,
            notes: notes.trim() || null,
          });
      onSaved(saved);
      onOpenChange(false);
    } catch (err) {
      setError(err instanceof ServiceError ? err.message : "Unable to save this guest.");
    } finally {
      setIsSaving(false);
    }
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>{guest ? "Edit Guest" : "Add Guest"}</DialogTitle>
        </DialogHeader>
        <div className="space-y-3">
          <input
            aria-label="Guest name"
            placeholder="Full name"
            value={name}
            onChange={(e) => setName(e.target.value)}
            className="h-11 w-full rounded-md border border-input bg-secondary/60 px-3 text-sm"
          />
          <input
            aria-label="Phone"
            placeholder="Mobile number (optional)"
            value={phone}
            onChange={(e) => setPhone(e.target.value)}
            className="h-11 w-full rounded-md border border-input bg-secondary/60 px-3 text-sm"
          />
          <input
            aria-label="Email"
            placeholder="Email (optional)"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            className="h-11 w-full rounded-md border border-input bg-secondary/60 px-3 text-sm"
          />
          <textarea
            aria-label="Notes"
            placeholder="Notes (optional)"
            value={notes}
            onChange={(e) => setNotes(e.target.value)}
            className="min-h-20 w-full rounded-md border border-input bg-secondary/60 px-3 py-2 text-sm"
          />
          {guest && (
            <div className="flex gap-2">
              <Button type="button" variant={status === "ACTIVE" ? "default" : "outline"} size="sm" onClick={() => setStatus("ACTIVE")}>
                Active
              </Button>
              <Button type="button" variant={status === "INACTIVE" ? "default" : "outline"} size="sm" onClick={() => setStatus("INACTIVE")}>
                Inactive
              </Button>
            </div>
          )}
          {error && <p className="text-sm text-destructive">{error}</p>}
        </div>
        <DialogFooter>
          <Button type="button" onClick={save} disabled={isSaving}>
            {isSaving ? "Saving…" : "Save"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}