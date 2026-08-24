"use client";

import { useState } from "react";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle, DialogDescription } from "@/components/ui/dialog";
import { getGuestService } from "@/services/guests";
import { getMembershipSessionService } from "@/services/membership-sessions";
import { validateGuestName, validateGuestPhone } from "@/features/guests/validation";
import type { GuestPlayer } from "@/features/guests/types";
import type { MembershipSessionSlot } from "@/features/membership-sessions/types";
import { ServiceError } from "@/services/shared/service-error";

export function BookGuestSlotDialog({
  open,
  onOpenChange,
  facilityId,
  slot,
  onBooked,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  facilityId: string;
  slot: MembershipSessionSlot;
  onBooked: () => void;
}) {
  const [query, setQuery] = useState("");
  const [results, setResults] = useState<GuestPlayer[]>([]);
  const [selectedGuest, setSelectedGuest] = useState<GuestPlayer | null>(null);
  const [showNewGuestForm, setShowNewGuestForm] = useState(false);
  const [newName, setNewName] = useState("");
  const [newPhone, setNewPhone] = useState("");
  const [isBooking, setIsBooking] = useState(false);
  const [error, setError] = useState<string | null>(null);

  function search(value: string) {
    setQuery(value);
    if (value.trim().length < 2) {
      setResults([]);
      return;
    }
    getGuestService()
      .searchGuests(facilityId, value)
      .then(setResults)
      .catch(() => {});
  }

  async function saveNewGuest() {
    const nameError = validateGuestName(newName);
    if (nameError) {
      setError(nameError);
      return;
    }
    const phoneError = validateGuestPhone(newPhone);
    if (phoneError) {
      setError(phoneError);
      return;
    }
    try {
      const guest = await getGuestService().findOrCreateGuest({ facilityId, name: newName, phone: newPhone.trim() || null });
      setSelectedGuest(guest);
      setShowNewGuestForm(false);
    } catch (err) {
      setError(err instanceof ServiceError ? err.message : "Unable to save this guest.");
    }
  }

  async function confirm() {
    if (!selectedGuest) {
      setError("Search for and select a guest, or create a new one.");
      return;
    }
    setIsBooking(true);
    setError(null);
    try {
      await getMembershipSessionService().bookGuestSlot(slot.batchId, slot.sessionDate, selectedGuest.id);
      onBooked();
      onOpenChange(false);
    } catch (err) {
      setError(err instanceof ServiceError ? err.message : "Unable to book this guest slot.");
    } finally {
      setIsBooking(false);
    }
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Book Guest Slot</DialogTitle>
          <DialogDescription>
            {slot.batchName} · {slot.courtName} · {slot.startTime.slice(0, 5)}–{slot.endTime.slice(0, 5)}
          </DialogDescription>
        </DialogHeader>

        <div className="space-y-3">
          {selectedGuest ? (
            <div className="flex items-center justify-between rounded-md border border-input bg-secondary/60 px-3 py-2 text-sm">
              <span>
                {selectedGuest.name}
                {selectedGuest.phone ? <span className="text-muted-foreground"> · {selectedGuest.phone}</span> : null}
              </span>
              <Button type="button" variant="ghost" size="sm" onClick={() => setSelectedGuest(null)}>
                Change
              </Button>
            </div>
          ) : showNewGuestForm ? (
            <div className="space-y-2">
              <input
                aria-label="New guest name"
                placeholder="Guest name"
                value={newName}
                onChange={(e) => setNewName(e.target.value)}
                className="h-10 w-full rounded-md border border-input bg-secondary/60 px-3 text-sm"
              />
              <input
                aria-label="New guest phone"
                placeholder="Phone (optional)"
                value={newPhone}
                onChange={(e) => setNewPhone(e.target.value)}
                className="h-10 w-full rounded-md border border-input bg-secondary/60 px-3 text-sm"
              />
              <div className="flex gap-2">
                <Button type="button" size="sm" onClick={saveNewGuest}>
                  Save Guest
                </Button>
                <Button type="button" variant="ghost" size="sm" onClick={() => setShowNewGuestForm(false)}>
                  Cancel
                </Button>
              </div>
            </div>
          ) : (
            <div className="space-y-2">
              <input
                aria-label="Search guests"
                placeholder="Search by name or phone"
                value={query}
                onChange={(e) => search(e.target.value)}
                className="h-10 w-full rounded-md border border-input bg-secondary/60 px-3 text-sm"
              />
              {results.length > 0 && (
                <div className="divide-y rounded-md border border-input">
                  {results.map((g) => (
                    <button
                      key={g.id}
                      type="button"
                      onClick={() => {
                        setSelectedGuest(g);
                        setResults([]);
                      }}
                      className="block w-full px-3 py-2 text-left text-sm hover:bg-accent"
                    >
                      {g.name} {g.phone && <span className="text-muted-foreground">· {g.phone}</span>}
                    </button>
                  ))}
                </div>
              )}
              <Button type="button" variant="outline" size="sm" onClick={() => setShowNewGuestForm(true)}>
                + Create New Guest
              </Button>
            </div>
          )}

          {error && <p className="text-sm text-destructive">{error}</p>}
        </div>

        <DialogFooter>
          <Button type="button" onClick={confirm} disabled={isBooking}>
            {isBooking ? "Booking…" : "Confirm Booking"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}