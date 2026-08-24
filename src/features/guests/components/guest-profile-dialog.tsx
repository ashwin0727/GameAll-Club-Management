"use client";

import { useEffect, useState } from "react";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Skeleton } from "@/components/ui/skeleton";
import { getGuestService } from "@/services/guests";
import { getSportsService } from "@/services/sports";
import { getPlayingAreasService } from "@/services/playing-areas";
import { formatCurrency } from "@/features/pricing/money";
import type { Booking } from "@/features/bookings/types";
import type { GuestPlayer, GuestStats } from "@/features/guests/types";
import type { FacilitySport, Sport } from "@/features/sports-setup/types";
import type { PlayingArea } from "@/features/courts-setup/types";
import { GuestFormDialog } from "@/features/guests/components/guest-form-dialog";
import { BookingDialog } from "@/features/bookings/components/booking-dialog";

function formatDateTime(iso: string): string {
  return new Date(iso).toLocaleString("en-IN", { day: "numeric", month: "short", hour: "numeric", minute: "2-digit", hour12: true });
}

export function GuestProfileDialog({
  open,
  onOpenChange,
  facilityId,
  guest,
  onChanged,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  facilityId: string;
  guest: GuestPlayer | null;
  onChanged: (guest: GuestPlayer) => void;
}) {
  const [stats, setStats] = useState<GuestStats | null>(null);
  const [history, setHistory] = useState<Booking[]>([]);
  const [loading, setLoading] = useState(true);
  const [editOpen, setEditOpen] = useState(false);
  const [bookOpen, setBookOpen] = useState(false);
  const [facilitySports, setFacilitySports] = useState<FacilitySport[]>([]);
  const [sports, setSports] = useState<Sport[]>([]);
  const [areas, setAreas] = useState<PlayingArea[]>([]);

  useEffect(() => {
    if (!open || !guest) return;
    let cancelled = false;
    setLoading(true);
    (async () => {
      const [s, h, fs, allSports, playingAreas] = await Promise.all([
        getGuestService().getGuestStats(guest.id),
        getGuestService().getGuestBookings(guest.id, { limit: 20 }),
        getSportsService().getFacilitySports(facilityId),
        getSportsService().getActiveSports(),
        getPlayingAreasService().getPlayingAreas(facilityId),
      ]);
      if (cancelled) return;
      setStats(s);
      setHistory(h);
      setFacilitySports(fs.filter((f) => f.enabled));
      setSports(allSports);
      setAreas(playingAreas.filter((a) => !a.archived && a.status === "ACTIVE" && a.bookingEnabled));
      setLoading(false);
    })();
    return () => {
      cancelled = true;
    };
  }, [open, guest, facilityId]);

  if (!guest) return null;

  return (
    <>
      <Dialog open={open && !editOpen && !bookOpen} onOpenChange={onOpenChange}>
        <DialogContent className="max-h-[90vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle>{guest.name}</DialogTitle>
          </DialogHeader>

          <div className="space-y-4 text-sm">
            {guest.phone && <p className="text-muted-foreground">Phone: {guest.phone}</p>}
            {guest.email && <p className="text-muted-foreground">Email: {guest.email}</p>}

            {loading || !stats ? (
              <Skeleton className="h-32 w-full rounded-lg" />
            ) : (
              <>
                <div className="grid grid-cols-2 gap-3 sm:grid-cols-3">
                  <div className="rounded-lg border border-border p-3">
                    <p className="text-xs text-muted-foreground">Total Visits</p>
                    <p className="text-lg font-semibold">{stats.totalVisits}</p>
                  </div>
                  <div className="rounded-lg border border-border p-3">
                    <p className="text-xs text-muted-foreground">Total Amount</p>
                    <p className="text-lg font-semibold">{formatCurrency(stats.totalAmountMinor, "INR")}</p>
                  </div>
                  <div className="rounded-lg border border-border p-3">
                    <p className="text-xs text-muted-foreground">Pending</p>
                    <p className="text-lg font-semibold">{formatCurrency(stats.pendingAmountMinor, "INR")}</p>
                  </div>
                </div>
                <div>
                  <p className="text-xs text-muted-foreground">Last Visit</p>
                  <p>{stats.lastVisit ? formatDateTime(stats.lastVisit) : "Never"}</p>
                </div>
                {stats.sports.length > 0 && (
                  <div>
                    <p className="text-xs text-muted-foreground">Sports Played</p>
                    <p>{stats.sports.map((s) => s.sportName).join(", ")}</p>
                  </div>
                )}

                <div>
                  <p className="mb-2 text-xs font-medium text-muted-foreground">Booking History</p>
                  {history.length === 0 ? (
                    <p className="text-muted-foreground">No bookings found.</p>
                  ) : (
                    <div className="max-h-56 space-y-2 overflow-y-auto">
                      {history.map((b) => (
                        <div key={b.id} className="flex items-center justify-between rounded-md border border-border p-2">
                          <div>
                            <p>{new Date(b.startTime).toLocaleDateString("en-IN", { day: "numeric", month: "short", year: "numeric" })}</p>
                            <p className="text-xs text-muted-foreground capitalize">
                              {b.status} · {b.paymentStatus.toLowerCase()}
                            </p>
                          </div>
                          <p>{b.amountMinor != null ? formatCurrency(b.amountMinor, b.currency) : "—"}</p>
                        </div>
                      ))}
                    </div>
                  )}
                </div>
              </>
            )}
          </div>

          <DialogFooter>
            <Button type="button" variant="outline" onClick={() => setEditOpen(true)}>
              Edit Guest
            </Button>
            <Button type="button" onClick={() => setBookOpen(true)}>
              Book Court
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      <GuestFormDialog
        open={editOpen}
        onOpenChange={setEditOpen}
        facilityId={facilityId}
        guest={guest}
        onSaved={onChanged}
      />

      {bookOpen && (
        <BookingDialog
          open={bookOpen}
          onOpenChange={setBookOpen}
          facilityId={facilityId}
          date={new Date()}
          facilitySports={facilitySports}
          sports={sports}
          areas={areas}
          initialGuest={guest}
          onBooked={() => setBookOpen(false)}
        />
      )}
    </>
  );
}