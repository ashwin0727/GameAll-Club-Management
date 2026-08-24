"use client";

import { useEffect, useMemo, useState } from "react";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { getBookingService } from "@/services/bookings";
import { getOperatingHoursService } from "@/services/operating-hours";
import { getGuestService } from "@/services/guests";
import { computeAvailableSlots } from "@/features/bookings/slots";
import { formatCurrency } from "@/features/pricing/money";
import { validateGuestName, validateGuestPhone } from "@/features/guests/validation";
import type { Booking, CustomerType, PaymentStatus, TimeSlot } from "@/features/bookings/types";
import type { GuestPlayer } from "@/features/guests/types";
import type { PlayingArea } from "@/features/courts-setup/types";
import type { FacilitySport, Sport } from "@/features/sports-setup/types";
import { ServiceError } from "@/services/shared/service-error";

function formatTime(iso: string): string {
  return new Date(iso).toLocaleTimeString("en-IN", { hour: "numeric", minute: "2-digit", hour12: true });
}

/**
 * Handles both entry points the spec calls out: tapping a free grid cell
 * (court + slot already known — jumps straight to the customer step) and
 * "+ Create Booking" (starts from Sport → Court, still against the same
 * facility-wide bookings the grid already has, so no extra fetch per pick).
 */
export function BookingDialog({
  open,
  onOpenChange,
  facilityId,
  date,
  facilitySports,
  sports,
  areas,
  initialCourtId,
  initialSlot,
  initialGuest,
  initialMember,
  onBooked,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  facilityId: string;
  date: Date;
  facilitySports: FacilitySport[];
  sports: Sport[];
  areas: PlayingArea[];
  initialCourtId?: string;
  initialSlot?: TimeSlot;
  /** Set when opened via "Book Court" from a Guest Profile — skips guest search entirely. */
  initialGuest?: GuestPlayer;
  /** Set when opened via "Book Court" from a Member Profile — skips member search entirely. */
  initialMember?: { id: string; fullName: string };
  onBooked: (booking: Booking) => void;
}) {
  const [facilitySportId, setFacilitySportId] = useState(initialCourtId ? areas.find((a) => a.id === initialCourtId)?.facilitySportId ?? "" : "");
  const [courtId, setCourtId] = useState(initialCourtId ?? "");
  const [slot, setSlot] = useState<TimeSlot | null>(initialSlot ?? null);
  const [slots, setSlots] = useState<TimeSlot[]>([]);
  const [slotsLoading, setSlotsLoading] = useState(false);

  const [customerType, setCustomerType] = useState<CustomerType>(initialMember ? "MEMBER" : "GUEST");
  const [selectedGuest, setSelectedGuest] = useState<GuestPlayer | null>(initialGuest ?? null);
  const [guestQuery, setGuestQuery] = useState("");
  const [guestResults, setGuestResults] = useState<GuestPlayer[]>([]);
  const [showNewGuestForm, setShowNewGuestForm] = useState(false);
  const [newGuestName, setNewGuestName] = useState("");
  const [newGuestPhone, setNewGuestPhone] = useState("");
  const [isSavingGuest, setIsSavingGuest] = useState(false);
  const [memberQuery, setMemberQuery] = useState("");
  const [memberResults, setMemberResults] = useState<{ id: string; fullName: string; phone: string; email: string | null }[]>([]);
  const [selectedMember, setSelectedMember] = useState<{ id: string; fullName: string } | null>(initialMember ?? null);
  const [paymentStatus, setPaymentStatus] = useState<PaymentStatus>("PENDING");
  const [notes, setNotes] = useState("");
  const [isBooking, setIsBooking] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!open) return;
    setFacilitySportId(initialCourtId ? areas.find((a) => a.id === initialCourtId)?.facilitySportId ?? "" : "");
    setCourtId(initialCourtId ?? "");
    setSlot(initialSlot ?? null);
    setCustomerType(initialMember ? "MEMBER" : "GUEST");
    setSelectedGuest(initialGuest ?? null);
    setGuestQuery("");
    setGuestResults([]);
    setShowNewGuestForm(false);
    setNewGuestName("");
    setNewGuestPhone("");
    setMemberQuery("");
    setMemberResults([]);
    setSelectedMember(initialMember ?? null);
    setPaymentStatus("PENDING");
    setNotes("");
    setError(null);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open, initialCourtId, initialSlot, initialGuest, initialMember]);

  useEffect(() => {
    let cancelled = false;
    if (guestQuery.trim().length < 2) {
      setGuestResults([]);
      return;
    }
    const timeout = setTimeout(() => {
      getGuestService()
        .searchGuests(facilityId, guestQuery)
        .then((results) => !cancelled && setGuestResults(results))
        .catch(() => {});
    }, 300);
    return () => {
      cancelled = true;
      clearTimeout(timeout);
    };
  }, [guestQuery, facilityId]);

  async function saveNewGuest() {
    const nameError = validateGuestName(newGuestName);
    if (nameError) {
      setError(nameError);
      return;
    }
    const phoneError = validateGuestPhone(newGuestPhone);
    if (phoneError) {
      setError(phoneError);
      return;
    }
    setIsSavingGuest(true);
    setError(null);
    try {
      const guest = await getGuestService().findOrCreateGuest({
        facilityId,
        name: newGuestName,
        phone: newGuestPhone.trim() || null,
      });
      setSelectedGuest(guest);
      setShowNewGuestForm(false);
    } catch (err) {
      setError(err instanceof ServiceError ? err.message : "Unable to save this guest.");
    } finally {
      setIsSavingGuest(false);
    }
  }

  const courtsForSport = useMemo(() => areas.filter((a) => a.facilitySportId === facilitySportId), [areas, facilitySportId]);

  useEffect(() => {
    if (!courtId || initialSlot) return;
    let cancelled = false;
    setSlotsLoading(true);
    (async () => {
      const dow = date.getDay();
      // bookingsByCourt is a fast-path (the grid already has today's data in
      // memory) — but it's only ever populated for the grid's own selected
      // date, so a caller opening this dialog for an arbitrary date (or
      // with no grid data at all, e.g. from a Guest Profile) must always
      // re-fetch the real bookings for the exact court+date being shown,
      // never silently treat "no data passed in" as "nothing is booked".
      const [override, facilitySchedule, existing] = await Promise.all([
        getOperatingHoursService().getPlayingAreaSchedule(courtId),
        getOperatingHoursService().getFacilitySchedule(facilityId),
        getBookingService().getBookingsForCourtOnDate(courtId, date),
      ]);
      if (cancelled) return;
      const schedule = override ?? facilitySchedule;
      const day = schedule?.days.find((d) => d.dayOfWeek === dow) ?? null;
      setSlots(day ? computeAvailableSlots(date, day, existing) : []);
      setSlotsLoading(false);
    })();
    return () => {
      cancelled = true;
    };
  }, [courtId, date, facilityId, initialSlot]);

  useEffect(() => {
    let cancelled = false;
    if (memberQuery.trim().length < 2) {
      setMemberResults([]);
      return;
    }
    const timeout = setTimeout(() => {
      getBookingService()
        .searchMembers(facilityId, memberQuery)
        .then((results) => !cancelled && setMemberResults(results))
        .catch(() => {});
    }, 300);
    return () => {
      cancelled = true;
      clearTimeout(timeout);
    };
  }, [memberQuery, facilityId]);

  async function confirm() {
    if (!courtId || !slot) return;
    if (customerType === "GUEST" && !selectedGuest) {
      setError("Search for and select a guest, or create a new one.");
      return;
    }
    if (customerType === "MEMBER" && !selectedMember) {
      setError("Search for and select a member.");
      return;
    }
    setIsBooking(true);
    setError(null);
    try {
      const booking = await getBookingService().createBooking({
        facilityId,
        courtId,
        startTime: slot.startTime,
        endTime: slot.endTime,
        customerType,
        memberId: customerType === "MEMBER" ? selectedMember!.id : null,
        guestPlayerId: customerType === "GUEST" ? selectedGuest!.id : null,
        notes: notes.trim() || null,
        paymentStatus,
      });
      onBooked(booking);
      onOpenChange(false);
    } catch (err) {
      setError(err instanceof ServiceError ? err.message : "Unable to create this booking.");
    } finally {
      setIsBooking(false);
    }
  }

  const court = areas.find((a) => a.id === courtId);
  const sport = sports.find((s) => facilitySports.find((fs) => fs.id === facilitySportId)?.sportId === s.id);
  const facilitySport = facilitySports.find((fs) => fs.id === facilitySportId);

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>Quick Booking</DialogTitle>
        </DialogHeader>

        <div className="space-y-4">
          {!initialCourtId && (
            <div className="grid grid-cols-2 gap-3">
              <select
                aria-label="Sport"
                value={facilitySportId}
                onChange={(e) => {
                  setFacilitySportId(e.target.value);
                  setCourtId("");
                  setSlot(null);
                }}
                className="h-11 rounded-md border border-input bg-secondary/60 px-3 text-sm"
              >
                <option value="">Select sport</option>
                {facilitySports.map((fs) => {
                  const s = sports.find((sp) => sp.id === fs.sportId);
                  return (
                    <option key={fs.id} value={fs.id}>
                      {fs.customSportName ?? s?.name ?? "Sport"}
                    </option>
                  );
                })}
              </select>
              <select
                aria-label="Court"
                value={courtId}
                onChange={(e) => {
                  setCourtId(e.target.value);
                  setSlot(null);
                }}
                disabled={!facilitySportId}
                className="h-11 rounded-md border border-input bg-secondary/60 px-3 text-sm disabled:opacity-50"
              >
                <option value="">Select court</option>
                {courtsForSport.map((a) => (
                  <option key={a.id} value={a.id}>
                    {a.name}
                  </option>
                ))}
              </select>
            </div>
          )}

          {initialCourtId && (
            <div className="rounded-md bg-secondary/50 p-3 text-sm">
              <span className="font-medium">{sport?.name ?? facilitySport?.customSportName}</span> · {court?.name}
            </div>
          )}

          <div className="text-sm text-muted-foreground">
            {date.toLocaleDateString("en-IN", { day: "numeric", month: "short", year: "numeric" })}
          </div>

          {!initialSlot && courtId && (
            <div>
              <p className="mb-2 text-sm font-medium">Time</p>
              {slotsLoading ? (
                <p className="text-sm text-muted-foreground">Loading availability…</p>
              ) : slots.length === 0 ? (
                <p className="text-sm text-muted-foreground">No slots available.</p>
              ) : (
                <div className="flex max-h-40 flex-wrap gap-2 overflow-y-auto">
                  {slots.map((s) => (
                    <button
                      key={s.startTime}
                      type="button"
                      disabled={!s.available}
                      onClick={() => setSlot(s)}
                      className={`h-9 rounded-md border px-3 text-xs font-medium ${
                        slot?.startTime === s.startTime
                          ? "border-primary bg-primary text-primary-foreground"
                          : s.available
                            ? "border-input bg-secondary/60 hover:bg-accent"
                            : "cursor-not-allowed border-input bg-muted text-muted-foreground line-through"
                      }`}
                    >
                      {formatTime(s.startTime)}
                    </button>
                  ))}
                </div>
              )}
            </div>
          )}

          {slot && (
            <>
              <div className="rounded-md bg-secondary/50 p-3 text-sm">
                {formatTime(slot.startTime)} – {formatTime(slot.endTime)}
              </div>

              <div className="flex gap-2">
                <Button type="button" variant={customerType === "GUEST" ? "default" : "outline"} size="sm" onClick={() => setCustomerType("GUEST")}>
                  Guest
                </Button>
                <Button type="button" variant={customerType === "MEMBER" ? "default" : "outline"} size="sm" onClick={() => setCustomerType("MEMBER")}>
                  Member
                </Button>
              </div>

              {customerType === "GUEST" ? (
                selectedGuest ? (
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
                    <div className="grid grid-cols-2 gap-3">
                      <input
                        aria-label="New guest name"
                        placeholder="Guest name"
                        value={newGuestName}
                        onChange={(e) => setNewGuestName(e.target.value)}
                        className="h-11 rounded-md border border-input bg-secondary/60 px-3 text-sm"
                      />
                      <input
                        aria-label="New guest phone"
                        placeholder="Phone (optional)"
                        value={newGuestPhone}
                        onChange={(e) => setNewGuestPhone(e.target.value)}
                        className="h-11 rounded-md border border-input bg-secondary/60 px-3 text-sm"
                      />
                    </div>
                    <div className="flex gap-2">
                      <Button type="button" size="sm" onClick={saveNewGuest} disabled={isSavingGuest}>
                        {isSavingGuest ? "Saving…" : "Save Guest"}
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
                      value={guestQuery}
                      onChange={(e) => setGuestQuery(e.target.value)}
                      className="h-11 w-full rounded-md border border-input bg-secondary/60 px-3 text-sm"
                    />
                    {guestResults.length > 0 && (
                      <div className="divide-y rounded-md border border-input">
                        {guestResults.map((g) => (
                          <button
                            key={g.id}
                            type="button"
                            onClick={() => {
                              setSelectedGuest(g);
                              setGuestResults([]);
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
                )
              ) : selectedMember ? (
                <div className="flex items-center justify-between rounded-md border border-input bg-secondary/60 px-3 py-2 text-sm">
                  <span>{selectedMember.fullName}</span>
                  <Button type="button" variant="ghost" size="sm" onClick={() => setSelectedMember(null)}>
                    Change
                  </Button>
                </div>
              ) : (
                <div className="space-y-2">
                  <input
                    aria-label="Search members"
                    placeholder="Search by name or phone"
                    value={memberQuery}
                    onChange={(e) => setMemberQuery(e.target.value)}
                    className="h-11 w-full rounded-md border border-input bg-secondary/60 px-3 text-sm"
                  />
                  {memberResults.length > 0 && (
                    <div className="divide-y rounded-md border border-input">
                      {memberResults.map((m) => (
                        <button
                          key={m.id}
                          type="button"
                          onClick={() => {
                            setSelectedMember({ id: m.id, fullName: m.fullName });
                            setMemberResults([]);
                          }}
                          className="block w-full px-3 py-2 text-left text-sm hover:bg-accent"
                        >
                          {m.fullName} <span className="text-muted-foreground">· {m.phone}</span>
                        </button>
                      ))}
                    </div>
                  )}
                </div>
              )}

              <div>
                <p className="mb-1 text-sm font-medium">Payment</p>
                <div className="flex gap-2">
                  <Button type="button" variant={paymentStatus === "PAID" ? "default" : "outline"} size="sm" onClick={() => setPaymentStatus("PAID")}>
                    Paid
                  </Button>
                  <Button type="button" variant={paymentStatus === "PENDING" ? "default" : "outline"} size="sm" onClick={() => setPaymentStatus("PENDING")}>
                    Pending
                  </Button>
                </div>
              </div>

              <input
                aria-label="Notes"
                placeholder="Notes (optional)"
                value={notes}
                onChange={(e) => setNotes(e.target.value)}
                className="h-11 w-full rounded-md border border-input bg-secondary/60 px-3 text-sm"
              />
            </>
          )}

          {error && <p className="text-sm text-destructive">{error}</p>}
        </div>

        <DialogFooter>
          <Button type="button" onClick={confirm} disabled={!slot || isBooking}>
            {isBooking ? "Booking…" : "Confirm Booking"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

export { formatTime, formatCurrency };