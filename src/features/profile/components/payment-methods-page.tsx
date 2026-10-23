"use client";

import { useState } from "react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { BadgeCheck, Banknote, CheckCircle2, Clock, Landmark, Lock, Pencil, Plus, Smartphone, Trash2, XCircle } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Skeleton } from "@/components/ui/skeleton";
import { ConfirmDialog } from "@/components/shared/confirm-dialog";
import { useCurrentUser } from "@/features/auth/hooks/use-auth";
import { useFacility } from "@/features/facility/hooks/use-facility";
import { profileKeys, usePayoutMethods } from "@/features/profile/hooks";
import { maskAccountNumber, maskUpi, payoutSchema } from "@/features/profile/payout-validation";
import { PageMessage, SubPageHeader } from "@/features/profile/components/profile-shared";
import type { PayoutMethod, PayoutMethodType, PayoutVerification } from "@/features/profile/types";
import { getProfileService } from "@/services/profile";
import { cn } from "@/lib/utils";
import { EditOnly } from "@/features/access/edit-only";

const VERIFICATION: Record<PayoutVerification, { label: string; icon: React.ComponentType<{ className?: string }>; className: string }> = {
  VERIFIED: { label: "Verified", icon: BadgeCheck, className: "bg-success/15 text-success" },
  PENDING: { label: "Verification pending", icon: Clock, className: "bg-warning/20 text-warning-foreground" },
  REJECTED: { label: "Couldn't verify", icon: XCircle, className: "bg-destructive/15 text-destructive" },
};

function VerificationBadge({ status }: { status: PayoutVerification }) {
  const v = VERIFICATION[status];
  const Icon = v.icon;
  return (
    <span className={cn("inline-flex items-center gap-1 rounded-full px-2.5 py-0.5 text-xs font-semibold", v.className)}>
      <Icon className="h-3.5 w-3.5" aria-hidden /> {v.label}
    </span>
  );
}

function formatVerifiedOn(iso: string): string {
  return new Date(iso).toLocaleDateString("en-IN", { day: "numeric", month: "short", year: "numeric" });
}

export function MethodCard({
  method,
  busy,
  onMakePrimary,
  onEdit,
  onDelete,
}: {
  method: PayoutMethod;
  busy: boolean;
  onMakePrimary: () => void;
  onEdit: () => void;
  onDelete: () => void;
}) {
  const Icon = method.type === "BANK" ? Landmark : Smartphone;
  return (
    <Card className={cn("flex flex-wrap items-center gap-3 p-4", method.isPrimary && "border-primary/40")}>
      <span className="flex h-11 w-11 shrink-0 items-center justify-center rounded-xl bg-primary/10 text-primary">
        <Icon className="h-5 w-5" aria-hidden />
      </span>
      <div className="min-w-0 flex-1">
        <p className="flex flex-wrap items-center gap-2 text-sm font-semibold">
          {method.type === "BANK" ? method.bankName : "UPI"}
          {method.isPrimary && (
            <Badge variant="success" className="bg-success/15 text-success">
              Primary
            </Badge>
          )}
          <VerificationBadge status={method.verification} />
        </p>
        <p className="truncate text-sm text-muted-foreground">
          {method.type === "BANK"
            ? `${maskAccountNumber(method.accountNumber)} · ${method.ifsc}`
            : maskUpi(method.upiId)}
        </p>
        <p className="truncate text-xs text-muted-foreground">{method.accountHolderName}</p>
        {method.verification === "VERIFIED" && method.verifiedAt && (
          <p className="mt-1 text-xs text-muted-foreground">Verified on {formatVerifiedOn(method.verifiedAt)}</p>
        )}
        {method.verification === "PENDING" && (
          <p className="mt-1 text-xs text-muted-foreground">
            We check every payment method by hand before sending money to it. You&apos;ll see a Verified badge here once it&apos;s done.
          </p>
        )}
        {method.verification === "REJECTED" && (
          <p className="mt-1 text-xs text-destructive">
            {method.verificationNote || "We couldn't verify these details."} Edit them and we&apos;ll check again.
          </p>
        )}
      </div>
      <div className="flex gap-2">
        {!method.isPrimary && (
          <EditOnly>
            <Button type="button" variant="outline" size="sm" disabled={busy} onClick={onMakePrimary}>
              Make primary
            </Button>
          </EditOnly>
        )}
        <EditOnly>
          <Button type="button" variant="ghost" size="icon" disabled={busy} onClick={onEdit} aria-label="Edit payment method">
            <Pencil className="h-4 w-4" aria-hidden />
          </Button>
        </EditOnly>
        <EditOnly>
          <Button
            type="button"
            variant="ghost"
            size="icon"
            className="text-muted-foreground hover:text-destructive"
            disabled={busy}
            onClick={onDelete}
            aria-label={`Remove ${method.type === "BANK" ? method.bankName : "UPI"} payment method`}
          >
            <Trash2 className="h-4 w-4" aria-hidden />
          </Button>
        </EditOnly>
      </div>
    </Card>
  );
}

