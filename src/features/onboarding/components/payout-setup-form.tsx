"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { Banknote, Lock, Plus, ShieldCheck } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { ConfirmDialog } from "@/components/shared/confirm-dialog";
import { FormMessage } from "@/features/auth/components/form-message";
import { SubmitButton } from "@/features/auth/components/submit-button";
import { useCurrentUser } from "@/features/auth/hooks/use-auth";
import { useFacility } from "@/features/facility/hooks/use-facility";
import { useOnboardingStore } from "@/features/onboarding/state/onboarding-store";
import { MethodCard, MethodDialog } from "@/features/profile/components/payment-methods-page";
import { profileKeys, usePayoutMethods } from "@/features/profile/hooks";
import type { PayoutMethod } from "@/features/profile/types";
import { getOnboardingService } from "@/services/onboarding";
import { getProfileService } from "@/services/profile";

/**
 * The last setup step before the dashboard: where should the facility's money be paid out? At least one bank account
 * or UPI ID is required. GameAll checks it by hand afterwards — the owner sees "Verification pending" until then — so
 * this step only needs it to be there.
 */
export function PayoutSetupForm() {
  const router = useRouter();
  const qc = useQueryClient();
  const { data: user } = useCurrentUser();
  const { data: facility, isLoading } = useFacility();
  const completePayments = useOnboardingStore((s) => s.completePayments);
  const isOwner = !!facility && facility.ownerId === user?.id;
  const methods = usePayoutMethods(facility?.id, isOwner);
  const [adding, setAdding] = useState(false);
  const [editing, setEditing] = useState<PayoutMethod | null>(null);
  const [removing, setRemoving] = useState<PayoutMethod | null>(null);
  const [error, setError] = useState<string | null>(null);

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
      setError(e instanceof Error ? e.message : "Could not remove this payment method.");
    },
  });
  const finish = useMutation({
    // Goes through the complete_facility_setup RPC (not a raw onboarding_step write) so profiles.onboarding_completed is
    // flipped in the same transaction — otherwise the next sign-in would send the owner back into onboarding.
    mutationFn: () => getOnboardingService().completeSetup(facility!.id),
    onSuccess: () => {
      completePayments();
      router.push("/onboarding/plan");
    },
    onError: () => setError("We couldn't finish your setup. Please try again."),
  });

  if (isLoading) return <Skeleton className="h-48 w-full rounded-xl" />;
  if (!facility) {
    router.replace("/onboarding/facility");
    return null;
  }
  if (!isOwner) return <FormMessage>You don&apos;t have access to this facility.</FormMessage>;

  const list = methods.data ?? [];

  return (
    <div className="space-y-6">
      {error && <FormMessage>{error}</FormMessage>}

      {methods.isLoading ? (
        <Skeleton className="h-24 w-full rounded-xl" />
      ) : list.length === 0 ? (
        <Card className="flex flex-col items-center gap-3 border-dashed px-6 py-12 text-center">
          <span className="flex h-12 w-12 items-center justify-center rounded-full bg-muted">
            <Banknote className="h-6 w-6 text-muted-foreground" aria-hidden />
          </span>
          <div>
            <p className="text-sm font-medium">Where should we send your payouts?</p>
            <p className="mt-1 max-w-sm text-sm text-muted-foreground">
              Add the bank account or UPI ID that receives what you collect for bookings and other payments.
            </p>
          </div>
          <Button type="button" onClick={() => setAdding(true)}>
            <Plus className="mr-1.5 h-4 w-4" aria-hidden /> Add payment method
          </Button>
        </Card>
      ) : (
        <div className="space-y-3">
          {list.map((m) => (
            <MethodCard
              key={m.id}
              method={m}
              busy={makePrimary.isPending || remove.isPending}
              onMakePrimary={() => {
                setError(null);
                makePrimary.mutate(m.id);
              }}
              onEdit={() => setEditing(m)}
              onDelete={() => setRemoving(m)}
            />
          ))}
          <Button type="button" variant="outline" size="sm" onClick={() => setAdding(true)}>
            <Plus className="mr-1.5 h-4 w-4" aria-hidden /> Add another
          </Button>
        </div>
      )}

      <div className="flex items-start gap-2 rounded-lg bg-muted/60 p-3 text-xs text-muted-foreground">
        <ShieldCheck className="mt-0.5 h-4 w-4 shrink-0 text-primary" aria-hidden />
        <p>
          We verify every payout method by hand before sending money to it — you&apos;ll see a Verified badge once it&apos;s
          done. Only you can see these details, and you can change them any time from Profile → Payment Methods.
        </p>
      </div>

      <div className="flex items-center justify-between gap-4">
        <p className="flex items-center gap-1.5 text-xs text-muted-foreground">
          <Lock className="h-3.5 w-3.5" aria-hidden /> Required to finish setup
        </p>
        <SubmitButton
          type="button"
          onClick={() => {
            setError(null);
            finish.mutate();
          }}
          pending={finish.isPending}
          disabled={list.length === 0}
          pendingLabel="Finishing…"
          className="w-auto sm:min-w-[10rem]"
        >
          Continue →
        </SubmitButton>
      </div>

      {adding && <MethodDialog facilityId={facility.id} onClose={() => setAdding(false)} />}
      {editing && <MethodDialog key={editing.id} facilityId={facility.id} method={editing} onClose={() => setEditing(null)} />}
      <ConfirmDialog
        open={removing !== null}
        destructive
        title="Remove this payment method?"
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
