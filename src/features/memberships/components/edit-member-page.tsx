"use client";

import { useEffect, useMemo, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useQueryClient } from "@tanstack/react-query";
import { ArrowLeft, CalendarDays, Check, ChevronRight, Info } from "lucide-react";
import { addDays, format, parseISO } from "date-fns";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Skeleton } from "@/components/ui/skeleton";
import { SelectField } from "@/components/shared/select-field";
import { DatePicker } from "@/components/shared/date-picker";
import { PlanSlotsList } from "@/features/memberships/components/plan-slots-list";
import { fieldErrors, type WizardDraft } from "@/features/memberships/add-member-wizard";
import { useMembershipDetailFor } from "@/features/memberships/hooks/use-member-schedule";
import type { PlanSlot } from "@/features/memberships/plan-slots";
import type { MembershipDetail, MembershipType } from "@/features/memberships/types";
import { getMembershipService } from "@/services/memberships";
import { ServiceError } from "@/services/shared/service-error";
import { cn } from "@/lib/utils";

const GENDERS = [
  { value: "", label: "Select" },
  { value: "male", label: "Male" },
  { value: "female", label: "Female" },
  { value: "other", label: "Other" },
];
const COUNTRY_CODES = ["+91", "+1", "+44", "+971"].map((c) => ({ value: c, label: c }));

/** The stored phone is bare digits for +91, "+code digits" otherwise — the reverse of how it was saved. */
function splitPhone(stored: string): { code: string; number: string } {
  const m = stored.trim().match(/^(\+\d{1,3})\s+(.*)$/);
  return m ? { code: m[1]!, number: m[2]!.replace(/\D/g, "") } : { code: "+91", number: stored.replace(/\D/g, "") };
}
function composePhone(code: string, phone: string): string {
  const digits = phone.replace(/\D/g, "");
  return code === "+91" ? digits : `${code} ${digits}`;
}
function capDigits(value: string, max: number): string {
  return value.replace(/\D/g, "").slice(0, max);
}
function inr(v: number): string {
  return `₹${v.toLocaleString("en-IN")}`;
}

function Field({ label, required, error, children }: { label: string; required?: boolean; error?: string; children: React.ReactNode }) {
  return (
    <div className="space-y-1.5">
      <p className="text-xs font-medium text-foreground/80">
        {label} {required && <span className="text-destructive">*</span>}
      </p>
      {children}
      {error && <p className="text-xs text-destructive">{error}</p>}
    </div>
  );
}

function ReadOnly({ children }: { children: React.ReactNode }) {
  return (
    <div className="flex h-10 w-full items-center gap-2 rounded-lg border border-input bg-muted/40 px-3 text-sm text-muted-foreground">
      {children}
    </div>
  );
}

/**
 * Edit Member — the Membership dashboard's own edit page (the v1 counterpart of Add New Member).
 * Personal details and the start date are editable; the plan, and therefore the court and
 * timings, are fixed by the plan the member joined, so they are shown but can't be changed here.
 */
