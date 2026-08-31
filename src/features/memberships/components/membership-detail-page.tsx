"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import {
  ArrowLeft,
  Pencil,
  Plus,
  MoreVertical,
  Trash2,
  Ban,
  Phone,
  Mail,
  Cake,
  MapPin,
  IdCard,
  CalendarDays,
  Link2,
  Copy,
} from "lucide-react";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Card } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogDescription,
  DialogFooter,
} from "@/components/ui/dialog";
import {
  DropdownMenu,
  DropdownMenuTrigger,
  DropdownMenuContent,
  DropdownMenuItem,
} from "@/components/ui/dropdown-menu";
import { Avatar, AvatarFallback } from "@/components/ui/avatar";
import { getMembershipService } from "@/services/memberships";
import { formatSlot } from "@/features/memberships/slot-format";
import { validateMemberPhone } from "@/features/members/validation";
import { ServiceError } from "@/services/shared/service-error";
import type { MembershipDetail, MembershipListStatus } from "@/features/memberships/types";

function inr(v: number): string {
  return `₹${v.toLocaleString("en-IN", { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
}
function fmtDate(iso: string | null): string {
  return iso ? new Date(iso).toLocaleDateString("en-IN", { day: "2-digit", month: "short", year: "numeric" }) : "—";
}
function fmtDateTime(iso: string | null): string {
  return iso
    ? new Date(iso).toLocaleString("en-IN", { day: "2-digit", month: "short", year: "numeric", hour: "numeric", minute: "2-digit", hour12: true })
    : "—";
}
function ageFromDob(iso: string | null): string {
  if (!iso) return "";
  const years = Math.floor((Date.now() - new Date(iso).getTime()) / 31557600000);
  return years > 0 && years < 130 ? ` (${years} yrs)` : "";
}
function initials(name: string): string {
  return name.split(" ").filter(Boolean).slice(0, 2).map((p) => p[0]!.toUpperCase()).join("");
}
function titleCase(s: string): string {
  return s.charAt(0).toUpperCase() + s.slice(1).toLowerCase();
}

function statusBadge(status: MembershipListStatus) {
  switch (status) {
    case "active":
      return <Badge variant="success">Active</Badge>;
    case "payment_not_initiated":
      return <Badge variant="warning">Payment Not Initiated</Badge>;
    case "inactive":
      return <Badge variant="secondary">Inactive</Badge>;
    default:
      return <Badge variant="secondary">{String(status).replace(/_/g, " ")}</Badge>;
  }
}

function paymentBadge(status: string | undefined) {
  if (status === "paid") return <Badge variant="success">Paid</Badge>;
  if (status === "refunded") return <Badge variant="secondary">Refunded</Badge>;
  if (status === "failed") return <Badge variant="destructive">Failed</Badge>;
  return <Badge variant="warning">Pending</Badge>;
}

function Row({ label, value }: { label: string; value: React.ReactNode }) {
  return (
    <div className="flex items-baseline justify-between gap-4 py-1.5 text-sm">
      <span className="shrink-0 text-muted-foreground">{label}</span>
      <span className="text-right font-medium text-foreground">{value}</span>
    </div>
  );
}

function HeaderStat({ icon: Icon, label, value }: { icon: React.ComponentType<{ className?: string }>; label: string; value: React.ReactNode }) {
  return (
    <div className="flex items-start gap-2">
      <Icon className="mt-0.5 h-4 w-4 shrink-0 text-muted-foreground" />
      <div className="min-w-0">
        <p className="text-xs text-muted-foreground">{label}</p>
        <p className="truncate text-sm font-medium text-foreground">{value}</p>
      </div>
    </div>
  );
}

export function MembershipDetailPage({ membershipId }: { membershipId: string }) {
  const router = useRouter();
  const [detail, setDetail] = useState<MembershipDetail | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const [editOpen, setEditOpen] = useState(false);
  const [editName, setEditName] = useState("");
  const [editPhone, setEditPhone] = useState("");
  const [editEmail, setEditEmail] = useState("");
  const [editError, setEditError] = useState<string | null>(null);
  const [savingEdit, setSavingEdit] = useState(false);

  const [confirm, setConfirm] = useState<null | "delete" | "cancel">(null);
  const [acting, setActing] = useState(false);
  const [actionError, setActionError] = useState<string | null>(null);
  const [linkCopied, setLinkCopied] = useState(false);

  async function load() {
    setLoading(true);
    setError(null);
    try {
      const d = await getMembershipService().getMembershipDetail(membershipId);
      setDetail(d);
    } catch (err) {
      setError(err instanceof ServiceError ? err.message : "Unable to load this membership.");
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    load();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [membershipId]);

  function openEdit() {
    if (!detail) return;
    setEditName(detail.member.fullName);
    setEditPhone(detail.member.phone);
    setEditEmail(detail.member.email ?? "");
    setEditError(null);
    setEditOpen(true);
  }

  async function saveEdit() {
    if (!detail) return;
    if (editName.trim().length < 2) return setEditError("Enter at least 2 characters.");
    const phoneError = validateMemberPhone(editPhone);
    if (phoneError) return setEditError(phoneError);
    setSavingEdit(true);
    setEditError(null);
    try {
      await getMembershipService().updateMember(detail.member.id, {
        fullName: editName.trim(),
        phone: editPhone.trim(),
        email: editEmail.trim() || undefined,
      });
      setEditOpen(false);
      load();
    } catch (err) {
      setEditError(err instanceof ServiceError ? err.message : "Unable to save changes.");
    } finally {
      setSavingEdit(false);
    }
  }

  async function runAction() {
    if (!detail || !confirm) return;
    setActing(true);
    setActionError(null);
    try {
      if (confirm === "delete") {
        await getMembershipService().deleteMember(detail.member.id);
        router.push("/memberships");
        return;
      }
      await getMembershipService().cancelMembership(detail.membershipId);
      setConfirm(null);
      load();
    } catch (err) {
      setActionError(err instanceof ServiceError ? err.message : "Unable to complete this action.");
    } finally {
      setActing(false);
    }
  }

  function shareLink() {
    if (!detail) return;
    const url = `${window.location.origin}/join/${detail.facilityId}`;
    navigator.clipboard.writeText(url).then(
      () => {
        setLinkCopied(true);
        setTimeout(() => setLinkCopied(false), 2000);
      },
      () => window.prompt("Copy this membership sign-up link:", url),
    );
  }

  const joinUrl = detail ? `${typeof window !== "undefined" ? window.location.origin : ""}/join/${detail.facilityId}` : "";

  return (
    <div className="space-y-6">
      <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
        <div className="flex items-start gap-3">
          <Button type="button" variant="ghost" size="icon" onClick={() => router.push("/memberships")}>
            <ArrowLeft className="h-4 w-4" />
          </Button>
          <div>
            <h1 className="text-xl font-semibold">Membership Details</h1>
            <p className="text-xs text-muted-foreground">Memberships / Membership Details</p>
          </div>
        </div>
        {detail && (
          <div className="flex flex-wrap items-center gap-2">
            <Button type="button" variant="outline" size="sm" onClick={openEdit}>
              <Pencil className="mr-1.5 h-4 w-4" />
              Edit
            </Button>
            <Button type="button" size="sm" onClick={() => router.push("/memberships/new")}>
              <Plus className="mr-1.5 h-4 w-4" />
              Create Membership
            </Button>
            <DropdownMenu>
              <DropdownMenuTrigger asChild>
                <Button type="button" variant="ghost" size="icon" aria-label="More actions">
                  <MoreVertical className="h-4 w-4" />
                </Button>
              </DropdownMenuTrigger>
              <DropdownMenuContent align="end">
                {detail.displayStatus === "active" && detail.membership.rawStatus !== "cancelled" && (
                  <DropdownMenuItem onClick={() => { setActionError(null); setConfirm("cancel"); }}>
                    <Ban className="mr-2 h-4 w-4" />
                    Cancel membership
                  </DropdownMenuItem>
                )}
                <DropdownMenuItem className="text-destructive focus:text-destructive" onClick={() => { setActionError(null); setConfirm("delete"); }}>
                  <Trash2 className="mr-2 h-4 w-4" />
                  Delete member
                </DropdownMenuItem>
              </DropdownMenuContent>
            </DropdownMenu>
          </div>
        )}
      </div>

      {loading ? (
        <Skeleton className="h-[70vh] w-full rounded-xl" />
      ) : error || !detail ? (
        <Card className="p-8 text-center text-sm text-muted-foreground">
          {error ?? "Membership not found."}
          <div className="mt-4">
            <Button type="button" variant="outline" size="sm" onClick={load}>
              Try again
            </Button>
          </div>
        </Card>
      ) : (
        <>
          {/* Header card */}
          <Card className="p-5">
            <div className="flex flex-col gap-4 sm:flex-row sm:items-start">
              <Avatar className="h-16 w-16">
                <AvatarFallback className="text-lg">{initials(detail.member.fullName)}</AvatarFallback>
              </Avatar>
              <div className="min-w-0 flex-1">
                <div className="flex flex-wrap items-center gap-2">
                  <h2 className="text-lg font-semibold">{detail.member.fullName}</h2>
                  {statusBadge(detail.displayStatus)}
                </div>
                <div className="mt-1 flex flex-wrap gap-x-4 gap-y-1 text-xs text-muted-foreground">
                  <span className="flex items-center gap-1"><Phone className="h-3.5 w-3.5" />{detail.member.phone}</span>
                  {detail.member.email && <span className="flex items-center gap-1"><Mail className="h-3.5 w-3.5" />{detail.member.email}</span>}
                  {detail.member.dateOfBirth && (
                    <span className="flex items-center gap-1"><Cake className="h-3.5 w-3.5" />{fmtDate(detail.member.dateOfBirth)}{ageFromDob(detail.member.dateOfBirth)}</span>
                  )}
                  {detail.member.address && <span className="flex items-center gap-1"><MapPin className="h-3.5 w-3.5" />{detail.member.address}</span>}
                </div>

                <div className="mt-4 grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
                  <HeaderStat icon={IdCard} label="Membership Type" value={detail.membership.name} />
                  <HeaderStat icon={CalendarDays} label="Member Since" value={fmtDate(detail.member.memberSince)} />
                  <HeaderStat
                    icon={IdCard}
                    label="Linked By"
                    value={detail.createdByName ?? "Self registered"}
                  />
                  <HeaderStat icon={CalendarDays} label="Start Date" value={fmtDate(detail.membership.startDate)} />
                  <HeaderStat icon={IdCard} label="Payment Status" value={paymentBadge(detail.payment?.status)} />
                  <HeaderStat
                    icon={CalendarDays}
                    label={detail.membership.autoRenew ? "Next Payment" : "Expiry"}
                    value={fmtDate(detail.membership.endDate)}
                  />
                </div>
              </div>
            </div>
          </Card>

          {/* Three info cards */}
          <div className="grid gap-6 lg:grid-cols-3">
            <Card className="p-5">
              <h3 className="mb-3 text-sm font-semibold">Membership Information</h3>
              <Row label="Membership Type" value={detail.membership.name} />
              <Row label="Category" value={titleCase(detail.membership.membershipType)} />
              <Row label="Start Date" value={fmtDate(detail.membership.startDate)} />
              <Row
                label={detail.membership.autoRenew ? "Next Payment Date" : "Expiry Date"}
                value={fmtDate(detail.membership.endDate)}
              />
              {detail.membership.durationDays != null && <Row label="Duration" value={`${detail.membership.durationDays} days`} />}
              {detail.membership.membershipType === "FAMILY" && (
                <Row label="Max. Members" value={detail.membership.maxFamilyMembers} />
              )}
              {detail.slot && (
                <Row
                  label="Time Slot"
                  value={
                    <span className="text-xs">
                      {detail.slot.courtName ? `${detail.slot.courtName} · ` : ""}
                      {formatSlot(detail.slot.daysOfWeek, detail.slot.startTime, detail.slot.endTime)}
                    </span>
                  }
                />
              )}
              {detail.membership.description && (
                <div className="mt-2 border-t border-border pt-2">
                  <p className="text-xs text-muted-foreground">Description</p>
                  <p className="mt-1 text-sm">{detail.membership.description}</p>
                </div>
              )}
            </Card>

            <Card className="p-5">
              <h3 className="mb-3 text-sm font-semibold">Charges &amp; Payment</h3>
              <Row label="Membership Fee" value={inr(detail.membership.membershipFeeInr)} />
              <Row label="Registration Fee" value={inr(detail.membership.registrationFeeInr)} />
              <Row
                label="Sub Total"
                value={inr(detail.membership.membershipFeeInr + detail.membership.registrationFeeInr)}
              />
              <Row label={`GST (${detail.membership.gstPercent}%)`} value={inr(Math.max(0, detail.membership.totalAmountInr - detail.membership.membershipFeeInr - detail.membership.registrationFeeInr))} />
              <div className="my-2 border-t border-border" />
              <div className="flex items-baseline justify-between text-sm font-semibold text-success">
                <span>Total Amount</span>
                <span>{inr(detail.membership.totalAmountInr)}</span>
              </div>
              <div className="mt-3 border-t border-border pt-2">
                <Row label="Payment Mode" value={detail.payment?.method ? detail.payment.method.toUpperCase() : "—"} />
                <Row label="Payment Date" value={fmtDateTime(detail.payment?.paidAt ?? detail.payment?.createdAt ?? null)} />
                {detail.payment?.transactionId && <Row label="Transaction ID" value={<span className="text-xs">{detail.payment.transactionId}</span>} />}
                {detail.paymentReference && <Row label="Reference" value={<span className="text-xs">{detail.paymentReference}</span>} />}
                <Row label="Payment Status" value={paymentBadge(detail.payment?.status)} />
              </div>
            </Card>

            <Card className="p-5">
              <h3 className="mb-3 text-sm font-semibold">Additional Information</h3>
              <Row label="Contact Number" value={detail.member.phone} />
              {detail.member.gender && <Row label="Gender" value={detail.member.gender} />}
              <Row label="How did you find us?" value={detail.discoverySource ?? "—"} />
              <Row label="Referral By" value={detail.referralName ?? "—"} />

              <div className="mt-4 border-t border-border pt-3">
                <div className="flex items-center justify-between">
                  <p className="text-sm font-semibold">Notes</p>
                </div>
                <p className="mt-1 text-sm text-muted-foreground">{detail.notes ?? "No notes added."}</p>
              </div>
            </Card>
          </div>

          {/* Membership link */}
          <Card className="p-5">
            <h3 className="mb-1 flex items-center gap-2 text-sm font-semibold">
              <Link2 className="h-4 w-4" /> Membership Link
            </h3>
            <p className="text-xs text-muted-foreground">Share this link with players so they can register for membership on their own.</p>
            <div className="mt-3 flex flex-wrap items-center gap-2">
              <Input readOnly value={joinUrl} className="h-9 max-w-md text-xs" />
              <Button type="button" variant="outline" size="sm" onClick={shareLink}>
                <Copy className="mr-1.5 h-4 w-4" />
                {linkCopied ? "Copied" : "Share Link"}
              </Button>
            </div>
          </Card>

          {/* Activity timeline */}
          <Card className="p-5">
            <h3 className="mb-4 text-sm font-semibold">Activity Timeline</h3>
            {detail.timeline.length === 0 ? (
              <p className="text-sm text-muted-foreground">No activity recorded.</p>
            ) : (
              <ol className="space-y-4">
                {detail.timeline.map((ev, i) => (
                  <li key={i} className="flex gap-3">
                    <span className="mt-1 h-2 w-2 shrink-0 rounded-full bg-success" />
                    <div className="flex flex-wrap items-baseline gap-x-3">
                      <span className="text-sm font-medium">{ev.label}</span>
                      <span className="text-xs text-muted-foreground">{ev.actor}</span>
                      <span className="text-xs text-muted-foreground">{fmtDateTime(ev.at)}</span>
                    </div>
                  </li>
                ))}
              </ol>
            )}
          </Card>
        </>
      )}

      {/* Edit member dialog */}
      <Dialog open={editOpen} onOpenChange={(o) => !savingEdit && setEditOpen(o)}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Edit Member</DialogTitle>
          </DialogHeader>
          <div className="space-y-3">
            <div className="space-y-2">
              <Label htmlFor="md_name">Full name</Label>
              <Input id="md_name" value={editName} onChange={(e) => setEditName(e.target.value)} />
            </div>
            <div className="space-y-2">
              <Label htmlFor="md_phone">Phone</Label>
              <Input id="md_phone" value={editPhone} onChange={(e) => setEditPhone(e.target.value)} placeholder="9876543210" />
            </div>
            <div className="space-y-2">
              <Label htmlFor="md_email">Email</Label>
              <Input id="md_email" value={editEmail} onChange={(e) => setEditEmail(e.target.value)} type="email" />
            </div>
            {editError && <p className="text-sm text-destructive">{editError}</p>}
          </div>
          <DialogFooter>
            <Button type="button" variant="outline" disabled={savingEdit} onClick={() => setEditOpen(false)}>
              Cancel
            </Button>
            <Button type="button" onClick={saveEdit} disabled={savingEdit}>
              {savingEdit ? "Saving…" : "Save"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Delete / Cancel confirm */}
      <Dialog open={confirm !== null} onOpenChange={(o) => !acting && !o && setConfirm(null)}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>{confirm === "delete" ? "Delete member" : "Cancel membership"}</DialogTitle>
            <DialogDescription>
              {confirm === "delete"
                ? "Permanently remove this member. This only works when they have no bookings and no settled payments."
                : "End this membership now. The record is kept for history."}
            </DialogDescription>
          </DialogHeader>
          {actionError && <p className="text-sm text-destructive">{actionError}</p>}
          <DialogFooter>
            <Button type="button" variant="outline" disabled={acting} onClick={() => setConfirm(null)}>
              Keep
            </Button>
            <Button type="button" variant="destructive" disabled={acting} onClick={runAction}>
              {acting ? "Working…" : confirm === "delete" ? "Delete" : "Cancel Membership"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}