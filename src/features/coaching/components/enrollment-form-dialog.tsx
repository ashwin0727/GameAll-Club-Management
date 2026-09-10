"use client";

import { useEffect, useMemo, useState } from "react";
import {
  Dialog,
  DialogContent,
  DialogDescription,
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
import { getCoachingService } from "@/services/coaching";
import { getMembershipService } from "@/services/memberships";
import { minorToRupees, money, rupeesToMinor } from "@/features/coaching/components/shared";
import { usePermissionContext } from "@/features/auth/context/permission-provider";
import type { CoachOption, ProgramOption } from "@/features/coaching/types";

interface MemberHit {
  id: string;
  fullName: string;
  phone: string | null;
}

export function EnrollmentFormDialog({
  facilityId,
  onClose,
  onSaved,
}: {
  facilityId: string;
  onClose: () => void;
  onSaved: (enrollmentId: string) => void;
}) {
  const perms = usePermissionContext();
  const canPrice = perms?.can("COACHING_MANAGE_PRICING") ?? false;

  const [programs, setPrograms] = useState<ProgramOption[]>([]);
  const [coaches, setCoaches] = useState<CoachOption[]>([]);
  const [memberQuery, setMemberQuery] = useState("");
  const [memberHits, setMemberHits] = useState<MemberHit[]>([]);
  const [member, setMember] = useState<MemberHit | null>(null);
  const [programId, setProgramId] = useState("");
  const [coachId, setCoachId] = useState("");
  const [startDate, setStartDate] = useState(() => new Date().toISOString().slice(0, 10));
  const [endDate, setEndDate] = useState("");
  const [sessionsTotal, setSessionsTotal] = useState("");
  const [price, setPrice] = useState("");
  const [notes, setNotes] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const program = useMemo(() => programs.find((p) => p.id === programId), [programs, programId]);

  useEffect(() => {
    getCoachingService().listProgramOptions(facilityId).then(setPrograms).catch(() => setPrograms([]));
    getCoachingService().listCoachOptions(facilityId).then(setCoaches).catch(() => setCoaches([]));
  }, [facilityId]);

  useEffect(() => {
    const t = setTimeout(() => {
      if (memberQuery.trim().length < 2) {
        setMemberHits([]);
        return;
      }
      getMembershipService()
        .searchMembers(facilityId, memberQuery)
        .then((r) => setMemberHits(r.map((m) => ({ id: m.id, fullName: m.fullName, phone: m.phone }))))
        .catch(() => setMemberHits([]));
    }, 300);
    return () => clearTimeout(t);
  }, [memberQuery, facilityId]);

  useEffect(() => {
    if (!program) return;
    setSessionsTotal((cur) => cur || (program.sessionCount != null ? String(program.sessionCount) : ""));
    if (!program.isMembershipIncluded && program.defaultPriceMinor != null) {
      setPrice((cur) => cur || minorToRupees(program.defaultPriceMinor));
    }
  }, [program]);

  async function submit() {
    if (!member) {
      setError("Select a member.");
      return;
    }
    if (!programId) {
      setError("Select a program.");
      return;
    }
    setBusy(true);
    setError(null);
    try {
      const id = await getCoachingService().createEnrollment({
        facilityId,
        memberId: member.id,
        programId,
        coachId: coachId || null,
        startDate,
        endDate: endDate || null,
        sessionsTotal: sessionsTotal.trim() ? Number(sessionsTotal) : null,
        priceMinor: program?.isMembershipIncluded ? 0 : price.trim() ? rupeesToMinor(price) : null,
        pricingType: program?.isMembershipIncluded ? "MEMBERSHIP_INCLUDED" : canPrice && price.trim() ? "CUSTOM" : "STANDARD",
        notes: notes.trim() || null,
      });
      onSaved(id);
    } catch (e) {
      setError(e instanceof ServiceError ? e.message : "Could not create the enrollment.");
      setBusy(false);
    }
  }

  return (
    <Dialog open onOpenChange={(v) => !v && !busy && onClose()}>
      <DialogContent className="max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>Add enrollment</DialogTitle>
          <DialogDescription>Enrol an existing facility member into a coaching program.</DialogDescription>
        </DialogHeader>
        <div className="space-y-3">
          <F label="Member">
            {member ? (
              <div className="flex items-center justify-between rounded-md border border-border px-3 py-2 text-sm">
                <span>
                  {member.fullName}
                  {member.phone ? ` · ${member.phone}` : ""}
                </span>
                <Button size="sm" variant="ghost" onClick={() => setMember(null)}>
                  Change
                </Button>
              </div>
            ) : (
              <>
                <Input
                  value={memberQuery}
                  onChange={(e) => setMemberQuery(e.target.value)}
                  placeholder="Search members by name or phone…"
                />
                {memberHits.length > 0 && (
                  <ul className="mt-1 max-h-40 overflow-y-auto rounded-md border border-border text-sm">
                    {memberHits.map((m) => (
                      <li key={m.id}>
                        <button
                          type="button"
                          className="w-full px-3 py-2 text-left hover:bg-accent"
                          onClick={() => {
                            setMember(m);
                            setMemberHits([]);
                          }}
                        >
                          {m.fullName}
                          {m.phone ? ` · ${m.phone}` : ""}
                        </button>
                      </li>
                    ))}
                  </ul>
                )}
              </>
            )}
          </F>

          <F label="Program">
            <Select value={programId} onValueChange={setProgramId}>
              <SelectTrigger>
                <SelectValue placeholder="Select a program" />
              </SelectTrigger>
              <SelectContent>
                {programs.map((p) => (
                  <SelectItem key={p.id} value={p.id}>
                    {p.name}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </F>

          <F label="Coach (optional)">
            <Select value={coachId || "none"} onValueChange={(v) => setCoachId(v === "none" ? "" : v)}>
              <SelectTrigger>
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="none">No specific coach</SelectItem>
                {coaches.map((c) => (
                  <SelectItem key={c.id} value={c.id}>
                    {c.name}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </F>

          <div className="grid grid-cols-2 gap-3">
            <F label="Start date">
              <Input type="date" value={startDate} onChange={(e) => setStartDate(e.target.value)} />
            </F>
            <F label="End date (optional)">
              <Input type="date" value={endDate} onChange={(e) => setEndDate(e.target.value)} />
            </F>
          </div>

          <div className="grid grid-cols-2 gap-3">
            <F label="Sessions in package">
              <Input type="number" min="1" step="1" value={sessionsTotal} onChange={(e) => setSessionsTotal(e.target.value)} />
            </F>
            {program?.isMembershipIncluded ? (
              <F label="Fee">
                <div className="rounded-md border border-border px-3 py-2 text-sm text-muted-foreground">Included in membership</div>
              </F>
            ) : (
              <F label="Fee (₹)">
                <Input
                  type="number"
                  min="0"
                  step="1"
                  value={price}
                  onChange={(e) => setPrice(e.target.value)}
                  disabled={!canPrice && program?.defaultPriceMinor != null}
                />
              </F>
            )}
          </div>
          {program && !program.isMembershipIncluded && (
            <p className="text-xs text-muted-foreground">
              The fee is an obligation of {money(rupeesToMinor(price) ?? 0)} — record a payment against it from Pending Payments.
            </p>
          )}

          <F label="Notes (optional)">
            <Textarea rows={2} value={notes} onChange={(e) => setNotes(e.target.value)} />
          </F>

          {error && <p className="text-sm text-destructive">{error}</p>}
        </div>
        <DialogFooter>
          <Button variant="outline" disabled={busy} onClick={onClose}>
            Cancel
          </Button>
          <Button disabled={busy} onClick={() => void submit()}>
            {busy ? "Enrolling…" : "Create Enrollment"}
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
