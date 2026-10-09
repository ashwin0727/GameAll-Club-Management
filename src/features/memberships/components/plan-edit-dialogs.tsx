"use client";

import { useState } from "react";
import { Lock, Plus, X } from "lucide-react";
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { SelectField } from "@/components/shared/select-field";
import { PLAN_CATEGORIES } from "@/features/memberships/create-plan-wizard";
import { DAY_OPTIONS } from "@/features/memberships/slot-form";
import { formatClock } from "@/features/memberships/slot-format";
import { durationLabel } from "@/features/memberships/plan-insights";
import { validateSlotEdit, type PlanSlotDetail } from "@/features/memberships/plan-detail-data";
import { duplicatePlanMessage, type SlotShape } from "@/features/memberships/duplicate-guards";
import { getMembershipService } from "@/services/memberships";
import { getMembershipSessionService } from "@/services/membership-sessions";
import { ServiceError } from "@/services/shared/service-error";
import type { MembershipPlan } from "@/features/memberships/types";
import { cn } from "@/lib/utils";

const BTN_PRIMARY =
  "flex h-10 items-center justify-center gap-2 rounded-lg bg-[#0B7A55] px-5 text-sm font-semibold text-white transition-opacity hover:opacity-90 disabled:opacity-60 dark:bg-primary dark:text-primary-foreground";
const BTN_OUTLINE = "flex h-10 items-center justify-center rounded-lg border border-input bg-card px-4 text-sm font-medium transition-colors hover:bg-accent";

function Field({ label, error, children }: { label: string; error?: string | null; children: React.ReactNode }) {
  return (
    <div className="space-y-1.5">
      <p className="text-xs font-medium text-foreground/80">{label}</p>
      {children}
      {error && <p className="text-xs text-destructive">{error}</p>}
    </div>
  );
}

function Locked({ children }: { children: React.ReactNode }) {
  return (
    <div className="flex h-10 w-full items-center justify-between gap-2 rounded-lg border border-input bg-muted/40 px-3 text-sm text-muted-foreground">
      <span className="truncate">{children}</span>
      <Lock className="h-3.5 w-3.5 shrink-0" aria-label="Locked" />
    </div>
  );
}

const digits = (v: string, max: number) => v.replace(/\D/g, "").slice(0, max);

/**
 * Edit Plan. The name and duration are shown but locked — members may already be on the plan, so
 * what it is called and how long it runs stay as created. Everything else can change.
 */
