"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { Users } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Sheet, SheetBody, SheetContent, SheetFooter, SheetHeader, SheetTitle, SheetDescription } from "@/components/ui/sheet";
import { AddCoachFormFields, submitButtonLabel } from "@/features/coaching/components/add-coach-form-fields";
import { useAddCoachForm } from "@/features/coaching/components/use-add-coach-form";
import { CoachAddedContent } from "@/features/coaching/components/coach-added-content";

/**
 * "Add Coach" as a right-side slide-over — the reference design's actual entry point, triggered
 * from the Coaching landing page's hero button, its Quick Actions tile, and the Coaches list's
 * own Add Coach button, instead of navigating to /coaching/coaches/add. Same form logic as that
 * standalone page (`useAddCoachForm`), just laid out as header/scrollable body/pinned footer to
 * fit a fixed-height panel instead of a full page.
 */
export function AddCoachSheet({
  facilityId,
  open,
  onOpenChange,
  onCoachAdded,
}: {
  facilityId: string | null;
  open: boolean;
  onOpenChange: (open: boolean) => void;
  /** Called once a coach is actually created, so the caller can refresh whatever list is showing. */
  onCoachAdded?: () => void;
}) {
  const router = useRouter();
  const form = useAddCoachForm(facilityId);
  const [created, setCreated] = useState<{ id: string; name: string } | null>(null);

  // Reset to a blank form each time the sheet is opened fresh, rather than showing the previous
  // attempt's leftover state (or the just-added coach's success screen) on the next open.
  useEffect(() => {
    if (open) setCreated(null);
  }, [open]);

  async function handleSubmit() {
    try {
      const { coachId, name } = await form.submit();
      setCreated({ id: coachId, name });
      onCoachAdded?.();
    } catch {
      // form.error already carries the user-facing message; nothing else to do here.
    }
  }

  function navigateAndClose(href: string) {
    onOpenChange(false);
    router.push(href);
  }

  return (
    <Sheet open={open} onOpenChange={onOpenChange}>
      <SheetContent side="right" className="flex h-full flex-col p-0 sm:max-w-md">
        {created ? (
          <>
            <SheetHeader className="border-b-0">
              <SheetTitle className="sr-only">Coach Added Successfully</SheetTitle>
            </SheetHeader>
            <SheetBody>
              <CoachAddedContent coachId={created.id} name={created.name} onNavigate={navigateAndClose} />
            </SheetBody>
            <SheetFooter>
              <Button type="button" variant="outline" onClick={() => setCreated(null)}>
                Add Another Coach
              </Button>
              <Button onClick={() => navigateAndClose("/coaching/coaches")}>Go to Coaches List</Button>
            </SheetFooter>
          </>
        ) : (
          <>
            <SheetHeader>
              <span className="flex h-11 w-11 shrink-0 items-center justify-center rounded-xl bg-success/15 text-success">
                <Users className="h-5 w-5" aria-hidden />
              </span>
              <div>
                <SheetTitle>Add Coach</SheetTitle>
                <SheetDescription>
                  Add a new coach to your club. They will be able to take coaching sessions and manage their schedule.
                </SheetDescription>
              </div>
            </SheetHeader>
            <SheetBody>
              <AddCoachFormFields facilityId={facilityId} form={form} />
            </SheetBody>
            <SheetFooter>
              <Button type="button" variant="outline" onClick={() => onOpenChange(false)}>
                Cancel
              </Button>
              <Button onClick={() => void handleSubmit()} disabled={form.busy || !form.canSubmit}>
                {submitButtonLabel(form)}
              </Button>
            </SheetFooter>
          </>
        )}
      </SheetContent>
    </Sheet>
  );
}
