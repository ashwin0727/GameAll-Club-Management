"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { usePermissionContext } from "@/features/auth/context/permission-provider";
import { PermissionDenied } from "@/features/staff/components/permission-denied";
import { PageHeader } from "@/features/coaching/components/shared";
import { AddCoachFormFields, submitButtonLabel } from "@/features/coaching/components/add-coach-form-fields";
import { useAddCoachForm } from "@/features/coaching/components/use-add-coach-form";
import { CoachAddedContent } from "@/features/coaching/components/coach-added-content";

/**
 * Add Coach, as a standalone page (direct link / bookmark / browser back-forward). The in-app
 * entry points (Coaching landing page hero, Coaches list, Quick Actions) open `AddCoachSheet`
 * instead — the reference design's actual "Add Coach" is a right-side slide-over, not a page
 * navigation — but this route stays as a working fallback, sharing the same form logic via
 * `useAddCoachForm`/`AddCoachFormFields` rather than a second implementation.
 */
export function AddCoachPage() {
  const perms = usePermissionContext();
  const router = useRouter();
  const facilityId = perms?.facilityId ?? null;
  const form = useAddCoachForm(facilityId);
  const [created, setCreated] = useState<{ id: string; name: string } | null>(null);

  if (!perms?.can("COACHING_MANAGE_COACHES")) {
    return <PermissionDenied message="You don't have permission to manage coaches." />;
  }

  async function handleSubmit() {
    try {
      const { coachId, name } = await form.submit();
      setCreated({ id: coachId, name });
    } catch {
      // form.error already carries the user-facing message; nothing else to do here.
    }
  }

  if (created) {
    return (
      <div className="mx-auto max-w-2xl space-y-4">
        <Card className="p-6">
          <CoachAddedContent coachId={created.id} name={created.name} onNavigate={(href) => router.push(href)} />
          <div className="mt-6 flex items-center justify-between border-t border-border pt-4">
            <Button type="button" variant="outline" onClick={() => window.location.reload()}>
              Add Another Coach
            </Button>
            <Button onClick={() => router.push("/coaching/coaches")}>Go to Coaches List</Button>
          </div>
        </Card>
      </div>
    );
  }

  return (
    <div className="space-y-4">
      <PageHeader
        title="Add Coach"
        subtitle="Add a new coach to your club. They will be able to take coaching sessions and manage their schedule."
      />

      <Card className="p-6">
        <AddCoachFormFields facilityId={facilityId} form={form} />

        <div className="mt-6 flex items-center justify-between border-t border-border pt-4">
          <Button type="button" variant="outline" onClick={() => router.push("/coaching/coaches")}>
            Cancel
          </Button>
          <Button onClick={() => void handleSubmit()} disabled={form.busy || !form.canSubmit}>
            {submitButtonLabel(form)}
          </Button>
        </div>
      </Card>
    </div>
  );
}