export function EditPlanDialog({
  plan,
  otherNames = [],
  open,
  onOpenChange,
  onSaved,
}: {
  plan: MembershipPlan;
  /** The other plans' names — a plan can't be renamed to one that is already taken. */
  otherNames?: string[];
  open: boolean;
  onOpenChange: (open: boolean) => void;
  onSaved: (plan: MembershipPlan) => void;
}) {
  const [name, setName] = useState(plan.name);
  const [description, setDescription] = useState(plan.description ?? "");
  const [category, setCategory] = useState(plan.category ?? PLAN_CATEGORIES[0]!);
  const [joining, setJoining] = useState(plan.joiningFeeInr ? String(plan.joiningFeeInr) : "");
  const [deposit, setDeposit] = useState(plan.securityDepositInr ? String(plan.securityDepositInr) : "");
  const [showBadge, setShowBadge] = useState(Boolean(plan.badgeText?.trim()));
  const [badge, setBadge] = useState(plan.badgeText ?? "Popular");
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const categories = PLAN_CATEGORIES.includes(category) ? PLAN_CATEGORIES : [...PLAN_CATEGORIES, category];

  async function save() {
    const trimmed = name.trim();
    if (trimmed.length < 2) return setError("Plan name is required.");
    if (otherNames.some((n) => n.trim().toLowerCase() === trimmed.toLowerCase())) return setError("Another plan already has this name.");
    if (description.length > 200) return setError("Description can't be more than 200 characters.");
    setSaving(true);
    setError(null);
    try {
      const saved = await getMembershipService().updatePlan(plan.id, {
        name: trimmed,
        description: description.trim() || undefined,
        category,
        joiningFeeInr: joining ? Number(joining) : null,
        securityDepositInr: deposit ? Number(deposit) : null,
        badgeText: showBadge ? badge.trim() || "Popular" : null,
      });
      onSaved(saved);
      onOpenChange(false);
    } catch (err) {
      setError(err instanceof ServiceError ? err.message : "Unable to save this plan.");
    } finally {
      setSaving(false);
    }
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-lg">
        <DialogHeader>
          <DialogTitle>Edit Plan</DialogTitle>
          <DialogDescription>The price and duration can&apos;t be changed once a plan is created.</DialogDescription>
        </DialogHeader>
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
          <Field label="Plan Name">
            <Input value={name} onChange={(e) => setName(e.target.value.slice(0, 60))} />
          </Field>
          <Field label="Duration">
            <Locked>{durationLabel(plan.durationDays)}</Locked>
          </Field>
        </div>
        <Field label={`Description (${description.length}/200)`}>
          <textarea
            value={description}
            onChange={(e) => setDescription(e.target.value.slice(0, 200))}
            rows={2}
            className="flex w-full rounded-md border border-input bg-transparent px-3 py-2 text-sm shadow-sm outline-none transition-colors focus-visible:border-foreground/40"
          />
        </Field>
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
          <Field label="Plan Category">
            <SelectField
              ariaLabel="Plan category"
              value={category}
              onValueChange={setCategory}
              options={categories.map((c) => ({ value: c, label: c }))}
              className="h-10 w-full rounded-lg border border-input bg-card px-3 text-sm outline-none transition-colors hover:border-foreground/30"
            />
          </Field>
          <Field label="Price (₹)">
            <Locked>{plan.priceInr.toLocaleString("en-IN")}</Locked>
          </Field>
          <Field label="Joining Fee (₹)">
            <Input value={joining} onChange={(e) => setJoining(digits(e.target.value, 7))} inputMode="numeric" placeholder="0" />
          </Field>
          <Field label="Security Deposit (₹)">
            <Input value={deposit} onChange={(e) => setDeposit(digits(e.target.value, 7))} inputMode="numeric" placeholder="0" />
          </Field>
        </div>
        <div className="flex flex-wrap items-center gap-3">
          <label className="flex items-center gap-2 text-sm">
            <input type="checkbox" checked={showBadge} onChange={(e) => setShowBadge(e.target.checked)} className="h-4 w-4 accent-[#0B7A55]" />
            Show a badge on this plan
          </label>
          {showBadge && <Input value={badge} onChange={(e) => setBadge(e.target.value.slice(0, 20))} className="h-9 w-40" aria-label="Badge text" />}
        </div>
        {error && <p className="text-sm text-destructive">{error}</p>}
        <div className="flex justify-end gap-3">
          <button type="button" className={BTN_OUTLINE} onClick={() => onOpenChange(false)}>
            Cancel
          </button>
          <button type="button" className={BTN_PRIMARY} disabled={saving} onClick={save}>
            {saving ? "Saving…" : "Save Changes"}
          </button>
        </div>
      </DialogContent>
    </Dialog>
  );
}

