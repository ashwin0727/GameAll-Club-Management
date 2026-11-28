"use client";

import { Lock, ShieldCheck } from "lucide-react";
import { Input } from "@/components/ui/input";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Textarea } from "@/components/ui/textarea";
import { OnboardingField, PAYOUT_FREQUENCY_OPTIONS } from "@/features/coaching/components/coach-onboarding-field";
import type { CoachOnboardingState } from "@/features/coaching/components/use-coach-onboarding";
import {
  isValidAccountNumber,
  isValidGstin,
  isValidIfsc,
  isValidPan,
  isValidUpi,
  normalizeGstin,
  normalizeIfsc,
  normalizePan,
} from "@/features/coaching/coach-onboarding-validation";
import { cn } from "@/lib/utils";

/** Step 4 — Payments, Payouts & KYC. Secrets are typed here but only ever come back masked. */
export function PayoutStep({ form }: { form: CoachOnboardingState }) {
  const p = form.draft.payout;
  const saved = form.savedPayout;

  if (!form.canManagePayouts) {
    return (
      <div className="flex items-start gap-3 rounded-lg border border-border bg-muted/30 p-4 text-sm">
        <Lock className="mt-0.5 h-4 w-4 shrink-0 text-muted-foreground" aria-hidden />
        <div>
          <p className="font-medium">Payout &amp; KYC details are restricted</p>
          <p className="text-muted-foreground">
            You don&apos;t have permission to enter bank or tax details. You can finish this coach now — an owner can add the payout details later, and the coach stays marked &ldquo;KYC pending&rdquo; until then.
          </p>
        </div>
      </div>
    );
  }

  const set = form.patchPayout;
  const business = p.entityType === "BUSINESS";
  const taxNorm = business && isValidGstin(normalizeGstin(p.taxId)) ? normalizeGstin(p.taxId) : normalizePan(p.taxId);
  const taxBad = p.taxId.trim() !== "" && !(isValidPan(taxNorm) || (business && isValidGstin(taxNorm)));
  const acctBad = p.accountNumber !== "" && !isValidAccountNumber(p.accountNumber);
  const confirmBad = p.confirmAccountNumber !== "" && p.confirmAccountNumber !== p.accountNumber;
  const ifscBad = p.ifsc.trim() !== "" && !isValidIfsc(normalizeIfsc(p.ifsc));
  const upiBad = p.upiId.trim() !== "" && !isValidUpi(p.upiId);

  return (
    <div className="space-y-5">
      <div className="flex items-start gap-2 rounded-lg bg-primary/5 p-3 text-xs text-muted-foreground">
        <ShieldCheck className="mt-0.5 h-4 w-4 shrink-0 text-primary" aria-hidden />
        <p>Bank and tax details are stored in a restricted area and shown masked (last 4 characters) after saving. You can finish this step later.</p>
      </div>

      {saved && (
        <div className="rounded-lg border border-success/40 bg-success/10 p-3 text-sm">
          <p className="font-medium text-success">Payout details saved</p>
          <p className="text-muted-foreground">
            {[saved.taxIdMasked && `Tax ID ${saved.taxIdMasked}`, saved.accountNumberMasked && `Account ${saved.accountNumberMasked}`, saved.ifsc && `IFSC ${saved.ifsc}`, saved.upiId && `UPI ${saved.upiId}`]
              .filter(Boolean)
              .join(" · ") || "Saved."}{" "}
            Leave the secret fields blank to keep them, or type new values to replace them.
          </p>
        </div>
      )}

      <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
        <OnboardingField label="Entity Type" required htmlFor="ob-entity">
          <Select value={p.entityType} onValueChange={(v) => set({ entityType: v as "INDIVIDUAL" | "BUSINESS" })}>
            <SelectTrigger id="ob-entity">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="INDIVIDUAL">Individual</SelectItem>
              <SelectItem value="BUSINESS">Business</SelectItem>
            </SelectContent>
          </Select>
        </OnboardingField>
        <OnboardingField
          label={business ? "PAN or GSTIN" : "PAN"}
          required={!saved}
          htmlFor="ob-tax"
          error={taxBad ? (business ? "Enter a valid PAN (ABCDE1234F) or GSTIN." : "Enter a valid PAN, e.g. ABCDE1234F.") : null}
          hint={saved?.taxIdMasked ? "Leave blank to keep the saved value." : undefined}
        >
          <Input id="ob-tax" value={p.taxId} onChange={(e) => set({ taxId: e.target.value.toUpperCase() })} maxLength={20} placeholder={saved?.taxIdMasked ?? "ABCDE1234F"} autoComplete="off" />
        </OnboardingField>
        {business && (
          <>
            <OnboardingField label="Legal Business Name" required htmlFor="ob-legal">
              <Input id="ob-legal" value={p.legalName} onChange={(e) => set({ legalName: e.target.value })} />
            </OnboardingField>
            <OnboardingField label="Business Address" required htmlFor="ob-addr">
              <Input id="ob-addr" value={p.businessAddress} onChange={(e) => set({ businessAddress: e.target.value })} />
            </OnboardingField>
          </>
        )}
      </div>

      <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
        <OnboardingField label="Preferred Payout Method" required htmlFor="ob-method">
          <Select value={p.payoutMethod} onValueChange={(v) => set({ payoutMethod: v as "BANK_TRANSFER" | "UPI" })}>
            <SelectTrigger id="ob-method">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="BANK_TRANSFER">Bank transfer</SelectItem>
              <SelectItem value="UPI">UPI</SelectItem>
            </SelectContent>
          </Select>
        </OnboardingField>
        <OnboardingField label="Payout Frequency" required htmlFor="ob-freq">
          <Select value={p.payoutFrequency} onValueChange={(v) => set({ payoutFrequency: v as typeof p.payoutFrequency })}>
            <SelectTrigger id="ob-freq">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              {PAYOUT_FREQUENCY_OPTIONS.map((f) => (
                <SelectItem key={f.value} value={f.value}>
                  {f.label}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        </OnboardingField>

        {p.payoutMethod === "BANK_TRANSFER" ? (
          <>
            <OnboardingField label="Account Holder Name" required htmlFor="ob-holder">
              <Input id="ob-holder" value={p.accountHolderName} onChange={(e) => set({ accountHolderName: e.target.value })} autoComplete="off" />
            </OnboardingField>
            <OnboardingField label="IFSC Code" required={!saved} htmlFor="ob-ifsc" error={ifscBad ? "Enter a valid IFSC, e.g. SBIN0001234." : null} hint={saved?.ifsc ? "Leave blank to keep the saved value." : undefined}>
              <Input id="ob-ifsc" value={p.ifsc} onChange={(e) => set({ ifsc: e.target.value.toUpperCase() })} maxLength={14} placeholder={saved?.ifsc ?? "SBIN0001234"} autoComplete="off" />
            </OnboardingField>
            <OnboardingField label="Account Number" required={!saved} htmlFor="ob-acct" error={acctBad ? "Account numbers are 9 to 18 digits." : null} hint={saved?.accountNumberMasked ? "Leave blank to keep the saved value." : undefined}>
              <Input id="ob-acct" type="password" inputMode="numeric" value={p.accountNumber} onChange={(e) => set({ accountNumber: e.target.value.replace(/\s/g, "") })} maxLength={18} placeholder={saved?.accountNumberMasked ?? ""} autoComplete="off" />
            </OnboardingField>
            <OnboardingField label="Confirm Account Number" required={!saved} htmlFor="ob-acct2" error={confirmBad ? "The account numbers don't match." : null}>
              <Input id="ob-acct2" inputMode="numeric" value={p.confirmAccountNumber} onChange={(e) => set({ confirmAccountNumber: e.target.value.replace(/\s/g, "") })} maxLength={18} autoComplete="off" onPaste={(e) => e.preventDefault()} />
            </OnboardingField>
          </>
        ) : (
          <OnboardingField label="UPI ID" required={!saved} htmlFor="ob-upi" error={upiBad ? "Enter a valid UPI ID, e.g. name@okbank." : null} className="sm:col-span-2">
            <Input id="ob-upi" value={p.upiId} onChange={(e) => set({ upiId: e.target.value })} placeholder={saved?.upiId ?? "name@okbank"} autoComplete="off" />
          </OnboardingField>
        )}

        <OnboardingField label="Currency" htmlFor="ob-cur" hint="Payouts are in Indian rupees.">
          <Input id="ob-cur" value="INR (₹)" disabled readOnly />
        </OnboardingField>
        <OnboardingField label="Cancellation & Refund Policy (Optional)" htmlFor="ob-policy" className="sm:col-span-2">
          <Textarea id="ob-policy" rows={3} value={p.cancellationPolicy} onChange={(e) => set({ cancellationPolicy: e.target.value })} placeholder="e.g. Free cancellation up to 24 hours before a session; after that the session is charged." className={cn("resize-y")} />
        </OnboardingField>
      </div>
    </div>
  );
}
