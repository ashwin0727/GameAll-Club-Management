"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { ChevronRight, Copy, Check } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Textarea } from "@/components/ui/textarea";
import { cn } from "@/lib/utils";
import { ServiceError } from "@/services/shared/service-error";
import { getStaffService } from "@/services/staff";
import { usePermissionContext } from "@/features/auth/context/permission-provider";
import { PermissionDenied } from "@/features/staff/components/permission-denied";
import type { CreateStaffResult, RoleRow } from "@/features/staff/types";

const STEPS = ["Basic Information", "Access & Role", "Review & Invite"] as const;

export function AddStaffPage() {
  const perms = usePermissionContext();
  const router = useRouter();
  const facilityId = perms?.facilityId ?? null;

  const [step, setStep] = useState(0);
  const [roles, setRoles] = useState<RoleRow[]>([]);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [result, setResult] = useState<CreateStaffResult | null>(null);
  const [copied, setCopied] = useState(false);

  const [fullName, setFullName] = useState("");
  const [email, setEmail] = useState("");
  const [phone, setPhone] = useState("");
  const [notes, setNotes] = useState("");
  const [roleId, setRoleId] = useState("");
  const [isPrimary, setIsPrimary] = useState(true);

  useEffect(() => {
    if (!facilityId) return;
    getStaffService()
      .listRoles(facilityId)
      .then((r) => {
        const assignable = r.filter((x) => x.isActive && x.key !== "owner");
        setRoles(assignable);
        setRoleId((cur) => cur || assignable.find((x) => x.key === "staff")?.id || assignable[0]?.id || "");
      })
      .catch(() => setRoles([]));
  }, [facilityId]);

  if (!perms?.can("USERS_CREATE")) {
    return <PermissionDenied message="You don't have permission to add staff." />;
  }

  const selectedRole = roles.find((r) => r.id === roleId);
  const emailValid = /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email.trim());

  function next() {
    setError(null);
    if (step === 0) {
      if (!fullName.trim()) return setError("Enter the staff member's full name.");
      if (!emailValid) return setError("Enter a valid email address.");
    }
    if (step === 1 && !roleId) return setError("Choose a role.");
    setStep((s) => Math.min(s + 1, STEPS.length - 1));
  }

  async function submit() {
    if (!facilityId || busy) return;
    setBusy(true);
    setError(null);
    try {
      const res = await getStaffService().createStaff({
        facilityId,
        fullName: fullName.trim(),
        email: email.trim(),
        phone: phone.trim() || null,
        roleId,
        isPrimary,
        notes: notes.trim() || null,
      });
      setResult(res);
    } catch (e) {
      setError(e instanceof ServiceError ? e.message : "Could not add the staff member.");
    } finally {
      setBusy(false);
    }
  }

  if (result) {
    return (
      <div className="mx-auto max-w-lg space-y-4">
        <Card className="p-6 text-center">
          <span className="mx-auto flex h-12 w-12 items-center justify-center rounded-full bg-success/15">
            <Check className="h-6 w-6 text-success" aria-hidden />
          </span>
          <h1 className="mt-3 text-lg font-semibold">
            {result.linked ? `${fullName} was added` : `${fullName} was invited`}
          </h1>
          <p className="mt-1 text-sm text-muted-foreground">
            {result.linked
              ? "They already had a GameAll account — access to this facility is active now."
              : "Share the one-time password below. They'll set their own on first sign-in."}
          </p>

          {result.temporaryPassword && (
            <div className="mt-4 flex items-center justify-between gap-2 rounded-md border border-border bg-muted/40 p-3">
              <code className="text-sm font-medium">{result.temporaryPassword}</code>
              <Button
                type="button"
                size="sm"
                variant="outline"
                onClick={() => {
                  navigator.clipboard.writeText(result.temporaryPassword ?? "");
                  setCopied(true);
                }}
              >
                {copied ? <Check className="h-3.5 w-3.5" /> : <Copy className="h-3.5 w-3.5" />}
                {copied ? "Copied" : "Copy"}
              </Button>
            </div>
          )}
          {result.temporaryPassword && (
            <p className="mt-2 text-xs text-muted-foreground">
              This password is shown once and is not stored. If you lose it, use “Reset password” on the staff member.
            </p>
          )}

          <div className="mt-5 flex justify-center gap-2">
            <Button asChild variant="outline">
              <Link href="/users-roles/staff">Back to staff</Link>
            </Button>
            <Button asChild>
              <Link href={`/users-roles/staff/${result.userId}`}>View {fullName}</Link>
            </Button>
          </div>
        </Card>
      </div>
    );
  }

  return (
    <div className="mx-auto max-w-2xl space-y-4">
      <nav aria-label="Breadcrumb" className="flex items-center gap-1 text-xs text-muted-foreground">
        <Link href="/users-roles/staff" className="hover:text-foreground">
          Users &amp; Roles
        </Link>
        <ChevronRight className="h-3 w-3" aria-hidden />
        <span className="text-foreground">Add Staff</span>
      </nav>

      <div>
        <h1 className="text-xl font-semibold">Add Staff</h1>
        <p className="text-sm text-muted-foreground">Invite a new staff member to your facility.</p>
      </div>

      <ol className="flex items-center gap-2 text-xs">
        {STEPS.map((s, i) => (
          <li key={s} className="flex items-center gap-2">
            <span
              className={cn(
                "flex h-6 w-6 items-center justify-center rounded-full border text-[11px] font-semibold",
                i === step
                  ? "border-primary bg-primary text-primary-foreground"
                  : i < step
                    ? "border-primary bg-primary/10 text-primary"
                    : "border-border text-muted-foreground",
              )}
            >
              {i + 1}
            </span>
            <span className={cn(i === step ? "font-medium text-foreground" : "text-muted-foreground")}>{s}</span>
            {i < STEPS.length - 1 && <ChevronRight className="h-3 w-3 text-muted-foreground" aria-hidden />}
          </li>
        ))}
      </ol>

      <Card className="space-y-4 p-5">
        {step === 0 && (
          <>
            <h2 className="text-sm font-semibold">Basic Information</h2>
            <div className="grid gap-3 sm:grid-cols-2">
              <Field id="s-name" label="Full name" required>
                <Input id="s-name" value={fullName} onChange={(e) => setFullName(e.target.value)} placeholder="Enter full name" />
              </Field>
              <Field id="s-email" label="Email address" required>
                <Input id="s-email" type="email" value={email} onChange={(e) => setEmail(e.target.value)} placeholder="staff@example.com" />
              </Field>
              <Field id="s-phone" label="Phone number">
                <Input id="s-phone" value={phone} onChange={(e) => setPhone(e.target.value)} placeholder="+91 98765 43210" />
              </Field>
            </div>
            <Field id="s-notes" label="Notes (optional)">
              <Textarea id="s-notes" rows={3} value={notes} onChange={(e) => setNotes(e.target.value)} maxLength={500} placeholder="Any notes about this staff member…" />
            </Field>
          </>
        )}

        {step === 1 && (
          <>
            <h2 className="text-sm font-semibold">Access &amp; Role</h2>
            <Field id="s-role" label="Role" required>
              <Select value={roleId} onValueChange={setRoleId}>
                <SelectTrigger id="s-role">
                  <SelectValue placeholder="Choose a role" />
                </SelectTrigger>
                <SelectContent>
                  {roles.map((r) => (
                    <SelectItem key={r.id} value={r.id}>
                      {r.name}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </Field>
            {selectedRole?.description && (
              <p className="text-xs text-muted-foreground">{selectedRole.description}</p>
            )}
            <label className="flex items-center gap-2 text-sm">
              <input type="checkbox" checked={isPrimary} onChange={(e) => setIsPrimary(e.target.checked)} className="h-4 w-4" />
              Make {perms.facilityName} their primary facility
            </label>
            <p className="text-xs text-muted-foreground">
              Access is scoped to {perms.facilityName}. You can grant access to other facilities you manage from the staff
              member&apos;s details afterwards.
            </p>
          </>
        )}

        {step === 2 && (
          <>
            <h2 className="text-sm font-semibold">Review &amp; Invite</h2>
            <dl className="grid grid-cols-2 gap-x-4 gap-y-3 text-sm">
              <Review label="Full name" value={fullName} />
              <Review label="Email" value={email} />
              <Review label="Phone" value={phone || "—"} />
              <Review label="Role" value={selectedRole?.name ?? "—"} />
              <Review label="Facility" value={perms.facilityName} />
              <Review label="Primary facility" value={isPrimary ? "Yes" : "No"} />
            </dl>
            <p className="text-xs text-muted-foreground">
              An account will be created with a one-time password you&apos;ll share with them. They must set their own
              password on first sign-in.
            </p>
          </>
        )}

        {error && (
          <p role="alert" className="text-sm text-destructive">
            {error}
          </p>
        )}

        <div className="flex items-center justify-between pt-2">
          <Button
            type="button"
            variant="outline"
            onClick={() => (step === 0 ? router.push("/users-roles/staff") : setStep((s) => s - 1))}
            disabled={busy}
          >
            {step === 0 ? "Cancel" : "Back"}
          </Button>
          {step < STEPS.length - 1 ? (
            <Button type="button" onClick={next}>
              Next <ChevronRight className="h-4 w-4" aria-hidden />
            </Button>
          ) : (
            <Button type="button" onClick={submit} disabled={busy}>
              {busy ? "Adding…" : "Add staff member"}
            </Button>
          )}
        </div>
      </Card>
    </div>
  );
}

function Field({ id, label, required, children }: { id: string; label: string; required?: boolean; children: React.ReactNode }) {
  return (
    <div className="space-y-1.5">
      <Label htmlFor={id} className="text-xs font-medium">
        {label} {required && <span className="text-destructive">*</span>}
      </Label>
      {children}
    </div>
  );
}

function Review({ label, value }: { label: string; value: string }) {
  return (
    <div>
      <dt className="text-xs text-muted-foreground">{label}</dt>
      <dd className="mt-0.5 font-medium">{value}</dd>
    </div>
  );
}
