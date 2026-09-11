"use client";

import { useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Textarea } from "@/components/ui/textarea";
import { cn } from "@/lib/utils";
import { ServiceError } from "@/services/shared/service-error";
import { getCoachingService } from "@/services/coaching";
import { usePermissionContext } from "@/features/auth/context/permission-provider";
import { PermissionDenied } from "@/features/staff/components/permission-denied";
import { PageHeader, money, rupeesToMinor } from "@/features/coaching/components/shared";

const STEPS = ["Program Details", "Schedule & Duration", "Pricing", "Review & Create"] as const;
const LEVELS = ["Beginner", "Intermediate", "Advanced", "All Levels", "Custom"];
const AGE_GROUPS = ["All Ages", "Under 12", "Teens", "Adults", "Seniors"];
const CATEGORIES = ["General", "Group", "Private", "Kids", "Ladies", "Competitive"];

export function ProgramWizardPage() {
  const perms = usePermissionContext();
  const router = useRouter();
  const facilityId = perms?.facilityId ?? null;
  const canPrice = perms?.can("COACHING_MANAGE_PRICING") ?? false;

  const [step, setStep] = useState(0);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const [name, setName] = useState("");
  const [level, setLevel] = useState("Beginner");
  const [ageGroup, setAgeGroup] = useState("All Ages");
  const [category, setCategory] = useState("General");
  const [description, setDescription] = useState("");
  const [duration, setDuration] = useState("60");
  const [capacity, setCapacity] = useState("10");
  const [sessionCount, setSessionCount] = useState("");
  const [pricingMode, setPricingMode] = useState<"PAID" | "INCLUDED" | "PER_ENROLLMENT">("PAID");
  const [price, setPrice] = useState("");

  if (!perms?.can("COACHING_MANAGE_PROGRAMS")) {
    return <PermissionDenied message="You don't have permission to manage programs." />;
  }

  function next() {
    setError(null);
    if (step === 0 && !name.trim()) return setError("Enter a program name.");
    if (step === 1) {
      if (Number(duration) < 15 || Number(duration) > 480) return setError("Duration must be between 15 and 480 minutes.");
      if (Number(capacity) < 1) return setError("Capacity must be at least 1.");
    }
    if (step === 2 && pricingMode === "PAID" && !price.trim()) return setError("Enter a price, or choose another pricing option.");
    setStep((s) => Math.min(s + 1, STEPS.length - 1));
  }

  async function submit() {
    if (!facilityId) return;
    setBusy(true);
    setError(null);
    try {
      const id = await getCoachingService().createProgram({
        facilityId,
        name: name.trim(),
        level,
        ageGroup,
        category,
        description: description.trim() || null,
        defaultDurationMinutes: Number(duration) || 60,
        defaultCapacity: Number(capacity) || 1,
        sessionCount: sessionCount.trim() ? Number(sessionCount) : null,
        defaultPriceMinor: pricingMode === "PAID" ? rupeesToMinor(price) : pricingMode === "INCLUDED" ? 0 : null,
        isMembershipIncluded: pricingMode === "INCLUDED",
      });
      router.push(`/coaching/programs/${id}`);
    } catch (e) {
      setError(e instanceof ServiceError ? e.message : "Could not create the program.");
      setBusy(false);
    }
  }

  return (
    <div className="mx-auto max-w-2xl space-y-4">
      <PageHeader title="Create Program" subtitle="Enter the basic information about the coaching program." />

      <ol className="flex flex-wrap gap-2 text-xs">
        {STEPS.map((s, i) => (
          <li
            key={s}
            className={cn(
              "rounded-full border px-3 py-1 font-medium",
              i === step ? "border-primary bg-primary/10 text-primary" : "border-border text-muted-foreground",
            )}
          >
            {i + 1}. {s}
          </li>
        ))}
      </ol>

      <Card className="space-y-4 p-5">
        {step === 0 && (
          <>
            <F label="Program Name">
              <Input value={name} onChange={(e) => setName(e.target.value)} placeholder="e.g. Beginner Group" />
            </F>
            <div className="grid grid-cols-2 gap-3">
              <F label="Level">
                <Picker value={level} onChange={setLevel} options={LEVELS} />
              </F>
              <F label="Age Group">
                <Picker value={ageGroup} onChange={setAgeGroup} options={AGE_GROUPS} />
              </F>
            </div>
            <F label="Category">
              <Picker value={category} onChange={setCategory} options={CATEGORIES} />
            </F>
            <F label="Description">
              <Textarea rows={3} value={description} onChange={(e) => setDescription(e.target.value)} maxLength={500} />
            </F>
          </>
        )}

        {step === 1 && (
          <>
            <div className="grid grid-cols-2 gap-3">
              <F label="Session duration (minutes)">
                <Input type="number" min="15" step="5" value={duration} onChange={(e) => setDuration(e.target.value)} />
              </F>
              <F label="Default capacity">
                <Input type="number" min="1" step="1" value={capacity} onChange={(e) => setCapacity(e.target.value)} />
              </F>
            </div>
            <F label="Sessions per package (optional)">
              <Input type="number" min="1" step="1" value={sessionCount} onChange={(e) => setSessionCount(e.target.value)} />
            </F>
            <p className="text-xs text-muted-foreground">
              A program only defines defaults — sessions are scheduled separately, one calendar instance at a time.
            </p>
          </>
        )}

        {step === 2 && (
          <>
            <F label="Pricing">
              <div className="space-y-2">
                {(["PAID", "INCLUDED", "PER_ENROLLMENT"] as const).map((m) => (
                  <label key={m} className="flex items-center gap-2 text-sm">
                    <input
                      type="radio"
                      name="pricing"
                      checked={pricingMode === m}
                      onChange={() => setPricingMode(m)}
                      disabled={m !== "PAID" && !canPrice}
                    />
                    {m === "PAID" && "Fixed program fee"}
                    {m === "INCLUDED" && "Included in membership (no charge)"}
                    {m === "PER_ENROLLMENT" && "Priced per enrollment"}
                  </label>
                ))}
              </div>
            </F>
            {pricingMode === "PAID" && (
              <F label="Program fee (₹)">
                <Input type="number" min="0" step="1" value={price} onChange={(e) => setPrice(e.target.value)} />
              </F>
            )}
            {!canPrice && (
              <p className="text-xs text-muted-foreground">
                You can set a fixed fee. Membership-included and per-enrollment pricing need the pricing permission.
              </p>
            )}
            <p className="text-xs text-muted-foreground">
              A fee is an obligation — it becomes revenue only when a payment is actually recorded.
            </p>
          </>
        )}

        {step === 3 && (
          <dl className="grid grid-cols-2 gap-x-4 gap-y-2 text-sm">
            <Review label="Name" value={name} />
            <Review label="Level" value={level} />
            <Review label="Age group" value={ageGroup} />
            <Review label="Category" value={category} />
            <Review label="Duration" value={`${duration} min`} />
            <Review label="Capacity" value={capacity} />
            <Review label="Sessions / package" value={sessionCount || "—"} />
            <Review
              label="Pricing"
              value={
                pricingMode === "INCLUDED"
                  ? "Membership-included"
                  : pricingMode === "PER_ENROLLMENT"
                    ? "Per enrollment"
                    : price
                      ? money(rupeesToMinor(price) ?? 0)
                      : "—"
              }
            />
            <Review label="Description" value={description || "—"} />
          </dl>
        )}

        {error && <p className="text-sm text-destructive">{error}</p>}

        <div className="flex items-center justify-between border-t border-border pt-4">
          {step === 0 ? (
            <Button asChild variant="outline">
              <Link href="/coaching/programs">Cancel</Link>
            </Button>
          ) : (
            <Button variant="outline" onClick={() => setStep((s) => s - 1)} disabled={busy}>
              Back
            </Button>
          )}
          {step < STEPS.length - 1 ? (
            <Button onClick={next}>Next</Button>
          ) : (
            <Button onClick={() => void submit()} disabled={busy}>
              {busy ? "Creating…" : "Create Program"}
            </Button>
          )}
        </div>
      </Card>
    </div>
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

function Picker({ value, onChange, options }: { value: string; onChange: (v: string) => void; options: string[] }) {
  return (
    <Select value={value} onValueChange={onChange}>
      <SelectTrigger>
        <SelectValue />
      </SelectTrigger>
      <SelectContent>
        {options.map((o) => (
          <SelectItem key={o} value={o}>
            {o}
          </SelectItem>
        ))}
      </SelectContent>
    </Select>
  );
}

function Review({ label, value }: { label: string; value: string }) {
  return (
    <>
      <dt className="text-muted-foreground">{label}</dt>
      <dd className="font-medium">{value}</dd>
    </>
  );
}
