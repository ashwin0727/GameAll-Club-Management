"use client";

import * as React from "react";
import { useRouter } from "next/navigation";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import {
  ArrowLeft,
  Calendar,
  Check,
  FileText,
  Info,
  Landmark,
  Layers,
  ListChecks,
  Loader2,
  Lock,
  Pencil,
  Plus,
  Search,
  Settings,
  Smartphone,
  Trash2,
  Wallet,
} from "lucide-react";
import { toast } from "sonner";
import { Skeleton } from "@/components/ui/skeleton";
import { Switch } from "@/components/ui/switch";
import { ConfirmDialog } from "@/components/shared/confirm-dialog";
import { FormMessage } from "@/features/auth/components/form-message";
import { useCurrentUser } from "@/features/auth/hooks/use-auth";
import { useFacility } from "@/features/facility/hooks/use-facility";
import { CardHeading, Field, SetupCard, SetupInput, SetupSelect } from "@/features/onboarding/components/setup-fields";
import { useOnboardingStore } from "@/features/onboarding/state/onboarding-store";
import { INDIAN_BANKS, bankFromIfsc, lookupIfsc } from "@/features/payout-setup/banks";
import {
  DEFAULT_PAYOUT_SETTINGS,
  FREQUENCY_OPTIONS,
  loadPayoutSettings,
  savePayoutSettings,
  validatePayoutSettings,
  type PayoutSettings,
  type SettlementFrequency,
} from "@/features/payout-setup/payout-settings";
import { MethodDialog, VerificationBadge } from "@/features/profile/components/payment-methods-page";
import { profileKeys, usePayoutMethods } from "@/features/profile/hooks";
import { maskAccountNumber, maskUpi, bankPayoutSchema, upiPayoutSchema } from "@/features/profile/payout-validation";
import type { PayoutAccountType, PayoutMethod } from "@/features/profile/types";
import { resubmitIfRejected } from "@/features/setup-review/api";
import { getOnboardingService } from "@/services/onboarding";
import { getProfileService } from "@/services/profile";
import { cn } from "@/lib/utils";

const settingsKey = (facilityId: string) => ["payout-settings", facilityId] as const;

type BankFields = { holder: string; bank: string; number: string; ifsc: string; type: PayoutAccountType };
const EMPTY_BANK: BankFields = { holder: "", bank: "", number: "", ifsc: "", type: "SAVINGS" };

/**
 * Payout (setup step 5): where the money goes (bank accounts / UPI IDs), how and when it is settled, and what is included. Finishing
 * submits the whole setup to GameAll for approval; until it is approved the dashboard stays closed (see the dashboard layout).
 */
