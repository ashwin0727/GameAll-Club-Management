"use client";

import { useState } from "react";
import { toast } from "sonner";
import { ConfirmDialog } from "@/components/shared/confirm-dialog";
import { isAutoPayLive } from "@/features/memberships/autopay";
import { getMembershipService } from "@/services/memberships";
import { ServiceError } from "@/services/shared/service-error";

export interface DeleteMemberTarget {
  memberId: string;
  name: string;
  /** The membership whose AutoPay may need cancelling first. Null when there is none to look at. */
  membershipId: string | null;
}

/**
 * Delete Member, in the order the owner expects:
 *   1. "Delete member?" — confirm;
 *   2. if AutoPay is still running, a second modal asks to cancel AutoPay — confirming cancels AutoPay AND the
 *      membership but does NOT delete the member (a toast says so);
 *   3. choosing Delete again (AutoPay now stopped) deletes the member.
 * Returns `start(target)` and the `dialogs` to render; `onDeleted` runs after a delete, `onChanged` after the
 * AutoPay + membership were cancelled.
 */
export function useDeleteMemberFlow({ onDeleted, onChanged }: { onDeleted: () => void; onChanged: () => void }) {
  const [target, setTarget] = useState<DeleteMemberTarget | null>(null);
  const [stage, setStage] = useState<"delete" | "autopay" | null>(null);
  const [busy, setBusy] = useState(false);

  function close() {
    setStage(null);
    setTarget(null);
  }

  async function confirmDelete() {
    if (!target) return;
    setBusy(true);
    try {
      const autoPay = target.membershipId ? await getMembershipService().getMembershipAutoPay(target.membershipId).catch(() => null) : null;
      if (autoPay && isAutoPayLive(autoPay)) {
        setStage("autopay");
        return;
      }
      await getMembershipService().deleteMember(target.memberId);
      toast.success("Member Deleted Successfully", { description: `${target.name} was removed.` });
      close();
      onDeleted();
    } catch (e) {
      toast.error(e instanceof ServiceError ? e.message : "Unable to delete this member.");
      close();
    } finally {
      setBusy(false);
    }
  }

  async function confirmCancelAutoPay() {
    if (!target?.membershipId) return;
    setBusy(true);
    try {
      await getMembershipService().cancelMembershipSubscription(target.membershipId);
      await getMembershipService().cancelMembership(target.membershipId);
      toast.success("AutoPay and membership cancelled", {
        description: `${target.name} was not deleted. Choose Delete Member again to remove them.`,
      });
      close();
      onChanged();
    } catch (e) {
      toast.error(e instanceof ServiceError ? e.message : "Unable to cancel AutoPay.");
    } finally {
      setBusy(false);
    }
  }

  const dialogs = (
    <>
      <ConfirmDialog
        open={stage === "delete"}
        destructive
        busy={busy}
        title="Delete Member"
        description={
          <>
            Do you want to proceed with deleting <span className="font-semibold text-foreground">{target?.name}</span>? Their memberships and bookings will be
            removed. Payments already received stay in Finance. This can&apos;t be undone.
          </>
        }
        confirmLabel="Yes, Delete"
        busyLabel="Checking…"
        onConfirm={() => void confirmDelete()}
        onCancel={close}
      />
      <ConfirmDialog
        open={stage === "autopay"}
        destructive
        busy={busy}
        title="Cancel AutoPay?"
        description={
          <>
            <span className="font-semibold text-foreground">{target?.name}</span> has AutoPay running, so they can&apos;t be deleted yet. Cancelling stops all
            future charges and cancels their membership — the member is <span className="font-semibold text-foreground">not</span> deleted. You can delete
            them afterwards.
          </>
        }
        confirmLabel="Cancel AutoPay"
        cancelLabel="Keep AutoPay"
        busyLabel="Cancelling…"
        onConfirm={() => void confirmCancelAutoPay()}
        onCancel={close}
      />
    </>
  );

  return { start: (t: DeleteMemberTarget) => { setTarget(t); setStage("delete"); }, dialogs };
}
