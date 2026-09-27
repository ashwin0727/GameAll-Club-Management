"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { Check, ChevronRight, Search } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Textarea } from "@/components/ui/textarea";
import { getCoachingService } from "@/services/coaching";
import { getFinanceService } from "@/services/finance";
import { getMembershipService } from "@/services/memberships";
import { MemberAlreadyExistsError } from "@/services/memberships/supabase-membership.service";
import { ServiceError } from "@/services/shared/service-error";
import { usePermissionContext } from "@/features/auth/context/permission-provider";
import { PermissionDenied } from "@/features/staff/components/permission-denied";
import { useFacilitySportOptions } from "@/features/facility/hooks/use-facility-sport-options";
import type { ProgramDetail, ProgramRow } from "@/features/coaching/types";
import { blurOnWheel, fmtDate, money, NO_SPINNER_INPUT } from "@/features/coaching/components/shared";
import { cn } from "@/lib/utils";

const STEPS = ["Student Details", "Program & Enrollment", "Review & Confirm", "Payment", "Success"] as const;
type Step = (typeof STEPS)[number];

interface MemberHit {
  id: string;
  fullName: string;
  phone: string | null;
  email: string | null;
}

function Field({ label, required, children }: { label: string; required?: boolean; children: React.ReactNode }) {
  return (
    <div className="space-y-1.5">
      <Label>
        {label}
        {required && <span className="text-destructive"> *</span>}
      </Label>
      {children}
    </div>
  );
}

function StepNumber({ n, done }: { n: number; done: boolean }) {
  return (
    <span className={cn("flex h-7 w-7 shrink-0 items-center justify-center rounded-full text-sm font-semibold", done ? "bg-success text-white" : "bg-muted text-muted-foreground")}>
      {done ? <Check className="h-4 w-4" aria-hidden /> : n}
    </span>
  );
}

/**
 * Add Student — Student Details → Program & Enrollment → Review & Confirm → Payment → Success.
 * Deliberately does NOT schedule sessions: the selected Coaching Program/Batch already defines
 * the schedule (day/time/court/coach); this wizard only connects an existing (or newly created)
 * member to that program + batch and collects the resulting fee, reusing the same member
 * identity, enrollment and Pending-Payments obligation architecture the rest of the app already
 * uses — no new Student/Program/Batch/payment engine.
 */