export function PayoutSetupForm() {
  const router = useRouter();
  const qc = useQueryClient();
  const { data: user } = useCurrentUser();
  const { data: facility, isLoading } = useFacility();
  const completePayments = useOnboardingStore((s) => s.completePayments);
  const isOwner = !!facility && facility.ownerId === user?.id;
  const methods = usePayoutMethods(facility?.id, isOwner);

  const [settings, setSettings] = React.useState<PayoutSettings>(DEFAULT_PAYOUT_SETTINGS);
  const [settingsReady, setSettingsReady] = React.useState(false);
  const settingsQuery = useQuery({
    queryKey: settingsKey(facility?.id ?? ""),
    queryFn: () => loadPayoutSettings(facility!.id),
    enabled: !!facility && isOwner,
    staleTime: Infinity,
  });
  React.useEffect(() => {
    if (settingsQuery.data && !settingsReady) {
      setSettings(settingsQuery.data);
      setSettingsReady(true);
    }
  }, [settingsQuery.data, settingsReady]);

  const [active, setActive] = React.useState<"BANK" | "UPI">("BANK");
  const [bank, setBank] = React.useState<BankFields>(EMPTY_BANK);
  const [bankErrors, setBankErrors] = React.useState<Record<string, string>>({});
  const [upi, setUpi] = React.useState("");
  const [upiError, setUpiError] = React.useState<string | null>(null);
  const [ifscNote, setIfscNote] = React.useState<{ ok: boolean; text: string } | null>(null);
  const [finding, setFinding] = React.useState(false);
  const [extraBank, setExtraBank] = React.useState<string | null>(null);

  const [editing, setEditing] = React.useState<PayoutMethod | null>(null);
  const [removing, setRemoving] = React.useState<PayoutMethod | null>(null);
  const [error, setError] = React.useState<string | null>(null);
  const [saving, setSaving] = React.useState<null | "draft" | "complete">(null);

  const refresh = () => qc.invalidateQueries({ queryKey: profileKeys.payouts(facility?.id ?? "") });
  const makePrimary = useMutation({
    mutationFn: (id: string) => getProfileService().setPrimaryPayoutMethod(id),
    onSuccess: refresh,
    onError: (e) => setError(e instanceof Error ? e.message : "Could not change the primary method."),
  });
  const remove = useMutation({
    mutationFn: (id: string) => getProfileService().deletePayoutMethod(id),
    onSuccess: async () => {
      await refresh();
      setRemoving(null);
    },
    onError: (e) => {
      setRemoving(null);
      setError(e instanceof Error ? e.message : "Could not remove this payout account.");
    },
  });
  const addMethod = useMutation({
    mutationFn: (input: Parameters<ReturnType<typeof getProfileService>["addPayoutMethod"]>[1]) => getProfileService().addPayoutMethod(facility!.id, input),
    onSuccess: refresh,
  });

  const list = methods.data ?? [];
  const bankOptions = React.useMemo(() => {
    const names: string[] = [...INDIAN_BANKS];
    for (const extra of [extraBank, bank.bank]) if (extra && !names.includes(extra)) names.unshift(extra);
    return names.map((n) => ({ value: n, label: n }));
  }, [extraBank, bank.bank]);

  function setBankField<K extends keyof BankFields>(k: K, v: BankFields[K]) {
    setBank((p) => ({ ...p, [k]: v }));
    setBankErrors((p) => (p[k] ? { ...p, [k]: "" } : p));
  }

  function onIfscChange(raw: string) {
    const v = raw.toUpperCase().replace(/[^A-Z0-9]/g, "").slice(0, 11);
    setIfscNote(null);
    setBank((p) => {
      // The first four letters name the bank, so a known prefix fills the dropdown for them.
      const inferred = v.length >= 4 ? bankFromIfsc(v) : null;
      return { ...p, ifsc: v, bank: inferred && !p.bank ? inferred : p.bank };
    });
    setBankErrors((p) => (p.ifsc ? { ...p, ifsc: "" } : p));
  }

  async function findIfsc() {
    const code = bank.ifsc.trim().toUpperCase();
    if (!/^[A-Z]{4}0[A-Z0-9]{6}$/.test(code)) {
      setBankErrors((p) => ({ ...p, ifsc: "Enter a valid IFSC, like HDFC0001234." }));
      return;
    }
    setFinding(true);
    setIfscNote(null);
    try {
      const found = await lookupIfsc(code);
      if (!found) {
        setIfscNote({ ok: false, text: "We couldn't find this IFSC. Check it and try again." });
      } else {
        setExtraBank(found.bank);
        setBank((p) => ({ ...p, bank: found.bank }));
        setBankErrors((p) => ({ ...p, ifsc: "", bank: "" }));
        setIfscNote({ ok: true, text: [found.bank, found.branch, found.city].filter(Boolean).join(" · ") });
      }
    } catch {
      setIfscNote({ ok: false, text: "The IFSC directory isn't reachable right now. You can still add the account." });
    } finally {
      setFinding(false);
    }
  }

  async function addBank() {
    setError(null);
    const parsed = bankPayoutSchema.safeParse({
      type: "BANK",
      accountHolderName: bank.holder,
      bankName: bank.bank,
      accountNumber: bank.number,
      ifsc: bank.ifsc,
      accountType: bank.type,
    });
    if (!parsed.success) {
      const next: Record<string, string> = {};
      for (const issue of parsed.error.issues) {
        const key = ({ accountHolderName: "holder", bankName: "bank", accountNumber: "number", ifsc: "ifsc", accountType: "type" } as Record<string, string>)[String(issue.path[0])] ?? "form";
        next[key] ??= issue.message;
      }
      return setBankErrors(next);
    }
    setBankErrors({});
    try {
      await addMethod.mutateAsync(parsed.data);
      setBank({ ...EMPTY_BANK, holder: bank.holder });
      setIfscNote(null);
      toast.success("Bank account added.");
    } catch (e) {
      setError(friendly(e, "Could not add this bank account."));
    }
  }

  async function addUpi() {
    setError(null);
    const holder = bank.holder.trim() || user?.name?.trim() || facility?.name || "";
    const parsed = upiPayoutSchema.safeParse({ type: "UPI", accountHolderName: holder, upiId: upi });
    if (!parsed.success) return setUpiError(parsed.error.issues[0]?.message ?? "Enter a valid UPI ID.");
    setUpiError(null);
    try {
      await addMethod.mutateAsync(parsed.data);
      setUpi("");
      toast.success("UPI ID added.");
    } catch (e) {
      setError(friendly(e, "Could not add this UPI ID."));
    }
  }

  async function persist(complete: boolean) {
    if (!facility) return;
    setError(null);
    const problem = validatePayoutSettings(settings);
    if (problem) return setError(problem);
    if (complete && list.length === 0) return setError("Add at least one bank account or UPI ID to finish setup.");
    setSaving(complete ? "complete" : "draft");
    try {
      await savePayoutSettings(facility.id, settings);
      if (complete) {
        // Goes through the complete_facility_setup RPC: it also flips profiles.onboarding_completed and SUBMITS the setup to GameAll.
        await getOnboardingService().completeSetup(facility.id);
        // A facility GameAll sent back is re-submitted by finishing setup again.
        await resubmitIfRejected(facility.id);
        completePayments();
        router.push("/onboarding/review");
      } else {
        toast.success("Draft saved. You can pick up where you left off.");
      }
    } catch (e) {
      setError(friendly(e, "We couldn't finish your setup. Please try again."));
    } finally {
      setSaving(null);
    }
  }

  if (isLoading) return <Skeleton className="h-72 w-full rounded-2xl" />;
  if (!facility) {
    router.replace("/onboarding/facility");
    return null;
  }
  if (!isOwner) return <FormMessage>You don&apos;t have access to this facility.</FormMessage>;

  const frequencyNote = FREQUENCY_OPTIONS.find((o) => o.value === settings.frequency)?.note ?? "";
  const set = (patch: Partial<PayoutSettings>) => setSettings((s) => ({ ...s, ...patch }));
  const busy = makePrimary.isPending || remove.isPending;

  return (
    <div className="space-y-5">
      {error && <FormMessage>{error}</FormMessage>}

      <div className="grid items-start gap-5 xl:grid-cols-[minmax(0,1.6fr)_minmax(0,1fr)]">
        {/* ── left: accounts ── */}
        <div className="min-w-0 space-y-5">
          <SetupCard>
            <CardHeading
              icon={<Wallet className="h-6 w-6" aria-hidden="true" />}
              title="Payout Account"
              description="Add and manage your bank account or UPI to receive payouts from GameAll."
            />

            <div role="tablist" aria-label="Payout account type" className="grid grid-cols-2 gap-2">
              {(["BANK", "UPI"] as const).map((t) => (
                <button
                  key={t}
                  type="button"
                  role="tab"
                  aria-selected={active === t}
                  onClick={() => {
                    setActive(t);
                    document.getElementById(t === "BANK" ? "payout-holder" : "payout-upi")?.focus();
                  }}
                  className={cn(
                    "flex h-11 items-center justify-center gap-2 rounded-lg border text-sm font-semibold transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#4817C2]",
                    active === t ? "border-[#4817C2] bg-[#F1EBFF] text-[#4817C2]" : "border-[#E5E1EF] bg-white text-[#171717] hover:border-[#4817C2]/50",
                  )}
                >
                  {t === "BANK" ? <Landmark className="h-4 w-4" aria-hidden="true" /> : <Smartphone className="h-4 w-4" aria-hidden="true" />}
                  {t === "BANK" ? "Bank Account" : "UPI"}
                </button>
              ))}
            </div>

            <div className="mt-4 space-y-4 rounded-xl border border-[#E5E1EF] p-4 sm:p-5" onFocusCapture={() => setActive("BANK")}>
              <Field id="payout-holder" label="Account Holder Name" required error={bankErrors.holder || undefined}>
                <SetupInput id="payout-holder" value={bank.holder} onChange={(e) => setBankField("holder", e.target.value)} placeholder="Enter account holder name" autoComplete="name" invalid={!!bankErrors.holder} maxLength={80} />
              </Field>
              <div className="grid gap-4 sm:grid-cols-2">
                <Field id="payout-bank" label="Bank Name" required error={bankErrors.bank || undefined}>
                  <SetupSelect id="payout-bank" value={bank.bank} onChange={(v) => setBankField("bank", v)} options={bankOptions} placeholder="Select bank" invalid={!!bankErrors.bank} />
                </Field>
                <Field id="payout-number" label="Account Number" required error={bankErrors.number || undefined}>
                  <SetupInput id="payout-number" value={bank.number} onChange={(e) => setBankField("number", e.target.value.replace(/\D/g, "").slice(0, 18))} placeholder="Enter account number" inputMode="numeric" autoComplete="off" invalid={!!bankErrors.number} />
                </Field>
              </div>
              <div className="grid gap-4 sm:grid-cols-[minmax(0,1fr)_auto] sm:items-end">
                <Field id="payout-ifsc" label="IFSC Code" required error={bankErrors.ifsc || undefined}>
                  <div className="flex gap-2">
                    <SetupInput id="payout-ifsc" value={bank.ifsc} onChange={(e) => onIfscChange(e.target.value)} placeholder="Enter IFSC code" autoCapitalize="characters" autoComplete="off" invalid={!!bankErrors.ifsc} className="uppercase" />
                    <button
                      type="button"
                      onClick={() => void findIfsc()}
                      disabled={finding}
                      className="flex h-11 shrink-0 items-center gap-1.5 rounded-lg border border-[#4817C2] bg-white px-3.5 text-sm font-semibold text-[#4817C2] hover:bg-[#F1EBFF] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#4817C2] disabled:opacity-60"
                    >
                      {finding ? <Loader2 className="h-4 w-4 animate-spin" aria-hidden="true" /> : <Search className="h-4 w-4" aria-hidden="true" />}
                      Find IFSC
                    </button>
                  </div>
                  {ifscNote && (
                    <p className={cn("mt-1.5 flex items-start gap-1.5 text-xs font-medium", ifscNote.ok ? "text-[#2E7D32]" : "text-[#B26A00]")}>
                      {ifscNote.ok ? <Check className="mt-px h-3.5 w-3.5 shrink-0" aria-hidden="true" /> : <Info className="mt-px h-3.5 w-3.5 shrink-0" aria-hidden="true" />}
                      {ifscNote.text}
                    </p>
                  )}
                </Field>
                <div>
                  <span id="payout-type-label" className="mb-1.5 block text-sm font-semibold leading-5">
                    Account Type<span className="ml-0.5 text-[#C62828]" aria-hidden="true">*</span>
                  </span>
                  <div role="radiogroup" aria-labelledby="payout-type-label" className="flex gap-2">
                    {(["SAVINGS", "CURRENT"] as const).map((t) => {
                      const on = bank.type === t;
                      return (
                        <button
                          key={t}
                          type="button"
                          role="radio"
                          aria-checked={on}
                          onClick={() => setBankField("type", t)}
                          className={cn(
                            "flex h-11 min-w-[112px] flex-1 items-center justify-center gap-2 rounded-lg border text-sm font-semibold focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#4817C2]",
                            on ? "border-[#4817C2] bg-[#F1EBFF] text-[#4817C2]" : "border-[#E5E1EF] bg-white text-[#171717] hover:border-[#4817C2]/50",
                          )}
                        >
                          <span className={cn("flex h-4 w-4 items-center justify-center rounded-full border", on ? "border-[#4817C2]" : "border-[#9A97A8]")}>
                            {on && <span className="h-2 w-2 rounded-full bg-[#4817C2]" />}
                          </span>
                          {t === "SAVINGS" ? "Savings" : "Current"}
                        </button>
                      );
                    })}
                  </div>
                </div>
              </div>
              <div className="flex justify-center pt-1">
                <button
                  type="button"
                  onClick={() => void addBank()}
                  disabled={addMethod.isPending}
                  className="flex h-11 items-center gap-2 rounded-lg bg-[#F1EBFF] px-6 text-sm font-semibold text-[#4817C2] hover:bg-[#E7DCFF] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#4817C2] disabled:opacity-60"
                >
                  {addMethod.isPending && active === "BANK" ? <Loader2 className="h-4 w-4 animate-spin" aria-hidden="true" /> : <Plus className="h-4 w-4" aria-hidden="true" />}
                  Add Bank Account
                </button>
              </div>
            </div>

            <div className="my-4 flex items-center gap-3" aria-hidden="true">
              <span className="h-px flex-1 bg-[#E5E1EF]" />
              <span className="rounded-full border border-[#E5E1EF] px-3 py-0.5 text-xs font-semibold text-[#666666]">OR</span>
              <span className="h-px flex-1 bg-[#E5E1EF]" />
            </div>

            <div className="rounded-xl bg-[#F7F3FF] p-4 sm:p-5" onFocusCapture={() => setActive("UPI")}>
              <Field id="payout-upi" label="UPI ID" required error={upiError || undefined}>
                <div className="flex flex-col gap-2 sm:flex-row">
                  <SetupInput
                    id="payout-upi"
                    value={upi}
                    onChange={(e) => {
                      setUpi(e.target.value);
                      setUpiError(null);
                    }}
                    placeholder="Enter UPI ID (e.g., name@okaxis)"
                    autoCapitalize="none"
                    autoComplete="off"
                    invalid={!!upiError}
                  />
                  <button
                    type="button"
                    onClick={() => void addUpi()}
                    disabled={addMethod.isPending}
                    className="flex h-11 shrink-0 items-center justify-center gap-2 rounded-lg bg-[#F1EBFF] px-5 text-sm font-semibold text-[#4817C2] ring-1 ring-[#E0D3FA] hover:bg-[#E7DCFF] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#4817C2] disabled:opacity-60"
                  >
                    {addMethod.isPending && active === "UPI" ? <Loader2 className="h-4 w-4 animate-spin" aria-hidden="true" /> : <Plus className="h-4 w-4" aria-hidden="true" />}
                    Add UPI
                  </button>
                </div>
              </Field>
            </div>

            <p className="mt-4 flex items-start gap-2 text-xs font-normal text-[#666666]">
              <Lock className="mt-0.5 h-3.5 w-3.5 shrink-0" aria-hidden="true" />
              Only you can add or change these details. Your full account number is stored securely and is only visible to GameAll&apos;s verification team.
            </p>

            <h3 className="mb-3 mt-6 flex items-center gap-2 text-base font-semibold">
              <ListChecks className="h-5 w-5 text-[#4817C2]" aria-hidden="true" />
              Added Payout Accounts
            </h3>
            {methods.isLoading ? (
              <Skeleton className="h-20 w-full rounded-xl" />
            ) : list.length === 0 ? (
              <p className="rounded-xl border border-dashed border-[#E5E1EF] p-5 text-center text-sm text-[#666666]">No payout account added yet. Add a bank account or UPI ID above.</p>
            ) : (
              <AccountsTable list={list} busy={busy} onPrimary={(m) => makePrimary.mutate(m.id)} onEdit={setEditing} onDelete={setRemoving} />
            )}
          </SetupCard>
        </div>

        {/* ── right: settlement ── */}
        <div className="min-w-0 space-y-5">
          <SetupCard>
            <CardHeading icon={<Settings className="h-6 w-6" aria-hidden="true" />} title="Settlement Settings" description="Configure how and when you receive your payouts." />
            <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-1 2xl:grid-cols-2">
              <Field id="payout-frequency" label="Settlement Frequency">
                <SetupSelect
                  id="payout-frequency"
                  value={settings.frequency}
                  onChange={(v) => set({ frequency: v as SettlementFrequency })}
                  options={FREQUENCY_OPTIONS.map((o) => ({ value: o.value, label: o.label }))}
                  icon={<Calendar className="h-4 w-4" aria-hidden="true" />}
                />
              </Field>
              <Field id="payout-min" label="Minimum Payout Amount">
                <SetupInput
                  id="payout-min"
                  value={String(settings.minimumPayoutInr)}
                  onChange={(e) => set({ minimumPayoutInr: Number(e.target.value.replace(/\D/g, "").slice(0, 7) || 0) })}
                  inputMode="numeric"
                  leading="₹"
                />
              </Field>
            </div>
            <p className="mt-4 flex items-start gap-2 rounded-lg bg-[#F1EBFF] px-3.5 py-3 text-[13px] font-normal text-[#4817C2]">
              <Info className="mt-0.5 h-4 w-4 shrink-0" aria-hidden="true" />
              <span>Payouts are processed to your selected account based on the selected frequency. {frequencyNote}</span>
            </p>
          </SetupCard>

          <SetupCard>
            <CardHeading icon={<Layers className="h-6 w-6" aria-hidden="true" />} title="Payout Sources" description="Choose which earnings should be included in your payouts." />
            <div className="space-y-4">
              <SwitchRow id="src-bookings" title="Booking Earnings" description="Court and slot bookings made by players." checked={settings.includeBookings} onChange={(v) => set({ includeBookings: v })} />
              <SwitchRow id="src-memberships" title="Membership Earnings" description="Payments for membership subscriptions (if enabled)." checked={settings.includeMemberships} onChange={(v) => set({ includeMemberships: v })} />
              <SwitchRow id="src-coaching" title="Coaching Earnings" description="Payments for coaching sessions (if enabled)." checked={settings.includeCoaching} onChange={(v) => set({ includeCoaching: v })} />
            </div>
          </SetupCard>

          <SetupCard>
            <CardHeading icon={<Wallet className="h-6 w-6" aria-hidden="true" />} title="Payout Rules" description="Additional settings for your payouts." />
            <div className="space-y-4">
              <SwitchRow id="rule-auto" title="Auto Payout" description="Automatically settle eligible earnings based on the settlement frequency." checked={settings.autoPayout} onChange={(v) => set({ autoPayout: v })} />
              <SwitchRow
                id="rule-hold"
                title="Hold Payout for Review"
                hint="Payouts wait until you approve them."
                description="Manually review and approve payouts before settlement."
                checked={settings.holdForReview}
                onChange={(v) => set({ holdForReview: v })}
              />
            </div>
          </SetupCard>
        </div>
      </div>

      <div className="flex flex-wrap items-center justify-between gap-3 border-t border-[#E5E1EF] pt-5">
        <button
          type="button"
          onClick={() => void persist(false)}
          disabled={saving !== null}
          className="flex h-12 items-center gap-2 rounded-lg border border-[#E5E1EF] bg-white px-5 text-sm font-semibold hover:bg-[#FBFAFE] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#4817C2] disabled:opacity-60"
        >
          {saving === "draft" ? <Loader2 className="h-4 w-4 animate-spin" aria-hidden="true" /> : <FileText className="h-4 w-4" aria-hidden="true" />}
          Save as Draft
        </button>
        <div className="flex items-center gap-3">
          <button
            type="button"
            onClick={() => router.push("/onboarding/pricing")}
            disabled={saving !== null}
            className="flex h-12 items-center gap-2 rounded-lg border border-[#E5E1EF] bg-white px-6 text-sm font-semibold hover:bg-[#FBFAFE] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#4817C2] disabled:opacity-60"
          >
            <ArrowLeft className="h-4 w-4" aria-hidden="true" />
            Back
          </button>
          <button
            type="button"
            onClick={() => void persist(true)}
            disabled={saving !== null || list.length === 0}
            className="flex h-12 min-w-[160px] items-center justify-center gap-2 rounded-lg bg-[#4817C2] px-7 text-sm font-semibold text-white transition-colors hover:bg-[#39109F] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#4817C2] focus-visible:ring-offset-2 disabled:opacity-60"
          >
            {saving === "complete" ? (
              <>
                <Loader2 className="h-4 w-4 animate-spin" aria-hidden="true" />
                Submitting…
              </>
            ) : (
              <>
                <Check className="h-4 w-4" aria-hidden="true" />
                Complete Setup
              </>
            )}
          </button>
        </div>
      </div>
      <p className="text-right text-xs font-normal text-[#666666]">GameAll reviews your whole setup before your dashboard opens. You&apos;ll be notified as soon as it&apos;s approved.</p>

      {editing && <MethodDialog key={editing.id} facilityId={facility.id} method={editing} onClose={() => setEditing(null)} />}
      <ConfirmDialog
        open={removing !== null}
        destructive
        title="Remove this payout account?"
        description="You can add it again any time."
        confirmLabel="Remove"
        busyLabel="Removing…"
        busy={remove.isPending}
        onConfirm={() => removing && remove.mutate(removing.id)}
        onCancel={() => setRemoving(null)}
      />
    </div>
  );
}