type Fields = { accountHolderName: string; bankName: string; accountNumber: string; ifsc: string; upiId: string };
const EMPTY: Fields = { accountHolderName: "", bankName: "", accountNumber: "", ifsc: "", upiId: "" };

export function MethodDialog({ facilityId, method, onClose }: { facilityId: string; method?: PayoutMethod; onClose: () => void }) {
  const qc = useQueryClient();
  const [type, setType] = useState<PayoutMethodType>(method?.type ?? "BANK");
  const [f, setF] = useState<Fields>(
    method
      ? {
          accountHolderName: method.accountHolderName,
          bankName: method.bankName ?? "",
          accountNumber: method.accountNumber ?? "",
          ifsc: method.ifsc ?? "",
          upiId: method.upiId ?? "",
        }
      : EMPTY,
  );
  const [errors, setErrors] = useState<Record<string, string>>({});

  const add = useMutation({
    mutationFn: (input: Parameters<ReturnType<typeof getProfileService>["addPayoutMethod"]>[1]) =>
      method ? getProfileService().updatePayoutMethod(method.id, input) : getProfileService().addPayoutMethod(facilityId, input),
    onSuccess: async () => {
      await qc.invalidateQueries({ queryKey: profileKeys.payouts(facilityId) });
      onClose();
    },
    onError: (e) => setErrors({ form: e instanceof Error ? e.message : "Could not save this payment method." }),
  });

  function set<K extends keyof Fields>(k: K, v: string) {
    setF((p) => ({ ...p, [k]: v }));
  }

  function submit(e: React.FormEvent) {
    e.preventDefault();
    const parsed = payoutSchema.safeParse(
      type === "BANK"
        ? { type, accountHolderName: f.accountHolderName, bankName: f.bankName, accountNumber: f.accountNumber, ifsc: f.ifsc }
        : { type, accountHolderName: f.accountHolderName, upiId: f.upiId },
    );
    if (!parsed.success) {
      const next: Record<string, string> = {};
      for (const issue of parsed.error.issues) next[String(issue.path[0])] ??= issue.message;
      return setErrors(next);
    }
    setErrors({});
    add.mutate(parsed.data);
  }

  const field = (id: keyof Fields, label: string, placeholder: string, extra: React.InputHTMLAttributes<HTMLInputElement> = {}) => (
    <div className="space-y-1.5">
      <Label htmlFor={`payout-${id}`}>{label}</Label>
      <Input id={`payout-${id}`} value={f[id]} onChange={(e) => set(id, e.target.value)} placeholder={placeholder} {...extra} />
      {errors[id] && <p className="text-xs text-destructive">{errors[id]}</p>}
    </div>
  );

  return (
    <Dialog open onOpenChange={(o) => !o && !add.isPending && onClose()}>
      <DialogContent className="max-w-md">
        <form onSubmit={submit} className="space-y-4" noValidate>
          <DialogHeader>
            <DialogTitle>{method ? "Edit payment method" : "Add a payment method"}</DialogTitle>
            <DialogDescription>
              {method
                ? "Changing these details sends the method back for verification."
                : "Where should we send the money you collect for bookings and other payments? We'll verify it by hand before the first payout."}
            </DialogDescription>
          </DialogHeader>

          <div role="tablist" aria-label="Payment method type" className="grid grid-cols-2 gap-1 rounded-lg bg-muted p-1 text-sm">
            {(["BANK", "UPI"] as const).map((t) => (
              <button
                key={t}
                type="button"
                role="tab"
                aria-selected={type === t}
                onClick={() => {
                  setType(t);
                  setErrors({});
                }}
                className={cn(
                  "rounded-md py-1.5 font-medium transition-colors",
                  type === t ? "bg-card shadow-sm" : "text-muted-foreground hover:text-foreground",
                )}
              >
                {t === "BANK" ? "Bank account" : "UPI"}
              </button>
            ))}
          </div>

          {field("accountHolderName", "Account holder name", "As it appears on the account", { autoComplete: "name" })}
          {type === "BANK" ? (
            <>
              {field("bankName", "Bank name", "e.g. HDFC Bank")}
              {field("accountNumber", "Account number", "9 to 18 digits", { inputMode: "numeric", autoComplete: "off" })}
              {field("ifsc", "IFSC code", "e.g. HDFC0001234", { autoCapitalize: "characters", autoComplete: "off" })}
            </>
          ) : (
            field("upiId", "UPI ID", "name@bank", { autoCapitalize: "none", autoComplete: "off" })
          )}

          <p className="flex items-start gap-2 text-xs text-muted-foreground">
            <Lock className="mt-0.5 h-3.5 w-3.5 shrink-0" aria-hidden />
            Only you, the facility owner, can see or change these details.
          </p>
          {errors.form && (
            <p role="alert" className="text-sm text-destructive">
              {errors.form}
            </p>
          )}
          <DialogFooter>
            <Button type="button" variant="outline" onClick={onClose} disabled={add.isPending}>
              Cancel
            </Button>
            <Button type="submit" disabled={add.isPending}>
              {add.isPending ? "Saving…" : method ? "Save changes" : "Save payment method"}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}

/** Payment Methods: the bank account or UPI ID the facility's money is paid out to. Owner only. */
export function PaymentMethodsPage() {
  const qc = useQueryClient();
  const { data: user } = useCurrentUser();
  const { data: facility, isLoading: facilityLoading } = useFacility();
  const isOwner = !!facility && facility.ownerId === user?.id;
  const methods = usePayoutMethods(facility?.id, isOwner);
  const [adding, setAdding] = useState(false);
  const [editing, setEditing] = useState<PayoutMethod | null>(null);
  const [removing, setRemoving] = useState<PayoutMethod | null>(null);
  const [actionError, setActionError] = useState<string | null>(null);

  const refresh = () => qc.invalidateQueries({ queryKey: profileKeys.payouts(facility?.id ?? "") });
  const makePrimary = useMutation({
    mutationFn: (id: string) => getProfileService().setPrimaryPayoutMethod(id),
    onSuccess: refresh,
    onError: (e) => setActionError(e instanceof Error ? e.message : "Could not change the primary method."),
  });
  const remove = useMutation({
    mutationFn: (id: string) => getProfileService().deletePayoutMethod(id),
    onSuccess: async () => {
      await refresh();
      setRemoving(null);
    },
    onError: (e) => {
      setRemoving(null);
      setActionError(e instanceof Error ? e.message : "Could not remove this payment method.");
    },
  });

  const header = (
    <SubPageHeader
      title="Payment Methods"
      description="Where the money you collect for bookings and other payments is paid out to."
      action={
        isOwner && (
          <EditOnly>
            <Button type="button" onClick={() => setAdding(true)}>
              <Plus className="mr-1.5 h-4 w-4" aria-hidden /> Add method
            </Button>
          </EditOnly>
        )
      }
    />
  );

  if (facilityLoading) {
    return (
      <div className="space-y-4">
        {header}
        <Skeleton className="h-24 w-full rounded-xl" />
      </div>
    );
  }
  if (!facility) {
    return (
      <div className="space-y-4">
        {header}
        <PageMessage>No facility is set up for this account yet.</PageMessage>
      </div>
    );
  }
  if (!isOwner) {
    return (
      <div className="space-y-4">
        {header}
        <Card className="flex items-start gap-3 p-5 text-sm text-muted-foreground">
          <Lock className="mt-0.5 h-4 w-4 shrink-0" aria-hidden />
          Payout details are managed by the facility owner.
        </Card>
      </div>
    );
  }

  const list = methods.data ?? [];
  return (
    <div className="space-y-4">
      {header}

      {actionError && (
        <p role="alert" className="rounded-lg bg-destructive/10 px-3 py-2 text-sm text-destructive">
          {actionError}
        </p>
      )}

      {methods.isLoading ? (
        <Skeleton className="h-24 w-full rounded-xl" />
      ) : methods.isError ? (
        <PageMessage tone="error">Unable to load your payment methods. Please try again.</PageMessage>
      ) : list.length === 0 ? (
        <Card className="flex flex-col items-center gap-3 border-dashed px-6 py-12 text-center">
          <span className="flex h-12 w-12 items-center justify-center rounded-full bg-muted">
            <Banknote className="h-6 w-6 text-muted-foreground" aria-hidden />
          </span>
          <div>
            <p className="text-sm font-medium">No payment method yet</p>
            <p className="mt-1 max-w-sm text-sm text-muted-foreground">
              Add a bank account or UPI ID so we know where to pay out what you collect.
            </p>
          </div>
          <EditOnly>
            <Button type="button" onClick={() => setAdding(true)}>
              <Plus className="mr-1.5 h-4 w-4" aria-hidden /> Add payment method
            </Button>
          </EditOnly>
        </Card>
      ) : (
        <div className="space-y-3">
          {list.map((m) => (
            <MethodCard
              key={m.id}
              method={m}
              busy={makePrimary.isPending || remove.isPending}
              onEdit={() => {
                setActionError(null);
                setEditing(m);
              }}
              onMakePrimary={() => {
                setActionError(null);
                makePrimary.mutate(m.id);
              }}
              onDelete={() => {
                setActionError(null);
                setRemoving(m);
              }}
            />
          ))}
          <p className="flex items-center gap-2 text-xs text-muted-foreground">
            <CheckCircle2 className="h-3.5 w-3.5 text-primary" aria-hidden />
            Account numbers are masked here and visible only to you. Payouts go to your primary method once it is verified.
          </p>
        </div>
      )}

      {adding && <MethodDialog facilityId={facility.id} onClose={() => setAdding(false)} />}
      {editing && <MethodDialog key={editing.id} facilityId={facility.id} method={editing} onClose={() => setEditing(null)} />}
      <ConfirmDialog
        open={removing !== null}
        destructive
        title="Remove this payment method?"
        description={
          removing?.isPrimary && list.length > 1
            ? "This is where payouts currently go. Make another method primary afterwards so payouts aren't held up."
            : "You can add it again any time."
        }
        confirmLabel="Remove"
        busyLabel="Removing…"
        busy={remove.isPending}
        onConfirm={() => removing && remove.mutate(removing.id)}
        onCancel={() => setRemoving(null)}
      />
    </div>
  );
}