/** Add or remove the benefits the plan lists. */
export function EditBenefitsDialog({
  plan,
  open,
  onOpenChange,
  onSaved,
}: {
  plan: MembershipPlan;
  open: boolean;
  onOpenChange: (open: boolean) => void;
  onSaved: (plan: MembershipPlan) => void;
}) {
  const [features, setFeatures] = useState<string[]>(plan.features);
  const [draft, setDraft] = useState("");
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  function add() {
    const t = draft.trim();
    if (!t) return features;
    const next = features.includes(t) ? features : [...features, t];
    setFeatures(next);
    setDraft("");
    return next;
  }

  async function save() {
    // A half-typed benefit still in the box is kept rather than silently dropped.
    const next = draft.trim() ? add() : features;
    setSaving(true);
    setError(null);
    try {
      const saved = await getMembershipService().updatePlan(plan.id, { features: next.map((f) => f.trim()).filter(Boolean) });
      onSaved(saved);
      onOpenChange(false);
    } catch (err) {
      setError(err instanceof ServiceError ? err.message : "Unable to save the benefits.");
    } finally {
      setSaving(false);
    }
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-md">
        <DialogHeader>
          <DialogTitle>Edit Benefits</DialogTitle>
          <DialogDescription>What members get with this plan.</DialogDescription>
        </DialogHeader>
        <ul className="space-y-2">
          {features.length === 0 && <li className="text-sm text-muted-foreground">No benefits yet.</li>}
          {features.map((f) => (
            <li key={f} className="flex items-center justify-between gap-2 rounded-lg border border-border px-3 py-2 text-sm">
              <span>{f}</span>
              <button type="button" aria-label={`Remove ${f}`} onClick={() => setFeatures(features.filter((x) => x !== f))} className="text-muted-foreground hover:text-destructive">
                <X className="h-4 w-4" />
              </button>
            </li>
          ))}
        </ul>
        <div className="flex gap-2">
          <Input
            value={draft}
            onChange={(e) => setDraft(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === "Enter") {
                e.preventDefault();
                add();
              }
            }}
            placeholder="Add a benefit, e.g. Free locker"
          />
          <button type="button" className={BTN_OUTLINE} onClick={add} aria-label="Add benefit">
            <Plus className="h-4 w-4" />
          </button>
        </div>
        {error && <p className="text-sm text-destructive">{error}</p>}
        <div className="flex justify-end gap-3">
          <button type="button" className={BTN_OUTLINE} onClick={() => onOpenChange(false)}>
            Cancel
          </button>
          <button type="button" className={BTN_PRIMARY} disabled={saving} onClick={save}>
            {saving ? "Saving…" : "Save Changes"}
          </button>
        </div>
      </DialogContent>
    </Dialog>
  );
}

/**
 * Edit the plan's slots. With `capacityOnly` (the Slot Configuration row) just the capacity changes;
 * otherwise each slot's court, days, hours and capacity can. Saving updates the slot itself, so
 * every member on it sees the change.
 */
