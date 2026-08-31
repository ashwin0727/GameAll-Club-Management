"use client";

import { useEffect, useState } from "react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Skeleton } from "@/components/ui/skeleton";
import {
  getPublicSignupBatches,
  getPublicSignupInfo,
  startPublicSignup,
  startPublicSubscription,
} from "@/features/memberships/public-signup";
import { formatSlot } from "@/features/memberships/slot-format";
import type { PublicSignupBatch, PublicSignupInfo } from "@/features/memberships/types";

function inr(v: number): string {
  return `₹${v.toLocaleString("en-IN")}`;
}

export function JoinMembershipForm({ facilityId }: { facilityId: string }) {
  const [info, setInfo] = useState<PublicSignupInfo | null | "error">(null);
  const [name, setName] = useState("");
  const [phone, setPhone] = useState("");
  const [email, setEmail] = useState("");
  const [planId, setPlanId] = useState("");
  const [batches, setBatches] = useState<PublicSignupBatch[]>([]);
  const [batchId, setBatchId] = useState("");
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [done, setDone] = useState(false);

  useEffect(() => {
    getPublicSignupInfo(facilityId)
      .then((i) => setInfo(i ?? "error"))
      .catch(() => setInfo("error"));
  }, [facilityId]);

  useEffect(() => {
    setBatchId("");
    if (!planId) {
      setBatches([]);
      return;
    }
    let cancelled = false;
    getPublicSignupBatches(facilityId, planId)
      .then((b) => !cancelled && setBatches(b))
      .catch(() => !cancelled && setBatches([]));
    return () => {
      cancelled = true;
    };
  }, [planId, facilityId]);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    if (!name.trim() || !phone.trim()) return setError("Please enter your name and phone number.");
    if (!planId) return setError("Please choose a membership plan.");
    setSubmitting(true);
    setError(null);
    try {
      const signup = await startPublicSignup({
        facilityId,
        fullName: name.trim(),
        phone: phone.trim(),
        email: email.trim(),
        planId,
        batchId: batchId || null,
      });
      if (signup.amountInr > 0) {
        const sub = await startPublicSubscription(signup.membershipId);
        if (sub.shortUrl) {
          window.location.href = sub.shortUrl;
          return;
        }
      }
      setDone(true);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Something went wrong. Please try again.");
    } finally {
      setSubmitting(false);
    }
  }

  if (info === null) {
    return (
      <div className="space-y-3">
        <Skeleton className="h-8 w-2/3" />
        <Skeleton className="h-40 w-full" />
      </div>
    );
  }

  if (info === "error") {
    return (
      <p className="text-sm text-muted-foreground">
        This membership link is not valid or the club is not accepting sign-ups right now.
      </p>
    );
  }

  if (done) {
    return (
      <div className="space-y-2">
        <h2 className="text-lg font-semibold">You&apos;re registered 🎉</h2>
        <p className="text-sm text-muted-foreground">
          {info.facilityName} has received your membership request. They&apos;ll confirm your start and collect payment.
        </p>
      </div>
    );
  }

  return (
    <form onSubmit={submit} className="space-y-5">
      <div>
        <h1 className="text-xl font-semibold">Join {info.facilityName}</h1>
        {info.city && <p className="text-sm text-muted-foreground">{info.city}</p>}
      </div>

      <div className="grid gap-3 sm:grid-cols-2">
        <Input value={name} onChange={(e) => setName(e.target.value)} placeholder="Full name" />
        <Input value={phone} onChange={(e) => setPhone(e.target.value)} placeholder="Phone number" inputMode="tel" />
        <Input
          value={email}
          onChange={(e) => setEmail(e.target.value)}
          placeholder="Email (optional)"
          type="email"
          className="sm:col-span-2"
        />
      </div>

      <div className="space-y-2">
        <p className="text-sm font-medium">Choose your plan</p>
        {info.plans.length === 0 ? (
          <p className="text-sm text-muted-foreground">No plans are available right now.</p>
        ) : (
          <div className="space-y-2">
            {info.plans.map((p) => (
              <button
                key={p.id}
                type="button"
                onClick={() => setPlanId(p.id)}
                className={`w-full rounded-md border px-3 py-3 text-left ${
                  planId === p.id ? "border-primary bg-primary/5" : "border-input hover:bg-accent"
                }`}
              >
                <div className="flex items-center justify-between">
                  <span className="font-medium">{p.name}</span>
                  <span className="font-semibold">{inr(p.priceInr)} / month</span>
                </div>
                {p.features.length > 0 && (
                  <p className="mt-1 text-xs text-muted-foreground">{p.features.join(" · ")}</p>
                )}
              </button>
            ))}
          </div>
        )}
      </div>

      {planId && batches.length > 0 && (
        <div className="space-y-2">
          <p className="text-sm font-medium">Pick your time slot</p>
          <div className="space-y-2">
            <button
              type="button"
              onClick={() => setBatchId("")}
              className={`w-full rounded-md border px-3 py-2 text-left text-sm ${
                batchId === "" ? "border-primary bg-primary/5" : "border-input hover:bg-accent"
              }`}
            >
              No fixed slot — I&apos;ll book each time
            </button>
            {batches.map((b) => (
              <button
                key={b.batchId}
                type="button"
                onClick={() => setBatchId(b.batchId)}
                className={`flex w-full items-center justify-between rounded-md border px-3 py-2 text-left text-sm ${
                  batchId === b.batchId ? "border-primary bg-primary/5" : "border-input hover:bg-accent"
                }`}
              >
                <span>
                  {b.name}
                  <span className="block text-xs text-muted-foreground">
                    {b.courtName} · {formatSlot(b.daysOfWeek, b.startTime, b.endTime)}
                  </span>
                </span>
                <span className="text-xs text-muted-foreground">{b.spare} left</span>
              </button>
            ))}
          </div>
        </div>
      )}

      <p className="text-xs text-muted-foreground">
        Paying by UPI? You&apos;ll set up an AutoPay mandate on the next screen — the monthly amount is then charged
        automatically. You can cancel anytime.
      </p>

      {error && <p className="text-sm text-destructive">{error}</p>}

      <Button type="submit" className="w-full" disabled={submitting || info.plans.length === 0}>
        {submitting ? "Setting up…" : "Continue to payment"}
      </Button>
    </form>
  );
}