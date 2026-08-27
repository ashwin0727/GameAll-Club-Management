"use client";

import { useEffect, useState } from "react";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Skeleton } from "@/components/ui/skeleton";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { getMembershipService } from "@/services/memberships";
import { getSportsService } from "@/services/sports";
import { getPlayingAreasService } from "@/services/playing-areas";
import { formatCurrency } from "@/features/pricing/money";
import { computeMembershipStatus } from "@/features/memberships/status";
import { validateMemberPhone } from "@/features/members/validation";
import { ServiceError } from "@/services/shared/service-error";
import type { Booking } from "@/features/bookings/types";
import type { FacilityMemberRow, Membership, MemberStats } from "@/features/memberships/types";
import type { FacilitySport, Sport } from "@/features/sports-setup/types";
import type { PlayingArea } from "@/features/courts-setup/types";
import { AssignMembershipDialog } from "@/features/memberships/components/assign-membership-dialog";
import { CancelMembershipDialog } from "@/features/memberships/components/cancel-membership-dialog";
import { BookingDialog } from "@/features/bookings/components/booking-dialog";

function formatDate(iso: string): string {
  return new Date(iso).toLocaleDateString("en-IN", { day: "numeric", month: "short", year: "numeric" });
}

function formatDateTime(iso: string): string {
  return new Date(iso).toLocaleString("en-IN", { day: "numeric", month: "short", hour: "numeric", minute: "2-digit", hour12: true });
}

function statusTone(status: ReturnType<typeof computeMembershipStatus>): "success" | "warning" | "destructive" | "secondary" {
  switch (status) {
    case "ACTIVE":
      return "success";
    case "EXPIRING_SOON":
      return "warning";
    case "EXPIRED":
      return "destructive";
    case "CANCELLED":
    case "NO_MEMBERSHIP":
      return "secondary";
  }
}

function statusText(status: ReturnType<typeof computeMembershipStatus>): string {
  return status === "NO_MEMBERSHIP" ? "no membership" : status.replace("_", " ").toLowerCase();
}