function friendly(e: unknown, fallback: string): string {
  const m = e instanceof Error ? e.message : "";
  // Our own validation / constraint messages are already written for people; anything else gets the fallback.
  if (/up to 5 payout accounts|already|required|Choose|Enter/i.test(m)) return m;
  if (/duplicate key|unique/i.test(m)) return "This account has already been added.";
  return fallback;
}

function SwitchRow({ id, title, description, hint, checked, onChange }: { id: string; title: string; description: string; hint?: string; checked: boolean; onChange: (v: boolean) => void }) {
  return (
    <div className="flex items-start gap-3">
      <Switch
        id={id}
        aria-labelledby={`${id}-title`}
        checked={checked}
        onCheckedChange={onChange}
        className="mt-0.5 h-7 w-12 shrink-0 border-0 data-[state=on]:bg-[#4817C2]"
        style={{ backgroundColor: checked ? "#4817C2" : "#C9C5D6" }}
      />
      <div className="min-w-0 flex-1">
        <p id={`${id}-title`} className="flex items-center gap-2 text-[15px] font-semibold leading-snug">
          {title}
          {hint && (
            <span title={hint} className="text-[#666666]">
              <Info className="h-4 w-4" aria-hidden="true" />
              <span className="sr-only">{hint}</span>
            </span>
          )}
        </p>
        <p className="mt-0.5 text-[13px] font-normal text-[#666666]">{description}</p>
      </div>
    </div>
  );
}