export function AddStudentWizardPage() {
  const perms = usePermissionContext();
  const facilityId = perms?.facilityId ?? null;

  const [step, setStep] = useState<Step>("Student Details");
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  // Step 1 — Student Details
  const [memberQuery, setMemberQuery] = useState("");
  const [memberHits, setMemberHits] = useState<MemberHit[]>([]);
  const [selectedMember, setSelectedMember] = useState<MemberHit | null>(null);
  const [fullName, setFullName] = useState("");
  const [phone, setPhone] = useState("");
  const [email, setEmail] = useState("");
  const [dateOfBirth, setDateOfBirth] = useState("");
  const [gender, setGender] = useState("");
  const [address, setAddress] = useState("");
  const [emergencyName, setEmergencyName] = useState("");
  const [emergencyPhone, setEmergencyPhone] = useState("");
  const [notes, setNotes] = useState("");
  const [existingWarning, setExistingWarning] = useState<string | null>(null);

  // Step 2 — Program & Enrollment
  const [programs, setPrograms] = useState<ProgramRow[] | null>(null);
  const [programId, setProgramId] = useState("");
  const [program, setProgram] = useState<ProgramDetail | null>(null);
  const [batchId, setBatchId] = useState("");
  const [startDate, setStartDate] = useState(() => new Date().toISOString().slice(0, 10));
  const sportsQuery = useFacilitySportOptions(facilityId ?? undefined);

  // Step 4 — Payment
  const [enrollmentId, setEnrollmentId] = useState<string | null>(null);
  const [paymentMode, setPaymentMode] = useState<"OFFLINE" | "LATER" | null>(null);
  const [payAmount, setPayAmount] = useState("");
  const [payMethod, setPayMethod] = useState("Cash");
  const [payReference, setPayReference] = useState("");
  const [paidSoFar, setPaidSoFar] = useState(0);

  useEffect(() => {
    if (!facilityId) return;
    getCoachingService()
      .listPrograms({ facilityId, filters: { status: "ACTIVE" }, limit: 100 })
      .then((p) => setPrograms(p.programs))
      .catch(() => setPrograms([]));
  }, [facilityId]);

  useEffect(() => {
    if (!facilityId) return;
    const t = setTimeout(() => {
      if (memberQuery.trim().length < 2) {
        setMemberHits([]);
        return;
      }
      getMembershipService()
        .searchMembers(facilityId, memberQuery)
        .then((r) => setMemberHits(r))
        .catch(() => setMemberHits([]));
    }, 300);
    return () => clearTimeout(t);
  }, [memberQuery, facilityId]);

  useEffect(() => {
    if (!programId) {
      setProgram(null);
      return;
    }
    getCoachingService()
      .getProgram(programId)
      .then((p) => {
        setProgram(p);
        setBatchId(p.batches[0]?.id ?? "");
      })
      .catch(() => setProgram(null));
  }, [programId]);

  if (!perms?.can("COACHING_MANAGE_ENROLLMENTS")) {
    return <PermissionDenied message="You don't have permission to manage coaching enrollments." />;
  }

  const stepIndex = STEPS.indexOf(step);
  const sportName = sportsQuery.data?.find((s) => s.facilitySportId === program?.facilitySportId)?.name;
  const selectedBatch = program?.batches.find((b) => b.id === batchId);

  const baseFeeInr = program?.defaultPriceMinor != null ? program.defaultPriceMinor / 100 : 0;
  const discountInr = program?.earlyBirdDiscountMinor != null ? program.earlyBirdDiscountMinor / 100 : 0;
  const taxInr = program?.taxPercent ? Math.round(((baseFeeInr - discountInr) * program.taxPercent) / 100) : 0;
  const amountPayableInr = program?.isMembershipIncluded ? 0 : Math.max(0, baseFeeInr - discountInr) + taxInr;

  const step1Valid = selectedMember ? true : Boolean(fullName.trim() && phone.trim().length >= 10);
  const step2Valid = Boolean(programId) && (program ? program.batches.length === 0 || Boolean(batchId) : false) && Boolean(startDate);

  function composeNotes(): string | null {
    const parts: string[] = [];
    if (emergencyName.trim() || emergencyPhone.trim()) {
      parts.push(`Emergency Contact: ${emergencyName.trim() || "—"}${emergencyPhone.trim() ? ` (${emergencyPhone.trim()})` : ""}`);
    }
    if (notes.trim()) parts.push(notes.trim());
    return parts.length ? parts.join("\n") : null;
  }

  async function goNextFromStep1() {
    setError(null);
    if (selectedMember) {
      setStep("Program & Enrollment");
      return;
    }
    if (!fullName.trim() || !phone.trim()) {
      setError("Enter the student's full name and phone number.");
      return;
    }
    setBusy(true);
    try {
      const member = await getMembershipService().createMember({
        facilityId: facilityId!,
        fullName: fullName.trim(),
        phone: phone.trim(),
        email: email.trim() || null,
        dateOfBirth: dateOfBirth || null,
        gender: gender || null,
        notes: composeNotes(),
      });
      setSelectedMember({ id: member.id, fullName: member.fullName, phone: member.phone, email: member.email });
      setStep("Program & Enrollment");
    } catch (e) {
      if (e instanceof MemberAlreadyExistsError) {
        setExistingWarning(e.existingMemberId);
        setError("A student with this phone number already exists. Use the search above to find and select them instead.");
      } else {
        setError(e instanceof ServiceError ? e.message : "Could not create the student.");
      }
    } finally {
      setBusy(false);
    }
  }

  async function confirmEnrollment() {
    if (!facilityId || !selectedMember || !programId) return;
    setBusy(true);
    setError(null);
    try {
      const id = await getCoachingService().createEnrollment({
        facilityId,
        memberId: selectedMember.id,
        programId,
        batchId: batchId || null,
        startDate,
        priceMinor: program?.isMembershipIncluded ? 0 : Math.round(amountPayableInr * 100),
        pricingType: program?.isMembershipIncluded ? "MEMBERSHIP_INCLUDED" : "STANDARD",
      });
      setEnrollmentId(id);
      setStep("Payment");
    } catch (e) {
      setError(e instanceof ServiceError ? e.message : "Could not create the enrollment.");
    } finally {
      setBusy(false);
    }
  }

  async function recordPayment(full: boolean) {
    if (!enrollmentId) return;
    const remaining = Math.round(amountPayableInr * 100) - paidSoFar;
    const amountMinor = full ? remaining : Math.round((Number(payAmount) || 0) * 100);
    if (amountMinor <= 0 || amountMinor > remaining) {
      setError("Enter a valid amount up to the outstanding balance.");
      return;
    }
    setBusy(true);
    setError(null);
    try {
      await getFinanceService().recordObligationPayment({
        sourceType: "COACHING_ENROLLMENT",
        sourceId: enrollmentId,
        amountMinor,
        method: payMethod,
        reference: payReference.trim() || null,
        idempotencyKey: `${enrollmentId}:${crypto.randomUUID()}`,
      });
      setPaidSoFar((p) => p + amountMinor);
      setPayAmount("");
      setStep("Success");
    } catch (e) {
      setError(e instanceof ServiceError ? e.message : "Could not record this payment.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="space-y-4">
      <nav aria-label="Breadcrumb" className="flex items-center gap-1 text-xs text-muted-foreground">
        <Link href="/coaching" className="hover:text-foreground">
          Coaching
        </Link>
        <ChevronRight className="h-3.5 w-3.5" aria-hidden />
        <Link href="/coaching/students" className="hover:text-foreground">
          Manage Students
        </Link>
        <ChevronRight className="h-3.5 w-3.5" aria-hidden />
        <span className="font-medium text-foreground">Add Student</span>
      </nav>
      <h1 className="text-2xl font-bold">Add Student</h1>
      <p className="text-sm text-muted-foreground">Enroll a student into an existing coaching program.</p>

      <ol className="flex flex-wrap gap-2 text-xs">
        {STEPS.map((s, i) => (
          <li key={s} className="flex items-center gap-1.5 rounded-full border px-3 py-1.5 font-medium">
            <StepNumber n={i + 1} done={i < stepIndex} />
            <span className={i === stepIndex ? "text-primary" : "text-muted-foreground"}>{s}</span>
          </li>
        ))}
      </ol>

      <div className="rounded-xl border border-border bg-card p-5">
        {step === "Student Details" && (
          <div className="space-y-4">
            <Field label="Search Existing Student">
              <div className="relative">
                <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" aria-hidden />
                <Input
                  value={memberQuery}
                  onChange={(e) => {
                    setMemberQuery(e.target.value);
                    setSelectedMember(null);
                  }}
                  placeholder="Search by name, phone or email…"
                  className="pl-9"
                />
              </div>
              {memberHits.length > 0 && !selectedMember && (
                <ul className="mt-1 max-h-48 overflow-y-auto rounded-lg border border-border text-sm">
                  {memberHits.map((m) => (
                    <li key={m.id}>
                      <button
                        type="button"
                        className="w-full px-3 py-2 text-left hover:bg-accent"
                        onClick={() => {
                          setSelectedMember(m);
                          setMemberHits([]);
                          setMemberQuery(m.fullName);
                        }}
                      >
                        {m.fullName}
                        {m.phone ? ` · ${m.phone}` : ""}
                      </button>
                    </li>
                  ))}
                </ul>
              )}
            </Field>

            {selectedMember ? (
              <div className="flex items-center justify-between rounded-lg border border-success/30 bg-success/5 p-3 text-sm">
                <div>
                  <p className="flex items-center gap-1.5 font-medium text-success">
                    <Check className="h-4 w-4" aria-hidden /> Existing student found
                  </p>
                  <p className="text-muted-foreground">
                    {selectedMember.fullName}
                    {selectedMember.phone ? ` · ${selectedMember.phone}` : ""}
                    {selectedMember.email ? ` · ${selectedMember.email}` : ""}
                  </p>
                </div>
                <button type="button" className="text-xs text-muted-foreground hover:underline" onClick={() => setSelectedMember(null)}>
                  Change
                </button>
              </div>
            ) : (
              <>
                <p className="text-xs text-muted-foreground">No match? Enter the student&apos;s details to create a new one.</p>
                <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
                  <Field label="Full Name" required>
                    <Input value={fullName} onChange={(e) => setFullName(e.target.value)} />
                  </Field>
                  <Field label="Phone Number" required>
                    <Input value={phone} onChange={(e) => setPhone(e.target.value)} />
                  </Field>
                  <Field label="Email">
                    <Input type="email" value={email} onChange={(e) => setEmail(e.target.value)} />
                  </Field>
                  <Field label="Date of Birth">
                    <Input type="date" value={dateOfBirth} onChange={(e) => setDateOfBirth(e.target.value)} />
                  </Field>
                  <Field label="Gender">
                    <Select value={gender} onValueChange={setGender}>
                      <SelectTrigger>
                        <SelectValue placeholder="Select" />
                      </SelectTrigger>
                      <SelectContent>
                        <SelectItem value="Male">Male</SelectItem>
                        <SelectItem value="Female">Female</SelectItem>
                        <SelectItem value="Other">Other</SelectItem>
                      </SelectContent>
                    </Select>
                  </Field>
                  <Field label="Address">
                    <Input value={address} onChange={(e) => setAddress(e.target.value)} />
                  </Field>
                  <Field label="Emergency Contact Name">
                    <Input value={emergencyName} onChange={(e) => setEmergencyName(e.target.value)} />
                  </Field>
                  <Field label="Emergency Contact Number">
                    <Input value={emergencyPhone} onChange={(e) => setEmergencyPhone(e.target.value)} />
                  </Field>
                </div>
                <Field label="Notes (Optional)">
                  <Textarea rows={2} value={notes} onChange={(e) => setNotes(e.target.value)} />
                </Field>
              </>
            )}
            {existingWarning && (
              <Link href={`/coaching/enrollments?memberId=${existingWarning}`} className="text-xs text-primary hover:underline">
                View existing student →
              </Link>
            )}
          </div>
        )}

        {step === "Program & Enrollment" && (
          <div className="space-y-4">
            <Field label="Coaching Program" required>
              <Select value={programId} onValueChange={setProgramId}>
                <SelectTrigger>
                  <SelectValue placeholder={programs === null ? "Loading…" : "Select a program"} />
                </SelectTrigger>
                <SelectContent>
                  {(programs ?? []).map((p) => (
                    <SelectItem key={p.id} value={p.id}>
                      {p.name}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </Field>
            {programs?.length === 0 && <p className="text-sm text-muted-foreground">No active coaching programs available.</p>}

            {program && (
              <div className="rounded-lg border border-border p-3 text-sm">
                <p className="font-semibold">{program.name}</p>
                <div className="mt-1.5 flex flex-wrap gap-x-4 gap-y-1 text-xs text-muted-foreground">
                  <span>{sportName ?? "—"}</span>
                  <span>{program.level}</span>
                  <span>{program.startDate && program.endDate ? `${fmtDate(program.startDate)} – ${fmtDate(program.endDate)}` : "—"}</span>
                  <span>{program.isMembershipIncluded ? "Included" : program.defaultPriceMinor != null ? money(program.defaultPriceMinor) : "—"}</span>
                </div>
              </div>
            )}

            {program && program.batches.length > 0 && (
              <Field label="Select Batch" required>
                <div className="space-y-2">
                  {program.batches.map((b) => {
                    const full = (b.enrolledCount ?? 0) >= b.capacity;
                    return (
                      <button
                        key={b.id}
                        type="button"
                        disabled={full && b.id !== batchId}
                        onClick={() => setBatchId(b.id)}
                        className={cn(
                          "flex w-full items-center justify-between rounded-lg border p-3 text-left text-sm transition-colors",
                          batchId === b.id ? "border-success bg-success/10" : full ? "cursor-not-allowed border-input opacity-50" : "border-input hover:bg-accent/50",
                        )}
                      >
                        <div>
                          <p className="font-medium">{b.name}</p>
                          <p className="text-xs text-muted-foreground">
                            {b.daysOfWeek.map((d) => ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][d]).join(", ")} · {b.startTime}–{b.endTime}
                            {b.coachName ? ` · ${b.coachName}` : ""}
                          </p>
                        </div>
                        <Badge variant={full ? "destructive" : "outline"}>
                          {full ? "Full" : `${b.enrolledCount ?? 0} / ${b.capacity}`}
                        </Badge>
                      </button>
                    );
                  })}
                </div>
              </Field>
            )}
            {program && program.batches.length === 0 && <p className="text-xs text-muted-foreground">This program has no active batches available for enrollment.</p>}

            <Field label="Enrollment Start Date" required>
              <Input type="date" value={startDate} onChange={(e) => setStartDate(e.target.value)} />
            </Field>
          </div>
        )}

        {step === "Review & Confirm" && program && (
          <div className="space-y-4">
            <div>
              <p className="text-xs text-muted-foreground">Student</p>
              <p className="text-sm font-medium">
                {selectedMember?.fullName}
                {selectedMember?.phone ? ` · ${selectedMember.phone}` : ""}
              </p>
            </div>
            <div>
              <p className="text-xs text-muted-foreground">Program</p>
              <p className="text-sm font-medium">
                {program.name} — {sportName ?? "—"}, {program.level}
              </p>
            </div>
            {selectedBatch && (
              <div>
                <p className="text-xs text-muted-foreground">Batch Schedule (informational — already configured)</p>
                <p className="text-sm font-medium">
                  {selectedBatch.name} · {selectedBatch.daysOfWeek.map((d) => ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][d]).join(", ")} · {selectedBatch.startTime}–{selectedBatch.endTime}
                  {selectedBatch.coachName ? ` · Coach ${selectedBatch.coachName}` : ""}
                </p>
              </div>
            )}
            <div>
              <p className="text-xs text-muted-foreground">Enrollment Start Date</p>
              <p className="text-sm font-medium">{fmtDate(startDate)}</p>
            </div>
            <div className="rounded-lg border border-border p-3 text-sm">
              <p className="mb-2 text-xs font-semibold text-muted-foreground">Payment Summary</p>
              {program.isMembershipIncluded ? (
                <p className="font-medium">Included — no fee</p>
              ) : (
                <dl className="space-y-1.5">
                  <div className="flex justify-between">
                    <dt className="text-muted-foreground">Program Fee</dt>
                    <dd>{money(Math.round(baseFeeInr * 100))}</dd>
                  </div>
                  {discountInr > 0 && (
                    <div className="flex justify-between text-success">
                      <dt>Discount</dt>
                      <dd>-{money(Math.round(discountInr * 100))}</dd>
                    </div>
                  )}
                  <div className="flex justify-between">
                    <dt className="text-muted-foreground">Tax</dt>
                    <dd>{money(Math.round(taxInr * 100))}</dd>
                  </div>
                  <div className="flex justify-between border-t border-border pt-1.5 font-semibold">
                    <dt>Amount Payable</dt>
                    <dd>{money(Math.round(amountPayableInr * 100))}</dd>
                  </div>
                </dl>
              )}
            </div>
          </div>
        )}

        {step === "Payment" && enrollmentId && (
          <div className="space-y-4">
            <div className="rounded-lg border border-border p-3 text-sm">
              <div className="flex items-center justify-between">
                <span className="text-muted-foreground">Amount Payable</span>
                <span className="text-lg font-bold">{money(Math.round(amountPayableInr * 100) - paidSoFar)}</span>
              </div>
            </div>
            {Math.round(amountPayableInr * 100) - paidSoFar <= 0 ? (
              <p className="text-sm text-success">No payment due.</p>
            ) : (
              <>
                <div className="grid grid-cols-2 gap-2">
                  <button
                    type="button"
                    onClick={() => setPaymentMode("OFFLINE")}
                    className={cn("h-10 rounded-lg border text-sm font-medium", paymentMode === "OFFLINE" ? "border-success bg-success/10 text-success" : "border-input hover:bg-accent/50")}
                  >
                    Record Offline Payment
                  </button>
                  <button
                    type="button"
                    onClick={() => setPaymentMode("LATER")}
                    className={cn("h-10 rounded-lg border text-sm font-medium", paymentMode === "LATER" ? "border-success bg-success/10 text-success" : "border-input hover:bg-accent/50")}
                  >
                    Pay Later
                  </button>
                </div>
                {paymentMode === "OFFLINE" && (
                  <div className="space-y-3 rounded-lg border border-border p-3">
                    <div className="grid grid-cols-2 gap-3">
                      <Field label="Amount (₹)">
                        <Input type="number" min="0" onWheel={blurOnWheel} className={NO_SPINNER_INPUT} value={payAmount} onChange={(e) => setPayAmount(e.target.value)} />
                      </Field>
                      <Field label="Payment Mode">
                        <Select value={payMethod} onValueChange={setPayMethod}>
                          <SelectTrigger>
                            <SelectValue />
                          </SelectTrigger>
                          <SelectContent>
                            <SelectItem value="Cash">Cash</SelectItem>
                            <SelectItem value="UPI">UPI</SelectItem>
                            <SelectItem value="Card">Card</SelectItem>
                            <SelectItem value="Bank Transfer">Bank Transfer</SelectItem>
                          </SelectContent>
                        </Select>
                      </Field>
                    </div>
                    <Field label="Reference (optional)">
                      <Input value={payReference} onChange={(e) => setPayReference(e.target.value)} />
                    </Field>
                    <div className="flex gap-2">
                      <button type="button" disabled={busy} onClick={() => void recordPayment(false)} className="h-9 rounded-lg border border-input px-3 text-sm font-medium hover:bg-accent disabled:opacity-50">
                        Record Payment
                      </button>
                      <button type="button" disabled={busy} onClick={() => void recordPayment(true)} className="h-9 rounded-lg bg-[#0B7A55] px-3 text-sm font-semibold text-white disabled:opacity-50">
                        Mark as Paid in Full
                      </button>
                    </div>
                  </div>
                )}
                {paymentMode === "LATER" && (
                  <button
                    type="button"
                    onClick={() => setStep("Success")}
                    className="flex h-10 items-center gap-2 rounded-lg bg-[#0B7A55] px-4 text-sm font-semibold text-white"
                  >
                    Continue — Collect Payment Later
                  </button>
                )}
              </>
            )}
          </div>
        )}

        {step === "Success" && (
          <div className="space-y-4 text-center">
            <div className="mx-auto flex h-14 w-14 items-center justify-center rounded-full bg-success/15">
              <Check className="h-7 w-7 text-success" aria-hidden />
            </div>
            <div>
              <p className="text-lg font-bold">Student Added Successfully</p>
              <p className="mt-1 text-sm text-muted-foreground">
                {selectedMember?.fullName} has been enrolled in <span className="font-medium text-foreground">{program?.name}</span>
                {selectedBatch ? ` — ${selectedBatch.name}` : ""}.
              </p>
            </div>
            <div className="flex flex-wrap justify-center gap-2 pt-2">
              {enrollmentId && (
                <Link href={`/coaching/enrollments/${enrollmentId}`} className="h-10 rounded-lg border border-input px-4 py-2 text-sm font-medium hover:bg-accent">
                  View Student
                </Link>
              )}
              {programId && (
                <Link href={`/coaching/programs/${programId}`} className="h-10 rounded-lg border border-input px-4 py-2 text-sm font-medium hover:bg-accent">
                  View Program
                </Link>
              )}
              <Link href="/coaching/students" className="h-10 rounded-lg bg-[#0B7A55] px-4 py-2 text-sm font-semibold text-white">
                Back to Students
              </Link>
            </div>
          </div>
        )}

        {error && <p className="mt-4 text-sm text-destructive">{error}</p>}

        {step !== "Success" && (
          <div className="mt-5 flex items-center justify-between border-t border-border pt-4">
            {stepIndex === 0 ? (
              <Link href="/coaching/students" className="h-10 rounded-lg border border-input px-4 py-2 text-sm font-medium hover:bg-accent">
                Cancel
              </Link>
            ) : (
              <button
                type="button"
                onClick={() => setStep(STEPS[stepIndex - 1]!)}
                disabled={busy || step === "Payment"}
                className="h-10 rounded-lg border border-input px-4 py-2 text-sm font-medium hover:bg-accent disabled:opacity-50"
              >
                Back
              </button>
            )}
            {step === "Student Details" && (
              <button type="button" disabled={busy || !step1Valid} onClick={() => void goNextFromStep1()} className="h-10 rounded-lg bg-[#0B7A55] px-4 py-2 text-sm font-semibold text-white disabled:opacity-50">
                {busy ? "Saving…" : "Next Step"}
              </button>
            )}
            {step === "Program & Enrollment" && (
              <button type="button" disabled={!step2Valid} onClick={() => setStep("Review & Confirm")} className="h-10 rounded-lg bg-[#0B7A55] px-4 py-2 text-sm font-semibold text-white disabled:opacity-50">
                Next Step
              </button>
            )}
            {step === "Review & Confirm" && (
              <button type="button" disabled={busy} onClick={() => void confirmEnrollment()} className="h-10 rounded-lg bg-[#0B7A55] px-4 py-2 text-sm font-semibold text-white disabled:opacity-50">
                {busy ? "Enrolling…" : "Continue to Payment"}
              </button>
            )}
          </div>
        )}
      </div>
    </div>
  );
}