export function EditSlotsDialog({
  slots,
  courts,
  capacityOnly = false,
  findDuplicate,
  open,
  onOpenChange,
  onSaved,
}: {
  slots: PlanSlotDetail[];
  /** Name of another plan whose slots would be identical to these, or null. */
  findDuplicate?: (slots: SlotShape[]) => string | null;
  /** Active courts, each with the sport it belongs to — a slot can only move within its own sport. */
  courts: { id: string; name: string; facilitySportId: string }[];
  capacityOnly?: boolean;
  open: boolean;
  onOpenChange: (open: boolean) => void;
  onSaved: () => void;
}) {
  const [drafts, setDrafts] = useState(() =>
    slots.map((s) => ({
      batchId: s.batchId,
      courtId: s.courtId,
      days: s.daysOfWeek,
      start: s.startTime,
      end: s.endTime,
      capacity: String(s.capacity),
    })),
  );
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const update = (i: number, patch: Partial<(typeof drafts)[number]>) => setDrafts((d) => d.map((x, j) => (j === i ? { ...x, ...patch } : x)));

  async function save() {
    for (const [i, d] of drafts.entries()) {
      const msg = validateSlotEdit({
        days: d.days,
        startTime: d.start,
        endTime: d.end,
        capacity: d.capacity ? Number(d.capacity) : null,
        enrolled: slots[i]!.enrolledCount,
      });
      if (msg) return setError(slots.length > 1 ? `${slots[i]!.courtName} ${formatClock(slots[i]!.startTime)}: ${msg}` : msg);
    }
    const clash = findDuplicate?.(drafts.map((d) => ({ courtId: d.courtId, daysOfWeek: d.days, startTime: d.start, endTime: d.end })));
    if (clash) return setError(duplicatePlanMessage(clash));
    setSaving(true);
    setError(null);
    try {
      for (const [i, d] of drafts.entries()) {
        const s = slots[i]!;
        const changed =
          d.courtId !== s.courtId ||
          d.start !== s.startTime ||
          d.end !== s.endTime ||
          Number(d.capacity) !== s.capacity ||
          [...d.days].sort().join() !== [...s.daysOfWeek].sort().join();
        if (!changed) continue;
        await getMembershipSessionService().updateBatch(
          d.batchId,
          capacityOnly
            ? { capacity: Number(d.capacity) }
            : { courtId: d.courtId, daysOfWeek: [...d.days].sort(), startTime: d.start, endTime: d.end, capacity: Number(d.capacity) },
        );
      }
      onSaved();
      onOpenChange(false);
    } catch (err) {
      setError(err instanceof ServiceError ? err.message : "Unable to save the slots.");
    } finally {
      setSaving(false);
    }
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-h-[85vh] max-w-xl overflow-y-auto">
        <DialogHeader>
          <DialogTitle>{capacityOnly ? "Edit Slot Settings" : "Edit Slots"}</DialogTitle>
          <DialogDescription>
            {capacityOnly ? "Update how many members each slot can hold." : "Change the court, days or hours of this plan's slots."}
          </DialogDescription>
        </DialogHeader>
        {drafts.map((d, i) => {
          const s = slots[i]!;
          const sportCourts = courts.filter((c) => c.facilitySportId === s.facilitySportId);
          return (
            <div key={d.batchId} className="space-y-3 rounded-xl border border-border p-4">
              {capacityOnly || slots.length > 1 ? (
                <p className="text-sm font-semibold">
                  {s.courtName} · {formatClock(s.startTime)} - {formatClock(s.endTime)}
                </p>
              ) : null}
              {!capacityOnly && (
                <>
                  <Field label="Court">
                    <SelectField
                      ariaLabel="Court"
                      value={d.courtId}
                      onValueChange={(v) => update(i, { courtId: v })}
                      options={(sportCourts.length ? sportCourts : [{ id: s.courtId, name: s.courtName }]).map((c) => ({ value: c.id, label: c.name }))}
                      className="h-10 w-full rounded-lg border border-input bg-card px-3 text-sm outline-none transition-colors hover:border-foreground/30"
                    />
                  </Field>
                  <Field label="Days">
                    <div className="flex flex-wrap gap-1.5">
                      {DAY_OPTIONS.map((o) => {
                        const on = d.days.includes(o.value);
                        return (
                          <button
                            key={o.value}
                            type="button"
                            aria-pressed={on}
                            onClick={() => update(i, { days: on ? d.days.filter((x) => x !== o.value) : [...d.days, o.value] })}
                            className={cn(
                              "rounded-lg px-3 py-1.5 text-xs font-medium transition-colors",
                              on ? "bg-[#0B9B63] text-white" : "bg-muted text-muted-foreground hover:bg-accent",
                            )}
                          >
                            {o.label}
                          </button>
                        );
                      })}
                    </div>
                  </Field>
                  <div className="grid grid-cols-2 gap-3">
                    <Field label="Start time">
                      <Input type="time" value={d.start} onChange={(e) => update(i, { start: e.target.value })} />
                    </Field>
                    <Field label="End time">
                      <Input type="time" value={d.end} onChange={(e) => update(i, { end: e.target.value })} />
                    </Field>
                  </div>
                </>
              )}
              <Field label={s.enrolledCount > 0 ? `Slot capacity (${s.enrolledCount} already on it)` : "Slot capacity"}>
                <Input value={d.capacity} onChange={(e) => update(i, { capacity: digits(e.target.value, 4) })} inputMode="numeric" />
              </Field>
            </div>
          );
        })}
        {error && <p className="text-sm text-destructive">{error}</p>}
        <div className="flex justify-end gap-3">
          <button type="button" className={BTN_OUTLINE} onClick={() => onOpenChange(false)}>
            Cancel
          </button>
          <button type="button" className={BTN_PRIMARY} disabled={saving} onClick={save}>
            {saving ? "Saving…" : "Save Changes"}
          </button>
        </div>
      </DialogContent>
    </Dialog>
  );
}
