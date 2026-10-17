"use client";

import { useState } from "react";
import { toast } from "sonner";
import { ConfirmDialog } from "@/components/shared/confirm-dialog";
import { getCoachingService } from "@/services/coaching";
import { ServiceError } from "@/services/shared/service-error";
import type { BillingStatus } from "@/features/coaching/types";

const LIVE_BILLING: BillingStatus[] = ["CREATED", "AUTHENTICATED", "ACTIVE", "PENDING", "HALTED"];

export interface DeleteStudentTarget {
  enrollmentId: string;
  studentName: string;
  programName: string;
  status: string;
  /** Money received so far, in minor units. */
  paidMinor: number;
}

/**
 * Delete Student, in the order the owner expects:
 *   1. "Delete student?" — confirm;
 *   2. if online payment / AutoPay is live, or money was received and coaching is still on, a second modal asks to
 *      cancel coaching (and AutoPay) — confirming cancels but does NOT delete the student (a toast says so);
 *   3. choosing Delete again deletes the student.
 */
export function useDeleteStudentFlow({ onDeleted, onChanged }: { onDeleted: () => void; onChanged: () => void }) {
  const [target, setTarget] = useState<DeleteStudentTarget | null>(null);
  const [stage, setStage] = useState<"delete" | "cancel" | null>(null);
  const [busy, setBusy] = useState(false);

  function close() {
    setStage(null);
    setTarget(null);
  }

  async function confirmDelete() {
    if (!target) return;
    setBusy(true);
    try {
      const billing = await getCoachingService().getEnrollmentBilling(target.enrollmentId).catch(() => null);
      const liveBilling = billing != null && LIVE_BILLING.includes(billing.status);
      const cancelled = target.status === "CANCELLED";
      if (!cancelled && (liveBilling || target.paidMinor > 0)) {
        setStage("cancel");
        return;
      }
      // Already cancelled but a link / AutoPay is somehow still live: stop it, then delete.
      if (liveBilling) await getCoachingService().cancelEnrollmentBilling(target.enrollmentId);
      await getCoachingService().deleteEnrollment(target.enrollmentId);
      toast.success("Student Deleted Successfully", { description: `${target.studentName} was removed from ${target.programName}.` });
      close();
      onDeleted();
    } catch (e) {
      toast.error(e instanceof ServiceError ? e.message : "Unable to delete this student.");
      close();
    } finally {
      setBusy(false);
    }
  }

  async function confirmCancelCoaching() {
    if (!target) return;
    setBusy(true);
    try {
      await getCoachingService().setEnrollmentStatus(target.enrollmentId, "CANCELLED", "Cancelled before deleting the student");
      toast.success("Coaching and AutoPay cancelled", {
        description: `${target.studentName} was not deleted. Choose Delete Student again to remove them.`,
      });
      close();
      onChanged();
    } catch (e) {
      toast.error(e instanceof ServiceError ? e.message : "Unable to cancel coaching.");
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
        title="Delete Student"
        description={
          <>
            Do you want to proceed with deleting <span className="font-semibold text-foreground">{target?.studentName}</span> from{" "}
            <span className="font-semibold text-foreground">{target?.programName}</span>? Their enrollment will be removed. Payments already received stay in
            Finance. This can&apos;t be undone.
          </>
        }
        confirmLabel="Yes, Delete"
        busyLabel="Checking…"
        onConfirm={() => void confirmDelete()}
        onCancel={close}
      />
      <ConfirmDialog
        open={stage === "cancel"}
        destructive
        busy={busy}
        title="Cancel Coaching & AutoPay?"
        description={
          <>
            <span className="font-semibold text-foreground">{target?.studentName}</span> still has an active payment or coaching, so they can&apos;t be deleted
            yet. Cancelling stops any online payment or AutoPay and cancels their coaching — the student is{" "}
            <span className="font-semibold text-foreground">not</span> deleted. You can delete them afterwards.
          </>
        }
        confirmLabel="Cancel Coaching"
        cancelLabel="Keep Coaching"
        busyLabel="Cancelling…"
        onConfirm={() => void confirmCancelCoaching()}
        onCancel={close}
      />
    </>
  );

  return { start: (t: DeleteStudentTarget) => { setTarget(t); setStage("delete"); }, dialogs };
}
