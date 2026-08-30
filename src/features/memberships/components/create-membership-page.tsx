"use client";

import { useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { useQueryClient } from "@tanstack/react-query";
import { ArrowLeft, Check } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Card } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { getFacilityService } from "@/services/facility";
import { getMembershipService } from "@/services/memberships";
import { ServiceError } from "@/services/shared/service-error";
import type { Member } from "@/features/members/types";
import type { MembershipPaymentMode, MembershipType } from "@/features/memberships/types";

const DURATIONS = [
  { label: "1 Month", days: 30 },
  { label: "3 Months", days: 90 },
  { label: "6 Months", days: 180 },
  { label: "1 Year", days: 365 },
];
const GENDERS = ["Male", "Female", "Other", "Prefer not to say"];
const PAYMENT_METHODS = ["Cash", "UPI", "Card", "Bank Transfer", "Other"];
const DISCOVERY = ["Walk-in", "Referral", "Social Media", "Google Search", "Advertisement", "Friend / Family", "Other"];
const TYPES: { value: MembershipType; label: string }[] = [
  { value: "INDIVIDUAL", label: "Individual" },
  { value: "FAMILY", label: "Family" },
  { value: "CORPORATE", label: "Corporate" },
];
const MODES: { value: MembershipPaymentMode; label: string; hint: string }[] = [
  { value: "PAID", label: "Paid", hint: "Collect payment now" },
  { value: "PENDING", label: "Pending", hint: "Collect payment later" },
  { value: "FREE", label: "Free", hint: "No payment required" },
];