export function MemberProfileDialog({
  open,
  onOpenChange,
  facilityId,
  member,
  onChanged,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  facilityId: string;
  member: FacilityMemberRow | null;
  onChanged: () => void;
}) {
  const [stats, setStats] = useState<MemberStats | null>(null);
  const [bookingHistory, setBookingHistory] = useState<Booking[]>([]);
  const [membershipHistory, setMembershipHistory] = useState<Membership[]>([]);
  const [loading, setLoading] = useState(true);
  const [editOpen, setEditOpen] = useState(false);
  const [renewOpen, setRenewOpen] = useState(false);
  const [cancelMembershipOpen, setCancelMembershipOpen] = useState(false);
  const [bookOpen, setBookOpen] = useState(false);
  const [facilitySports, setFacilitySports] = useState<FacilitySport[]>([]);
  const [sports, setSports] = useState<Sport[]>([]);
  const [areas, setAreas] = useState<PlayingArea[]>([]);

  const [editName, setEditName] = useState("");
  const [editPhone, setEditPhone] = useState("");
  const [editError, setEditError] = useState<string | null>(null);
  const [isSavingEdit, setIsSavingEdit] = useState(false);

  useEffect(() => {
    if (!open || !member) return;
    let cancelled = false;
    setLoading(true);
    (async () => {
      const membershipService = getMembershipService();
      const [s, history, plans, fs, allSports, playingAreas] = await Promise.all([
        membershipService.getMemberStats(member.memberId, facilityId),
        membershipService.getMemberBookings(member.memberId, facilityId, { limit: 20 }),
        membershipService.getMembershipHistory(member.memberId, facilityId),
        getSportsService().getFacilitySports(facilityId),
        getSportsService().getActiveSports(),
        getPlayingAreasService().getPlayingAreas(facilityId),
      ]);
      if (cancelled) return;
      setStats(s);
      setBookingHistory(history);
      setMembershipHistory(plans);
      setFacilitySports(fs.filter((f) => f.enabled));
      setSports(allSports);
      setAreas(playingAreas.filter((a) => !a.archived && a.status === "ACTIVE" && a.bookingEnabled));
      setLoading(false);
    })();
    return () => {
      cancelled = true;
    };
  }, [open, member, facilityId]);

  useEffect(() => {
    if (!member) return;
    setEditName(member.fullName);
    setEditPhone(member.phone ?? "");
    setEditError(null);
  }, [member]);

  if (!member) return null;

  const displayStatus = computeMembershipStatus(
    member.status !== null && member.endDate !== null ? { status: member.status, endDate: member.endDate } : null,
  );

  async function saveEdit() {
    if (!member) return;
    if (editName.trim().length < 2) {
      setEditError("Enter at least 2 characters.");
      return;
    }
    const phoneError = validateMemberPhone(editPhone);
    if (phoneError) {
      setEditError(phoneError);
      return;
    }
    setIsSavingEdit(true);
    setEditError(null);
    try {
      await getMembershipService().updateMember(member.memberId, {
        fullName: editName.trim(),
        phone: editPhone.trim(),
      });
      setEditOpen(false);
      onChanged();
    } catch (err) {
      setEditError(err instanceof ServiceError ? err.message : "Unable to save changes.");
    } finally {
      setIsSavingEdit(false);
    }
  }

  return (
    <>
      <Dialog open={open && !editOpen && !renewOpen && !cancelMembershipOpen && !bookOpen} onOpenChange={onOpenChange}>
        <DialogContent className="max-h-[90vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              {member.fullName}
              <Badge variant={statusTone(displayStatus)} className="capitalize">
                {statusText(displayStatus)}
              </Badge>
            </DialogTitle>
          </DialogHeader>

          <div className="space-y-4 text-sm">
            <div className="text-muted-foreground">
              <p>Phone: {member.phone}</p>
              {member.email && <p>Email: {member.email}</p>}
              <p>
                {member.planName && member.startDate && member.endDate
                  ? `${member.planName} · ${formatDate(member.startDate)} – ${formatDate(member.endDate)}`
                  : "No membership assigned yet."}
              </p>
            </div>

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
                  <p className="mb-2 text-xs font-medium text-muted-foreground">Membership History</p>
                  {membershipHistory.length === 0 ? (
                    <p className="text-muted-foreground">No membership history.</p>
                  ) : (
                    <div className="max-h-40 space-y-2 overflow-y-auto">
                      {membershipHistory.map((m) => {
                        const s = computeMembershipStatus({ status: m.status, endDate: m.endDate });
                        return (
                          <div key={m.id} className="flex items-center justify-between rounded-md border border-border p-2">
                            <div>
                              <p>{m.planName}</p>
                              <p className="text-xs text-muted-foreground">
                                {formatDate(m.startDate)} – {formatDate(m.endDate)}
                              </p>
                            </div>
                            <Badge variant={statusTone(s)} className="capitalize">
                              {statusText(s)}
                            </Badge>
                          </div>
                        );
                      })}
                    </div>
                  )}
                </div>

                <div>
                  <p className="mb-2 text-xs font-medium text-muted-foreground">Booking History</p>
                  {bookingHistory.length === 0 ? (
                    <p className="text-muted-foreground">No bookings found.</p>
                  ) : (
                    <div className="max-h-56 space-y-2 overflow-y-auto">
                      {bookingHistory.map((b) => (
                        <div key={b.id} className="flex items-center justify-between rounded-md border border-border p-2">
                          <div>
                            <p>{formatDate(b.startTime)}</p>
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

          <DialogFooter className="flex-wrap gap-2">
            <Button type="button" variant="outline" onClick={() => setEditOpen(true)}>
              Edit Member
            </Button>
            <Button type="button" variant="outline" onClick={() => setRenewOpen(true)}>
              {member.membershipId ? "Renew Membership" : "Add Membership"}
            </Button>
            <Button type="button" onClick={() => setBookOpen(true)}>
              Book Court
            </Button>
            {member.membershipId && displayStatus === "ACTIVE" && (
              <Button type="button" variant="destructive" onClick={() => setCancelMembershipOpen(true)}>
                Cancel Membership
              </Button>
            )}
          </DialogFooter>
        </DialogContent>
      </Dialog>

      <Dialog open={editOpen} onOpenChange={setEditOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Edit Member</DialogTitle>
          </DialogHeader>
          <div className="space-y-3">
            <div className="space-y-2">
              <Label htmlFor="edit_name">Full name</Label>
              <Input id="edit_name" value={editName} onChange={(e) => setEditName(e.target.value)} />
            </div>
            <div className="space-y-2">
              <Label htmlFor="edit_phone">Phone</Label>
              <Input id="edit_phone" value={editPhone} onChange={(e) => setEditPhone(e.target.value)} placeholder="9876543210" />
            </div>
            {editError && <p className="text-sm text-destructive">{editError}</p>}
          </div>
          <DialogFooter>
            <Button type="button" onClick={saveEdit} disabled={isSavingEdit}>
              {isSavingEdit ? "Saving…" : "Save"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {renewOpen && (
        <AssignMembershipDialog
          open={renewOpen}
          onOpenChange={setRenewOpen}
          facilityId={facilityId}
          memberId={member.memberId}
          memberName={member.fullName}
          onAssigned={() => {
            setRenewOpen(false);
            onChanged();
          }}
        />
      )}

      {cancelMembershipOpen && member.membershipId && (
        <CancelMembershipDialog
          open={cancelMembershipOpen}
          onOpenChange={setCancelMembershipOpen}
          membershipId={member.membershipId}
          planName={member.planName ?? "Membership"}
          onCancelled={() => {
            setCancelMembershipOpen(false);
            onChanged();
          }}
        />
      )}

      {bookOpen && (
        <BookingDialog
          open={bookOpen}
          onOpenChange={setBookOpen}
          facilityId={facilityId}
          date={new Date()}
          facilitySports={facilitySports}
          sports={sports}
          areas={areas}
          initialMember={{ id: member.memberId, fullName: member.fullName }}
          onBooked={() => setBookOpen(false)}
        />
      )}
    </>
  );
}