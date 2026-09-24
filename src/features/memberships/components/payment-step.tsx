"use client";

import { useEffect, useState } from "react";
import Image from "next/image";
import {
  ArrowRight,
  Banknote,
  Building2,
  Check,
  ClipboardCheck,
  Copy,
  CreditCard,
  Info,
  Link2,
  MoreHorizontal,
  Pencil,
  Send,
  UserCheck,
  Wallet,
} from "lucide-react";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { DatePicker } from "@/components/shared/date-picker";
import type { PaymentMethod, PaymentTab, WizardDraft } from "@/features/memberships/add-member-wizard";
import { durationLabel } from "@/features/memberships/plan-insights";
import { cn } from "@/lib/utils";

export const PAYMENT_TABS: { tab: PaymentTab; icon: React.ComponentType<{ className?: string }>; title: string; sub: string }[] = [
  { tab: "link", icon: Link2, title: "Generate Payment Link", sub: "Create a Razorpay payment link" },
  { tab: "offline", icon: CreditCard, title: "Record Offline Payment", sub: "Cash, Bank Transfer, etc." },
  { tab: "paid", icon: ClipboardCheck, title: "Mark as Paid", sub: "If already paid" },
];

/** The hero's tagline for each tab, matching the reference design's three variants. */
export const PAYMENT_TAB_COPY: Record<PaymentTab, { tagline: string; sub: string }> = {
  link: {
    tagline: "Secure Payments. Stronger Communities.",
    sub: "Create a payment link and let your member complete the payment securely.",
  },
  offline: { tagline: "Build a Healthier Community", sub: "Members make the club stronger. Manage memberships with ease." },
  paid: { tagline: "Every Member Matters.", sub: "Mark payments, activate memberships and keep your community growing." },
};

const PAYMENT_METHODS: { value: PaymentMethod; icon: React.ComponentType<{ className?: string }> }[] = [
  { value: "Cash", icon: Wallet },
  { value: "Bank Transfer", icon: Building2 },
  { value: "UPI", icon: Banknote },
  { value: "Other", icon: MoreHorizontal },
];

const WHAT_HAPPENS_NEXT = [
  { icon: Link2, title: "Generate Link", sub: "Create a secure Razorpay payment link" },
  { icon: Check, title: "Member Created", sub: "Activated the moment payment succeeds" },
  { icon: Send, title: "Share with Member", sub: "Send via WhatsApp, SMS or Email" },
  { icon: CreditCard, title: "Member Pays", sub: "They complete the payment securely" },
];

function inr(v: number): string {
  return `₹${v.toLocaleString("en-IN")}`;
}