function todayIso(): string {
  return new Date().toISOString().slice(0, 10);
}
function inr(v: number): string {
  return `₹${v.toLocaleString("en-IN", { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
}
function num(s: string): number {
  const n = Number(s);
  return Number.isFinite(n) && n > 0 ? n : 0;
}

function SectionHeader({ n, title }: { n: number; title: string }) {
  return (
    <div className="mb-4 flex items-center gap-2">
      <span className="flex h-6 w-6 items-center justify-center rounded-full border border-primary text-xs font-semibold text-primary">
        {n}
      </span>
      <h2 className="text-sm font-semibold">{title}</h2>
    </div>
  );
}

function Field({ label, required, hint, children }: { label: string; required?: boolean; hint?: string; children: React.ReactNode }) {
  return (
    <div className="space-y-1.5">
      <label className="text-xs font-medium text-muted-foreground">
        {label} {required && <span className="text-destructive">*</span>}
      </label>
      {children}
      {hint && <p className="text-[11px] text-muted-foreground">{hint}</p>}
    </div>
  );
}

const selectCls = "h-10 w-full rounded-md border border-input bg-secondary/60 px-3 text-sm";

export function CreateMembershipPage() {
  const router = useRouter();
  const queryClient = useQueryClient();
  const [facilityId, setFacilityId] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  // Member
  const [fullName, setFullName] = useState("");
  const [phone, setPhone] = useState("");
  const [email, setEmail] = useState("");
  const [dob, setDob] = useState("");
  const [gender, setGender] = useState("");
  const [address, setAddress] = useState("");

  // Membership
  const [name, setName] = useState("");
  const [type, setType] = useState<MembershipType>("INDIVIDUAL");
  const [startDate, setStartDate] = useState(todayIso());
  const [durationDays, setDurationDays] = useState(0);
  const [maxFamily, setMaxFamily] = useState(1);
  const [description, setDescription] = useState("");
  const [slotStart, setSlotStart] = useState("");
  const [slotEnd, setSlotEnd] = useState("");

  // Charges
  const [fee, setFee] = useState("");
  const [regFee, setRegFee] = useState("");
  const [gst, setGst] = useState("");

  // Payment
  const [mode, setMode] = useState<MembershipPaymentMode>("PAID");
  const [methods, setMethods] = useState<string[]>(["Cash", "UPI"]);
  const [paymentRef, setPaymentRef] = useState("");
  const [recurring, setRecurring] = useState(false);

  // Extras
  const [referralQuery, setReferralQuery] = useState("");
  const [referralResults, setReferralResults] = useState<Pick<Member, "id" | "fullName" | "phone">[]>([]);
  const [referral, setReferral] = useState<Pick<Member, "id" | "fullName"> | null>(null);
  const [discovery, setDiscovery] = useState("");
  const [notes, setNotes] = useState("");

  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [mandateUrl, setMandateUrl] = useState<string | null>(null);

  useEffect(() => {
    getFacilityService()
      .getFacility()
      .then((f) => {
        setFacilityId(f?.id ?? null);
        setLoading(false);
      })
      .catch(() => setLoading(false));
  }, []);

  useEffect(() => {
    const q = referralQuery.trim();
    if (q.length < 2 || !facilityId) {
      setReferralResults([]);
      return;
    }
    let cancelled = false;
    const t = setTimeout(() => {
      getMembershipService()
        .searchMembers(facilityId, q)
        .then((r) => !cancelled && setReferralResults(r))
        .catch(() => undefined);
    }, 300);
    return () => {
      cancelled = true;
      clearTimeout(t);
    };
  }, [referralQuery, facilityId]);

  const charges = useMemo(() => {
    const subTotal = num(fee);
    const gstAmount = Math.round((subTotal * num(gst)) / 100);
    const registration = num(regFee);
    return { subTotal, gstAmount, registration, total: subTotal + gstAmount + registration };
  }, [fee, gst, regFee]);

  async function submit() {
    if (!facilityId) return;
    if (!fullName.trim() || !phone.trim()) return setError("Full name and phone number are required.");
    if (!durationDays) return setError("Select a membership duration.");
    if (mode !== "FREE" && charges.subTotal <= 0) return setError("Enter a membership fee.");
    if (slotStart && slotEnd && slotEnd <= slotStart) return setError("Time slot end must be after the start.");

    setSaving(true);
    setError(null);
    try {
      const membership = await getMembershipService().createMembershipFull({
        facilityId,
        fullName: fullName.trim(),
        phone: phone.trim(),
        email: email.trim() || undefined,
        dateOfBirth: dob || undefined,
        gender: gender || undefined,
        address: address.trim() || undefined,
        name: name.trim() || undefined,
        membershipType: type,
        maxFamilyMembers: type === "FAMILY" ? maxFamily : 1,
        startDate,
        durationDays,
        timeSlotStart: slotStart || undefined,
        timeSlotEnd: slotEnd || undefined,
        description: description.trim() || undefined,
        membershipFeeInr: charges.subTotal,
        registrationFeeInr: charges.registration,
        gstPercent: num(gst),
        paymentMode: mode,
        paymentMethods: methods,
        paymentReference: paymentRef.trim() || undefined,
        recurring,
        referralMemberId: referral?.id,
        discoverySource: discovery || undefined,
        notes: notes.trim() || undefined,
      });

      queryClient.invalidateQueries({ queryKey: ["membership-list"] });
      queryClient.invalidateQueries({ queryKey: ["membership-summary"] });
      queryClient.invalidateQueries({ queryKey: ["membership-revenue"] });

      if (recurring && mode !== "FREE" && charges.total > 0) {
        const sub = await getMembershipService().createMembershipSubscription(membership.id);
        setMandateUrl(sub.shortUrl ?? "");
        setSaving(false);
        return;
      }
      router.push("/memberships");
    } catch (err) {
      setError(err instanceof ServiceError ? err.message : "Unable to create this membership.");
      setSaving(false);
    }
  }

  if (loading) return <Skeleton className="h-[600px] w-full rounded-xl" />;
  if (!facilityId) return <p className="text-sm text-muted-foreground">Complete your facility setup first.</p>;

  if (mandateUrl !== null) {
    return (
      <div className="mx-auto max-w-lg space-y-4 text-center">
        <Check className="mx-auto h-10 w-10 text-success" />
        <h1 className="text-lg font-semibold">Membership created</h1>
        {mandateUrl ? (
          <>
            <p className="text-sm text-muted-foreground">Send this UPI AutoPay link to the member:</p>
            <div className="flex items-center gap-2">
              <Input readOnly value={mandateUrl} className="text-xs" />
              <Button type="button" variant="outline" size="sm" onClick={() => navigator.clipboard.writeText(mandateUrl)}>
                Copy
              </Button>
            </div>
          </>
        ) : (
          <p className="text-sm text-muted-foreground">Recurring link could not be generated — you can retry from the list.</p>
        )}
        <Button type="button" onClick={() => router.push("/memberships")}>
          Back to Memberships
        </Button>
      </div>
    );
  }

  return (
    <div className="w-full space-y-6">
      <div className="flex items-center gap-3">
        <Button type="button" variant="ghost" size="sm" onClick={() => router.push("/memberships")}>
          <ArrowLeft className="h-4 w-4" />
        </Button>
        <div>
          <h1 className="text-xl font-semibold">Create Membership</h1>
          <p className="text-sm text-muted-foreground">Register a new member</p>
        </div>
      </div>

      {/* 1 — Member Information */}
      <Card className="p-5">
        <SectionHeader n={1} title="Member Information" />
        <div className="grid gap-4 sm:grid-cols-3">
          <Field label="Full Name" required>
            <Input value={fullName} onChange={(e) => setFullName(e.target.value)} placeholder="Enter full name" />
          </Field>
          <Field label="Phone Number" required>
            <div className="flex gap-2">
              <span className="flex h-10 items-center rounded-md border border-input bg-secondary/60 px-2 text-sm text-muted-foreground">
                +91
              </span>
              <Input value={phone} onChange={(e) => setPhone(e.target.value)} placeholder="Enter phone number" inputMode="tel" />
            </div>
          </Field>
          <Field label="Email Address">
            <Input value={email} onChange={(e) => setEmail(e.target.value)} placeholder="Enter email address" type="email" />
          </Field>
          <Field label="Date of Birth">
            <input type="date" value={dob} onChange={(e) => setDob(e.target.value)} className={selectCls} />
          </Field>
          <Field label="Gender">
            <select value={gender} onChange={(e) => setGender(e.target.value)} className={selectCls}>
              <option value="">Select gender</option>
              {GENDERS.map((g) => (
                <option key={g} value={g}>
                  {g}
                </option>
              ))}
            </select>
          </Field>
          <Field label="Address">
            <Input value={address} onChange={(e) => setAddress(e.target.value)} placeholder="Enter complete address" />
          </Field>
        </div>
      </Card>

      {/* 2 — Membership Details */}
      <Card className="p-5">
        <SectionHeader n={2} title="Membership Details" />
        <div className="grid gap-4 sm:grid-cols-2">
          <Field label="Membership Name" required hint="e.g., Premium Membership">
            <Input value={name} onChange={(e) => setName(e.target.value)} placeholder="Enter membership name" />
          </Field>
          <Field label="Membership Type" required>
            <div className="flex flex-wrap gap-4 pt-2">
              {TYPES.map((t) => (
                <label key={t.value} className="flex items-center gap-1.5 text-sm">
                  <input type="radio" checked={type === t.value} onChange={() => setType(t.value)} />
                  {t.label}
                </label>
              ))}
            </div>
          </Field>
          <Field label="Start Date" required>
            <input type="date" value={startDate} onChange={(e) => setStartDate(e.target.value)} className={selectCls} />
          </Field>
          <Field label="Duration" required hint="e.g., 3 Months, 6 Months, 1 Year">
            <select value={durationDays} onChange={(e) => setDurationDays(Number(e.target.value))} className={selectCls}>
              <option value={0}>Select duration</option>
              {DURATIONS.map((d) => (
                <option key={d.days} value={d.days}>
                  {d.label}
                </option>
              ))}
            </select>
          </Field>
          <Field label="Time Slot" hint="The hour the member plays each visit">
            <div className="flex items-center gap-2">
              <input type="time" value={slotStart} onChange={(e) => setSlotStart(e.target.value)} className={selectCls} />
              <span className="text-sm text-muted-foreground">to</span>
              <input type="time" value={slotEnd} onChange={(e) => setSlotEnd(e.target.value)} className={selectCls} />
            </div>
          </Field>
          <Field label="Max. Members (Family)" hint="Applicable only for Family membership">
            <div className="flex items-center gap-2">
              <Button type="button" variant="outline" size="sm" disabled={type !== "FAMILY"} onClick={() => setMaxFamily((v) => Math.max(1, v - 1))}>
                −
              </Button>
              <span className="w-10 text-center text-sm">{type === "FAMILY" ? maxFamily : 1}</span>
              <Button type="button" variant="outline" size="sm" disabled={type !== "FAMILY"} onClick={() => setMaxFamily((v) => v + 1)}>
                +
              </Button>
            </div>
          </Field>
          <div className="sm:col-span-2">
            <Field label="Description">
              <textarea
                value={description}
                onChange={(e) => setDescription(e.target.value.slice(0, 300))}
                placeholder="Enter membership description and benefits…"
                rows={3}
                className="w-full rounded-md border border-input bg-secondary/60 p-3 text-sm"
              />
              <p className="text-right text-[11px] text-muted-foreground">{description.length}/300</p>
            </Field>
          </div>
        </div>
      </Card>

      {/* 3 — Membership Charges */}
      <Card className="p-5">
        <SectionHeader n={3} title="Membership Charges" />
        <div className="grid gap-4 sm:grid-cols-3">
          <Field label="Membership Fee" required>
            <Input value={fee} onChange={(e) => setFee(e.target.value)} placeholder="Enter amount" type="number" min={0} />
          </Field>
          <Field label="Registration Fee" hint="One-time, (if applicable)">
            <Input value={regFee} onChange={(e) => setRegFee(e.target.value)} placeholder="Enter amount" type="number" min={0} />
          </Field>
          <Field label="GST (%)" hint="Applicable tax percentage">
            <Input value={gst} onChange={(e) => setGst(e.target.value)} placeholder="Enter GST percentage" type="number" min={0} />
          </Field>
        </div>
        <div className="mt-4 flex flex-wrap items-center gap-x-4 gap-y-2 rounded-md bg-secondary/50 p-3 text-sm">
          <span>
            <span className="text-muted-foreground">Sub Total</span> {inr(charges.subTotal)}
          </span>
          <span className="text-muted-foreground">+</span>
          <span>
            <span className="text-muted-foreground">GST Amount</span> {inr(charges.gstAmount)}
          </span>
          <span className="text-muted-foreground">+</span>
          <span>
            <span className="text-muted-foreground">Registration Fee</span> {inr(charges.registration)}
          </span>
          <span className="text-muted-foreground">=</span>
          <span className="font-semibold text-success">Total {inr(charges.total)}</span>
        </div>
      </Card>

      {/* 4 — Payment Mode */}
      <Card className="p-5">
        <SectionHeader n={4} title="Payment Mode" />
        <div className="flex flex-wrap gap-6">
          {MODES.map((m) => (
            <label key={m.value} className="flex items-start gap-2 text-sm">
              <input type="radio" checked={mode === m.value} onChange={() => setMode(m.value)} className="mt-0.5" />
              <span>
                {m.label}
                <span className="block text-xs text-muted-foreground">{m.hint}</span>
              </span>
            </label>
          ))}
        </div>
        {mode !== "FREE" && (
          <div className="mt-4 grid gap-4 sm:grid-cols-2">
            <div className="space-y-1.5">
              <p className="text-xs font-medium text-muted-foreground">Accepted Payment Methods</p>
              <div className="flex flex-wrap gap-3">
                {PAYMENT_METHODS.map((pm) => (
                  <label key={pm} className="flex items-center gap-1.5 text-sm">
                    <input
                      type="checkbox"
                      checked={methods.includes(pm)}
                      onChange={(e) =>
                        setMethods((prev) => (e.target.checked ? [...prev, pm] : prev.filter((x) => x !== pm)))
                      }
                    />
                    {pm}
                  </label>
                ))}
              </div>
            </div>
            <Field label="Payment Reference (Optional)">
              <Input value={paymentRef} onChange={(e) => setPaymentRef(e.target.value)} placeholder="Enter transaction / reference number" />
            </Field>
            <label className="flex items-start gap-2 text-sm sm:col-span-2">
              <input type="checkbox" checked={recurring} onChange={(e) => setRecurring(e.target.checked)} className="mt-0.5" />
              <span>
                Recurring UPI AutoPay
                <span className="block text-xs text-muted-foreground">
                  Generates a Razorpay mandate link — the total is then charged automatically each cycle.
                </span>
              </span>
            </label>
          </div>
        )}
      </Card>

      {/* 5 — Additional Information */}
      <Card className="p-5">
        <SectionHeader n={5} title="Additional Information" />
        <div className="grid gap-4 sm:grid-cols-3">
          <Field label="Referral By">
            {referral ? (
              <div className="flex h-10 items-center justify-between rounded-md border border-input bg-secondary/40 px-3 text-sm">
                {referral.fullName}
                <button type="button" className="text-xs text-primary" onClick={() => setReferral(null)}>
                  Change
                </button>
              </div>
            ) : (
              <div className="space-y-1">
                <Input value={referralQuery} onChange={(e) => setReferralQuery(e.target.value)} placeholder="Select member (optional)" />
                {referralResults.length > 0 && (
                  <div className="max-h-32 space-y-1 overflow-y-auto rounded-md border border-input p-1">
                    {referralResults.map((r) => (
                      <button
                        key={r.id}
                        type="button"
                        onClick={() => {
                          setReferral(r);
                          setReferralQuery("");
                          setReferralResults([]);
                        }}
                        className="flex w-full justify-between rounded px-2 py-1 text-left text-sm hover:bg-accent"
                      >
                        <span>{r.fullName}</span>
                        <span className="text-xs text-muted-foreground">{r.phone}</span>
                      </button>
                    ))}
                  </div>
                )}
              </div>
            )}
          </Field>
          <Field label="How did you find us?">
            <select value={discovery} onChange={(e) => setDiscovery(e.target.value)} className={selectCls}>
              <option value="">Select an option</option>
              {DISCOVERY.map((d) => (
                <option key={d} value={d}>
                  {d}
                </option>
              ))}
            </select>
          </Field>
          <Field label="Notes">
            <textarea
              value={notes}
              onChange={(e) => setNotes(e.target.value.slice(0, 200))}
              placeholder="Add any notes or special requests…"
              rows={2}
              className="w-full rounded-md border border-input bg-secondary/60 p-3 text-sm"
            />
          </Field>
        </div>
      </Card>

      {error && <p className="text-sm text-destructive">{error}</p>}

      <div className="flex flex-wrap items-center justify-between gap-3">
        <Button type="button" variant="outline" onClick={() => router.push("/memberships")}>
          Cancel
        </Button>
        <Button type="button" onClick={submit} disabled={saving}>
          {saving ? "Creating…" : "Create Membership"}
        </Button>
      </div>
      <p className="text-center text-xs text-muted-foreground">Secure registration · You can edit details later</p>
    </div>
  );
}