function AccountsTable({
  list,
  busy,
  onPrimary,
  onEdit,
  onDelete,
}: {
  list: PayoutMethod[];
  busy: boolean;
  onPrimary: (m: PayoutMethod) => void;
  onEdit: (m: PayoutMethod) => void;
  onDelete: (m: PayoutMethod) => void;
}) {
  const cols = "sm:grid-cols-[28px_minmax(0,1.1fr)_minmax(0,1.4fr)_minmax(0,1fr)_64px_84px]";
  return (
    <div className="overflow-hidden rounded-xl border border-[#E5E1EF]">
      <div className={cn("hidden items-center gap-3 border-b border-[#E5E1EF] bg-[#FBFAFE] px-4 py-2.5 text-xs font-semibold text-[#666666] sm:grid", cols)} aria-hidden="true">
        <span>#</span>
        <span>Payout Method</span>
        <span>Account Details</span>
        <span>Status</span>
        <span className="text-center">Primary</span>
        <span className="text-right">Actions</span>
      </div>
      <ul className="divide-y divide-[#E5E1EF]">
        {list.map((m, i) => {
          const Icon = m.type === "BANK" ? Landmark : Smartphone;
          return (
            <li key={m.id} className={cn("grid items-center gap-x-3 gap-y-2 px-4 py-3 text-sm", cols)}>
              <span className="hidden text-[#666666] sm:block">{i + 1}</span>
              <span className="flex items-center gap-2 font-semibold">
                <Icon className="h-4 w-4 shrink-0 text-[#4817C2]" aria-hidden="true" />
                {m.type === "BANK" ? "Bank Account" : "UPI"}
              </span>
              <span className="min-w-0 break-words text-[#171717]">
                {m.type === "BANK" ? (
                  <>
                    {m.bankName}
                    <span className="block text-xs text-[#666666]">
                      {m.accountType === "CURRENT" ? "Current" : "Savings"} · A/c No. {maskAccountNumber(m.accountLast4)}
                    </span>
                  </>
                ) : (
                  <>
                    {maskUpi(m.upiId)}
                    <span className="block text-xs text-[#666666]">{m.accountHolderName}</span>
                  </>
                )}
              </span>
              <span className="min-w-0">
                <VerificationBadge status={m.verification} />
              </span>
              <span className="flex items-center sm:justify-center">
                <button
                  type="button"
                  role="radio"
                  aria-checked={m.isPrimary}
                  aria-label={m.isPrimary ? "Primary account" : "Make this the primary account"}
                  disabled={busy || m.isPrimary}
                  onClick={() => onPrimary(m)}
                  className="flex h-5 w-5 items-center justify-center rounded-full border border-[#9A97A8] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#4817C2] aria-checked:border-[#4817C2]"
                >
                  {m.isPrimary && <span className="h-2.5 w-2.5 rounded-full bg-[#4817C2]" />}
                </button>
                <span className="ml-2 text-xs text-[#666666] sm:hidden">{m.isPrimary ? "Primary" : "Make primary"}</span>
              </span>
              <span className="flex items-center gap-2 sm:justify-end">
                <button
                  type="button"
                  disabled={busy}
                  onClick={() => onEdit(m)}
                  aria-label={`Edit ${m.type === "BANK" ? m.bankName : "UPI"} payout account`}
                  className="flex h-8 w-8 items-center justify-center rounded-lg border border-[#E0D3FA] text-[#4817C2] hover:bg-[#F1EBFF] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#4817C2]"
                >
                  <Pencil className="h-4 w-4" aria-hidden="true" />
                </button>
                <button
                  type="button"
                  disabled={busy}
                  onClick={() => onDelete(m)}
                  aria-label={`Remove ${m.type === "BANK" ? m.bankName : "UPI"} payout account`}
                  className="flex h-8 w-8 items-center justify-center rounded-lg border border-[#F3C9C9] text-[#C62828] hover:bg-[#FDECEC] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#C62828]"
                >
                  <Trash2 className="h-4 w-4" aria-hidden="true" />
                </button>
              </span>
            </li>
          );
        })}
      </ul>
    </div>
  );
}