function Field({
  label,
  required,
  error,
  children,
}: {
  label: string;
  required?: boolean;
  error?: string;
  children: React.ReactNode;
}) {
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

/**
 * Step 5, "Payment" — three ways to settle up, matching the reference design: a Razorpay
 * subscription link (first month now, auto-billed monthly after), an offline record, or a
 * quick "it's already paid" confirmation. The latter two collect the same fields, since the
 * design shows identical forms for both; only the framing text differs.
 */
export function PaymentStep({
  draft,
  set,
  totalPayable,
  show,
  invalid,
  focusProps,
  linkResult,
  onGenerateLink,
  generatingLink,
  linkError,
  isRecurringPlan = false,
}: {
  draft: WizardDraft;
  set: <K extends keyof WizardDraft>(key: K, value: WizardDraft[K]) => void;
  totalPayable: number;
  show: (field: string) => string | undefined;
  invalid: (field: string) => string;
  focusProps: (field: string) => { onFocus: () => void; onBlur: () => void };
  /** Set once the Razorpay subscription link has actually been generated. */
  linkResult: { shortUrl: string | null } | null;
  onGenerateLink: () => void;
  generatingLink: boolean;
  linkError: string | null;
  /** True when the selected plan is RECURRING — a recurring membership must never be marked
   *  ACTIVE just because a form was submitted (spec §15), so "Record Offline Payment"/"Mark as
   *  Paid" are unavailable: the only path is the real subscription behind "Generate Payment
   *  Link", which is the sole thing that actually creates/verifies the mandate. */
  isRecurringPlan?: boolean;
}) {
  const [copied, setCopied] = useState(false);
  const [editingAmount, setEditingAmount] = useState(false);
  // Cash needs no paper trail, but UPI/Bank Transfer should always be traceable to a reference.
  const referenceRequired = draft.paymentMethod === "UPI" || draft.paymentMethod === "Bank Transfer";
  // Once a payment link exists, nothing about this membership can change here — the plan, the
  // schedule and the amount are all locked into what the link/mandate was already generated for.
  // "Record Offline Payment" specifically is switched off too: the member is meant to either pay
  // through the link or be marked as already paid (which also cancels the link) — recording a
  // separate offline payment on top of a live mandate would double up.
  const locked = Boolean(linkResult);

  useEffect(() => {
    if (isRecurringPlan && draft.paymentTab !== "link") set("paymentTab", "link");
    // eslint-disable-next-line react-hooks/exhaustive-deps -- only ever forces the tab once, when the plan is recurring; not on every draft change
  }, [isRecurringPlan]);

  async function copyLink() {
    if (!linkResult?.shortUrl) return;
    try {
      await navigator.clipboard.writeText(linkResult.shortUrl);
    } catch {
      window.prompt("Copy this link:", linkResult.shortUrl);
    }
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  }

  return (
    <div className="space-y-5">
      <div className="grid grid-cols-1 gap-3 sm:grid-cols-3">
        {PAYMENT_TABS.map((t) => {
          const tabLocked = (locked && t.tab === "offline") || (isRecurringPlan && t.tab !== "link");
          return (
          <button
            key={t.tab}
            type="button"
            disabled={tabLocked}
            onClick={() => set("paymentTab", t.tab)}
            title={
              isRecurringPlan && t.tab !== "link"
                ? "This is a recurring plan — payment must go through a verified subscription, not an offline record."
                : tabLocked
                  ? "A payment link has already been generated — record offline payment is unavailable."
                  : undefined
            }
            className={cn(
              "flex items-center gap-3 rounded-xl border p-3 text-left transition-colors",
              tabLocked
                ? "cursor-not-allowed border-input opacity-50"
                : draft.paymentTab === t.tab
                  ? "border-[#0B9B63] bg-success/10"
                  : "border-input hover:bg-accent/50",
            )}
          >
            <span
              className={cn(
                "flex h-9 w-9 shrink-0 items-center justify-center rounded-lg",
                draft.paymentTab === t.tab ? "bg-[#0B9B63] text-white" : "bg-blue-500/15 text-blue-600 dark:text-blue-400",
              )}
            >
              <t.icon className="h-4.5 w-4.5" aria-hidden />
            </span>
            <span>
              <span className="block text-sm font-semibold text-foreground">{t.title}</span>
              <span className="block text-xs text-muted-foreground">{t.sub}</span>
            </span>
          </button>
          );
        })}
      </div>

      {draft.paymentTab === "link" ? (
        <div className="space-y-5">
          <Card className="space-y-4 rounded-xl p-4">
            <div className="flex flex-wrap items-start justify-between gap-3">
              <div className="flex items-start gap-2.5">
                <span className="flex h-9 w-9 shrink-0 items-center justify-center rounded-lg bg-success/15 text-success">
                  <Link2 className="h-4.5 w-4.5" aria-hidden />
                </span>
                <div>
                  <p className="text-sm font-bold text-black dark:text-foreground">Payment Details</p>
                  <p className="text-xs text-muted-foreground">
                    Generate a secure Razorpay payment link for this membership. Share it with the member and complete the
                    registration after payment.
                  </p>
                </div>
              </div>
              <Image src="/assets/razorpay-icon.svg" alt="Razorpay" width={96} height={24} className="h-5 w-auto shrink-0" />
            </div>

            <div className="flex flex-wrap items-center justify-between gap-3 rounded-xl border border-border bg-muted/30 p-4">
              <div>
                <p className="text-xs text-muted-foreground">Amount to Collect</p>
                {editingAmount ? (
                  <Input
                    autoFocus
                    type="number"
                    value={draft.paymentAmount || ""}
                    onChange={(e) => set("paymentAmount", Number(e.target.value) || 0)}
                    onBlur={() => setEditingAmount(false)}
                    className="mt-1 w-32"
                  />
                ) : (
                  <p className="text-2xl font-bold tabular-nums text-black dark:text-foreground">{inr(draft.paymentAmount)}</p>
                )}
                <p className="text-xs text-muted-foreground">
                  {draft.planName} ({durationLabel(draft.durationDays)})
                </p>
              </div>
              {!editingAmount && !locked && (
                <button
                  type="button"
                  onClick={() => setEditingAmount(true)}
                  className="flex h-9 items-center gap-1.5 rounded-lg border border-input bg-card px-3 text-xs font-medium transition-colors hover:bg-accent"
                >
                  <Pencil className="h-3 w-3" aria-hidden />
                  Edit Amount
                </button>
              )}
            </div>
            {show("paymentAmount") && <p className="text-xs text-destructive">{show("paymentAmount")}</p>}

            <div className="flex items-start gap-2.5 rounded-lg bg-blue-500/10 p-3">
              <Info className="mt-0.5 h-4 w-4 shrink-0 text-blue-600 dark:text-blue-400" aria-hidden />
              <p className="text-xs leading-relaxed text-foreground/80">
                A secure Razorpay payment link will be generated for this month, and the same amount will auto-collect on
                this day every month after — the member only has to approve it once. You can share this link via
                WhatsApp, SMS, or Email.
              </p>
            </div>

            {linkResult?.shortUrl ? (
              <div className="space-y-2 rounded-xl border border-success/30 bg-success/10 p-4">
                <p className="flex items-center gap-1.5 text-sm font-semibold text-success">
                  <Check className="h-4 w-4" aria-hidden />
                  Member created — payment link ready
                </p>
                <div className="flex items-center gap-2">
                  <Input readOnly value={linkResult.shortUrl} className="flex-1 bg-card text-xs" />
                  <button
                    type="button"
                    onClick={copyLink}
                    className="flex h-9 shrink-0 items-center gap-1.5 rounded-lg bg-[#0B9B63] px-3 text-xs font-semibold text-white transition-opacity hover:opacity-90"
                  >
                    <Copy className="h-3.5 w-3.5" aria-hidden />
                    {copied ? "Copied" : "Copy"}
                  </button>
                </div>
                <p className="text-xs text-foreground/80">
                  The member is already created (Payment Incomplete) — share this link and their status updates once
                  they pay.
                </p>
              </div>
            ) : (
              <button
                type="button"
                disabled={generatingLink}
                onClick={onGenerateLink}
                className="mx-auto flex w-2/5 items-center justify-center gap-2 rounded-2xl bg-gradient-to-r from-[#0F9D66] to-[#0B7A55] py-3.5 text-white transition-opacity hover:opacity-90 disabled:opacity-60"
              >
                <Link2 className="h-4 w-4 shrink-0" aria-hidden />
                <span className="text-center">
                  <span className="block text-sm font-semibold leading-tight">
                    {generatingLink ? "Generating…" : "Generate Payment Link"}
                  </span>
                  <span className="block text-[11px] font-normal leading-tight opacity-85">Create Razorpay payment link</span>
                </span>
              </button>
            )}
            {linkError && <p className="text-xs text-destructive">{linkError}</p>}

            <div className="space-y-3 border-t border-border pt-4">
              <p className="text-sm font-semibold text-foreground">What happens next?</p>
              <div className="flex flex-col gap-3 sm:flex-row sm:items-start">
                {WHAT_HAPPENS_NEXT.map((s, i) => (
                  <div key={s.title} className="flex flex-1 items-start gap-2">
                    <div className="flex items-start gap-2">
                      <span className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-blue-500/15 text-blue-600 dark:text-blue-400">
                        <s.icon className="h-4 w-4" aria-hidden />
                      </span>
                      <div>
                        <p className="text-xs font-semibold text-foreground">{s.title}</p>
                        <p className="text-[11px] text-muted-foreground">{s.sub}</p>
                      </div>
                    </div>
                    {i < WHAT_HAPPENS_NEXT.length - 1 && (
                      <ArrowRight className="mt-2 hidden h-3.5 w-3.5 shrink-0 text-muted-foreground sm:block" aria-hidden />
                    )}
                  </div>
                ))}
              </div>
            </div>
          </Card>
        </div>
      ) : (
        <Card className="space-y-5 rounded-xl p-4">
          <div className="flex items-start gap-2.5">
            <span className="flex h-9 w-9 shrink-0 items-center justify-center rounded-lg bg-success/15 text-success">
              {draft.paymentTab === "paid" ? <ClipboardCheck className="h-4.5 w-4.5" aria-hidden /> : <CreditCard className="h-4.5 w-4.5" aria-hidden />}
            </span>
            <div>
              <p className="text-sm font-bold text-black dark:text-foreground">
                {draft.paymentTab === "paid" ? "Mark as Paid" : "Record Offline Payment"}
              </p>
              <p className="text-xs text-muted-foreground">
                {draft.paymentTab === "paid"
                  ? "Mark this membership as paid if the payment has already been received outside the system."
                  : "Record a payment received outside the online system (Cash, Bank Transfer, UPI, etc.)."}
              </p>
            </div>
          </div>

          {draft.paymentTab === "paid" && (
            <div className="flex items-start gap-2.5 rounded-lg bg-success/10 p-3">
              <Check className="mt-0.5 h-4 w-4 shrink-0 text-success" aria-hidden />
              <p className="text-xs text-foreground/80">This will mark the payment as completed and you can create the member immediately.</p>
            </div>
          )}

          <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
            <Field label="Payment Amount" required error={show("paymentAmount")}>
              <div className="flex items-center gap-2">
                <span className="flex h-10 w-10 shrink-0 items-center justify-center rounded-lg border border-input text-muted-foreground">
                  ₹
                </span>
                <Input
                  type="number"
                  value={draft.paymentAmount || ""}
                  onChange={(e) => set("paymentAmount", Number(e.target.value) || 0)}
                  {...focusProps("paymentAmount")}
                  className={invalid("paymentAmount")}
                />
              </div>
            </Field>
            <Field label="Payment Date" required error={show("paymentDate")}>
              <DatePicker
                value={draft.paymentDate}
                onChange={(iso) => set("paymentDate", iso)}
                triggerClassName={cn(
                  "flex h-10 w-full items-center justify-between gap-2 rounded-lg border border-input bg-card px-3 text-left text-sm outline-none transition-colors hover:border-foreground/30",
                  invalid("paymentDate"),
                )}
              />
            </Field>
          </div>

          <div>
            <p className="mb-1.5 text-xs font-medium text-foreground/80">
              Payment Mode <span className="text-destructive">*</span>
            </p>
            <div className="grid grid-cols-2 gap-2 sm:grid-cols-4">
              {PAYMENT_METHODS.map((m) => (
                <button
                  key={m.value}
                  type="button"
                  onClick={() => set("paymentMethod", m.value)}
                  className={cn(
                    "flex h-11 items-center justify-center gap-1.5 rounded-lg border text-sm transition-colors",
                    draft.paymentMethod === m.value
                      ? "border-[#0B9B63] bg-success/10 font-medium text-[#0B7A55]"
                      : "border-input hover:bg-accent",
                  )}
                >
                  <m.icon className="h-4 w-4" aria-hidden />
                  {m.value}
                </button>
              ))}
            </div>
          </div>

          <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
            <Field
              label={referenceRequired ? "Reference / Transaction ID" : "Reference / Transaction ID (Optional)"}
              required={referenceRequired}
              error={show("paymentReference")}
            >
              <Input
                value={draft.paymentReference}
                onChange={(e) => set("paymentReference", e.target.value)}
                {...focusProps("paymentReference")}
                placeholder="Enter reference number (e.g. UTR, Receipt No.)"
                className={invalid("paymentReference")}
              />
            </Field>
            <Field label="Received From" required error={show("receivedFrom")}>
              <Input
                value={draft.receivedFrom}
                onChange={(e) => set("receivedFrom", e.target.value)}
                {...focusProps("receivedFrom")}
                className={invalid("receivedFrom")}
              />
            </Field>
          </div>

          <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
            <Field label="Collected By" required error={show("collectedBy")}>
              <div className="flex items-center gap-2">
                <UserCheck className="h-4 w-4 shrink-0 text-muted-foreground" aria-hidden />
                <Input
                  value={draft.collectedBy}
                  onChange={(e) => set("collectedBy", e.target.value)}
                  {...focusProps("collectedBy")}
                  placeholder="Staff member's name"
                  className={cn("flex-1", invalid("collectedBy"))}
                />
              </div>
            </Field>

            <Field label="Notes (Optional)">
              <textarea
                value={draft.paymentNotes}
                onChange={(e) => set("paymentNotes", e.target.value.slice(0, 500))}
                placeholder="Add any additional notes..."
                rows={1}
                className="flex w-full rounded-md border border-input bg-transparent px-3 py-2 text-sm shadow-sm outline-none transition-colors placeholder:text-muted-foreground/60 focus-visible:border-foreground/40"
              />
              <p className="text-right text-[11px] text-muted-foreground">{draft.paymentNotes.length}/500</p>
            </Field>
          </div>

          <div className="flex items-start gap-2.5 rounded-lg bg-blue-500/10 p-4">
            <Info className="mt-0.5 h-4 w-4 shrink-0 text-blue-600 dark:text-blue-400" aria-hidden />
            <div className="space-y-1 text-xs text-foreground/80">
              <p className="font-semibold text-foreground">Important</p>
              <ul className="list-disc space-y-0.5 pl-4">
                <li>
                  {draft.paymentTab === "paid"
                    ? "Use this option only if the payment has already been received offline."
                    : "Recording an offline payment will mark this membership as paid once you create the member."}
                </li>
                <li>Please ensure the payment has actually been received before marking it here.</li>
                <li>
                  You can view all {draft.paymentTab === "paid" ? "marked payments" : "offline payments"} in the{" "}
                  <span className="font-medium">Payments</span> section.
                </li>
                {locked && (
                  <li className="font-medium text-foreground">
                    A payment link was already generated for this member — confirming here cancels it, so it stops
                    working immediately.
                  </li>
                )}
              </ul>
            </div>
          </div>
        </Card>
      )}

      <div className="rounded-xl bg-success/10 p-4">
        <div className="flex items-center justify-between">
          <span className="text-sm font-semibold">Total payable</span>
          <span className="text-xl font-bold tabular-nums">{inr(totalPayable)}</span>
        </div>
      </div>
    </div>
  );
}