export function EditMemberPage({ membershipId }: { membershipId: string }) {
  const router = useRouter();
  const queryClient = useQueryClient();
  const detailQuery = useMembershipDetailFor(membershipId);
  const detail = detailQuery.data;

  const [seeded, setSeeded] = useState(false);
  const [fullName, setFullName] = useState("");
  const [countryCode, setCountryCode] = useState("+91");
  const [phone, setPhone] = useState("");
  const [email, setEmail] = useState("");
  const [dob, setDob] = useState("");
  const [gender, setGender] = useState("");
  const [address, setAddress] = useState("");
  const [notes, setNotes] = useState("");
  const [startDate, setStartDate] = useState("");
  const [touched, setTouched] = useState<Set<string>>(new Set());
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!detail || seeded) return;
    const p = splitPhone(detail.member.phone);
    setFullName(detail.member.fullName);
    setCountryCode(p.code);
    setPhone(p.number);
    setEmail(detail.member.email ?? "");
    setDob(detail.member.dateOfBirth ?? "");
    setGender(detail.member.gender ?? "");
    setAddress(detail.member.address ?? "");
    setNotes(detail.notes ?? "");
    setStartDate(detail.membership.startDate);
    setSeeded(true);
  }, [detail, seeded]);

  // Reuses the Add Member wizard's own personal-information rules.
  const errors = useMemo(
    () =>
      fieldErrors(1, {
        fullName,
        countryCode,
        phone,
        email,
        dateOfBirth: dob,
        gender,
        address,
        city: "",
        pincode: "",
        emergencyName: "",
        emergencyCountryCode: "+91",
        emergencyPhone: "",
        sendWelcome: false,
        planId: "",
        planName: "",
        startDate,
        durationDays: 0,
        membershipFeeInr: 0,
        registrationFeeInr: 0,
        gstPercent: 0,
        paymentTab: "link",
        paymentAmount: 0,
        paymentDate: "",
        paymentMethod: "Cash",
        paymentReference: "",
        receivedFrom: "",
        collectedBy: "",
        paymentNotes: "",
      } satisfies WizardDraft),
    [fullName, countryCode, phone, email, dob, gender, address, startDate],
  );
  const startError = !startDate ? "Start date is required." : undefined;
  const show = (f: string) => (touched.has(f) ? (f === "startDate" ? startError : errors[f]) : undefined);
  const invalid = (f: string) => (show(f) ? "border-destructive focus-visible:ring-destructive" : "");
  const touch = (f: string) => setTouched((t) => new Set(t).add(f));

  const slots: PlanSlot[] = useMemo(() => slotsOf(detail), [detail]);
  const endDate = useMemo(() => {
    const days = detail?.membership.durationDays;
    return startDate && days ? addDays(parseISO(startDate), days - 1) : null;
  }, [startDate, detail]);

  async function save() {
    if (!detail) return;
    const hasError = Object.values(errors).some(Boolean) || Boolean(startError);
    if (hasError) {
      setTouched(new Set(["fullName", "phone", "email", "dateOfBirth", "startDate"]));
      return;
    }
    setSaving(true);
    setError(null);
    try {
      await getMembershipService().updateMembershipFull(membershipId, {
        fullName: fullName.trim(),
        phone: composePhone(countryCode, phone),
        email: email.trim() || undefined,
        dateOfBirth: dob || undefined,
        gender: gender || undefined,
        address: address.trim() || undefined,
        name: detail.membership.name,
        membershipType: detail.membership.membershipType as MembershipType,
        maxFamilyMembers: detail.membership.maxFamilyMembers || 1,
        startDate,
        durationDays: detail.membership.durationDays ?? 0,
        // Re-sent as-is: leaving both batch fields empty would clear the member's court slot.
        batchId: detail.slot?.batchId,
        description: detail.membership.description ?? undefined,
        membershipFeeInr: detail.membership.membershipFeeInr,
        registrationFeeInr: detail.membership.registrationFeeInr,
        gstPercent: detail.membership.gstPercent,
        referralMemberId: detail.referralMemberId ?? undefined,
        discoverySource: detail.discoverySource ?? undefined,
        notes: notes.trim() || undefined,
      });
      for (const key of ["membership-list", "membership-summary", "membership-dashboard-rows", "membership-detail"]) {
        queryClient.invalidateQueries({ queryKey: [key] });
      }
      router.push("/memberships/v1");
    } catch (err) {
      setError(err instanceof ServiceError ? err.message : "Unable to save this member.");
      setSaving(false);
    }
  }

  if (detailQuery.isLoading || (detail && !seeded)) {
    return (
      <div className="space-y-5">
        <Skeleton className="h-20 w-full rounded-2xl" />
        <Skeleton className="h-96 w-full rounded-xl" />
      </div>
    );
  }
  if (!detail) {
    return <p className="text-sm text-muted-foreground">We couldn&apos;t load this member.</p>;
  }

  return (
    <div className="space-y-5">
      <div className="rounded-2xl bg-card px-6 py-4">
        <nav aria-label="Breadcrumb" className="flex items-center gap-1 text-xs text-muted-foreground">
          <Link href="/memberships/v1" className="hover:text-foreground">
            Membership
          </Link>
          <ChevronRight className="h-3.5 w-3.5" aria-hidden />
          <span className="font-medium text-foreground">Edit Member</span>
        </nav>
        <h1 className="mt-1 text-2xl font-bold text-black dark:text-foreground">Edit Member</h1>
        <p className="text-sm text-muted-foreground">Update {detail.member.fullName}&apos;s details.</p>
      </div>

      <Card className="space-y-5 rounded-xl p-5">
        <div>
          <h2 className="text-base font-bold text-black dark:text-foreground">Personal Information</h2>
          <p className="text-xs text-muted-foreground">Basic details</p>
        </div>
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
          <Field label="Full Name" required error={show("fullName")}>
            <Input value={fullName} onChange={(e) => setFullName(e.target.value)} onBlur={() => touch("fullName")} className={invalid("fullName")} />
          </Field>
          <Field label="Phone Number" required error={show("phone")}>
            <div className="flex gap-2">
              <SelectField
                wrapperClassName="w-[84px] shrink-0"
                ariaLabel="Country code"
                value={countryCode}
                onValueChange={setCountryCode}
                options={COUNTRY_CODES}
                className="h-10 w-full rounded-lg border border-input bg-card px-2.5 text-sm outline-none transition-colors hover:border-foreground/30"
              />
              <Input
                value={phone}
                onChange={(e) => setPhone(capDigits(e.target.value, countryCode === "+91" ? 10 : 14))}
                onBlur={() => touch("phone")}
                inputMode="tel"
                className={cn("flex-1", invalid("phone"))}
              />
            </div>
          </Field>
          <Field label="Email" error={show("email")}>
            <Input value={email} onChange={(e) => setEmail(e.target.value)} onBlur={() => touch("email")} type="email" className={invalid("email")} />
          </Field>
          <Field label="Date of Birth" error={show("dateOfBirth")}>
            <DatePicker
              value={dob}
              onChange={(iso) => {
                setDob(iso);
                touch("dateOfBirth");
              }}
              max={format(new Date(), "yyyy-MM-dd")}
              placeholder="Select date"
              triggerClassName={cn(
                "flex h-10 w-full items-center justify-between gap-2 rounded-lg border border-input bg-card px-3 text-left text-sm outline-none transition-colors hover:border-foreground/30",
                !dob && "text-muted-foreground/60",
                invalid("dateOfBirth"),
              )}
            />
          </Field>
          <Field label="Gender">
            <SelectField
              ariaLabel="Gender"
              value={gender}
              onValueChange={setGender}
              options={GENDERS}
              className="h-10 w-full rounded-lg border border-input bg-card px-3 text-sm outline-none transition-colors hover:border-foreground/30"
            />
          </Field>
          <Field label="Address">
            <Input value={address} onChange={(e) => setAddress(e.target.value)} placeholder="Optional" />
          </Field>
        </div>
        <Field label="Notes">
          <textarea
            value={notes}
            onChange={(e) => setNotes(e.target.value)}
            rows={2}
            className="flex w-full rounded-md border border-input bg-transparent px-3 py-2 text-sm shadow-sm outline-none transition-colors placeholder:text-muted-foreground/60 focus-visible:border-foreground/40"
          />
        </Field>
      </Card>

      <Card className="space-y-5 rounded-xl p-5">
        <div>
          <h2 className="text-base font-bold text-black dark:text-foreground">Membership Plan</h2>
          <p className="text-xs text-muted-foreground">The plan can&apos;t be changed here — its court and timings come with it.</p>
        </div>
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-3">
          <Field label="Plan">
            <ReadOnly>
              {detail.membership.name} · {inr(detail.membership.membershipFeeInr)}
            </ReadOnly>
          </Field>
          <Field label="Plan Start Date" required error={show("startDate")}>
            <DatePicker
              value={startDate}
              onChange={(iso) => {
                setStartDate(iso);
                touch("startDate");
              }}
              placeholder="Select date"
              triggerClassName="flex h-10 w-full items-center justify-between gap-2 rounded-lg border border-input bg-card px-3 text-left text-sm outline-none transition-colors hover:border-foreground/30"
            />
          </Field>
          <Field label="Plan End Date">
            <ReadOnly>
              <CalendarDays className="h-4 w-4 shrink-0" aria-hidden />
              {endDate ? format(endDate, "dd MMM yyyy") : "—"}
            </ReadOnly>
          </Field>
        </div>

        <div className="space-y-2 rounded-xl border border-border p-4">
          <p className="text-sm font-semibold text-foreground">Court &amp; Timing</p>
          <PlanSlotsList slots={slots} className="grid grid-cols-1 gap-3 space-y-0 md:grid-cols-2" />
        </div>

        <div className="flex items-start gap-2.5 rounded-lg bg-blue-500/10 p-3">
          <Info className="mt-0.5 h-4 w-4 shrink-0 text-blue-600 dark:text-blue-400" aria-hidden />
          <p className="text-xs leading-relaxed text-foreground/80">Fees and payments aren&apos;t edited here.</p>
        </div>
      </Card>

      {error && <p className="text-sm text-destructive">{error}</p>}

      <div className="flex items-center justify-between gap-3">
        <button
          type="button"
          onClick={() => router.push("/memberships/v1")}
          className="flex h-10 items-center gap-2 rounded-lg border border-input bg-card px-4 text-sm font-medium transition-colors hover:bg-accent"
        >
          <ArrowLeft className="h-4 w-4" aria-hidden />
          Cancel
        </button>
        <button
          type="button"
          disabled={saving}
          onClick={save}
          className="flex h-10 items-center gap-2 rounded-lg bg-[#0B7A55] px-5 text-sm font-semibold text-white transition-opacity hover:opacity-90 disabled:opacity-60 dark:bg-primary dark:text-primary-foreground"
        >
          <Check className="h-4 w-4" aria-hidden />
          {saving ? "Saving…" : "Save Changes"}
        </button>
      </div>
    </div>
  );
}

/** The member's current slot as a one-item list for display. */
function slotsOf(detail: MembershipDetail | undefined): PlanSlot[] {
  const s = detail?.slot;
  if (!s) return [];
  return [
    {
      batchId: s.batchId,
      courtId: s.courtId,
      courtName: s.courtName ?? "Court",
      daysOfWeek: [...s.daysOfWeek].sort((a, b) => a - b),
      startTime: s.startTime.slice(0, 5),
      endTime: s.endTime.slice(0, 5),
    },
  ];
}
