"use client";

import * as React from "react";
import Link from "next/link";
import { Clock, ShieldAlert } from "lucide-react";
import { Dialog, DialogContent, DialogDescription, DialogTitle } from "@/components/ui/dialog";
import { setupFontClass } from "@/features/onboarding/components/onboarding-shell";
import { ReviewIllustration } from "@/features/setup-review/components/setup-review-gate";
import { cn } from "@/lib/utils";

/**
 * Shown over the dashboard while GameAll has not approved the facility setup yet: a small version of the Under Review page, with the
 * dialog's close button in the corner. The owner can explore GameAll meanwhile. It stays closed for the rest of the visit (the dashboard
 * layout does not remount between pages) and returns on the next load.
 */
export function SetupReviewPopup({ status, note }: { status: "PENDING" | "REJECTED"; note: string | null; facilityId: string }) {
  const [open, setOpen] = React.useState(true);
  const rejected = status === "REJECTED";

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogContent className={cn(setupFontClass, "max-w-[480px] gap-0 rounded-2xl border-[#E5E1EF] bg-gradient-to-b from-white via-[#FBF9FF] to-[#F3ECFF] p-6 text-center text-[#171717] sm:p-8")}>
        {rejected ? (
          <span className="mx-auto flex h-20 w-20 items-center justify-center rounded-full bg-[#FDECEC] text-[#C62828]">
            <ShieldAlert className="h-9 w-9" aria-hidden="true" />
          </span>
        ) : (
          <ReviewIllustration className="h-[130px] sm:h-[150px]" />
        )}

        <DialogTitle className="mt-4 text-2xl font-bold leading-tight tracking-tight text-[#1B0B4B]">
          {rejected ? (
            <>
              Your Facility Setup <span className="text-[#C62828]">Needs Changes</span>
            </>
          ) : (
            <>
              Your Facility Setup is <span className="text-[#5B1FE8]">Under Review</span>
            </>
          )}
        </DialogTitle>
        <DialogDescription className="mt-2 text-sm leading-snug text-[#2B2B2B]">
          {rejected
            ? (note ?? "GameAll needs something fixed before your facility can go live.")
            : "Our team is reviewing your details and documents. You can explore GameAll in the meantime. We'll notify you as soon as it's approved."}
        </DialogDescription>

        {!rejected && (
          <p className="mx-auto mt-4 inline-flex items-center gap-2 rounded-full bg-[#EFE8FF] px-4 py-2 text-sm font-medium text-[#2A1070]">
            <Clock className="h-4 w-4 shrink-0 text-[#5B1FE8]" aria-hidden="true" />
            <span>
              Approval usually takes up to <strong className="font-bold text-[#5B1FE8]">24 hours.</strong>
            </span>
          </p>
        )}

        <div className="mt-6 flex flex-col-reverse gap-2 sm:flex-row sm:justify-center">
          <button
            type="button"
            onClick={() => setOpen(false)}
            className="h-11 rounded-lg border border-[#E5E1EF] bg-white px-5 text-sm font-semibold hover:bg-[#F1EBFF] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#4817C2]"
          >
            {rejected ? "Close" : "Explore GameAll"}
          </button>
          <Link
            href="/onboarding/review"
            className="flex h-11 items-center justify-center rounded-lg bg-[#4817C2] px-5 text-sm font-semibold text-white hover:bg-[#39109F] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#4817C2] focus-visible:ring-offset-2"
          >
            {rejected ? "See what to fix" : "View review status"}
          </Link>
        </div>
      </DialogContent>
    </Dialog>
  );
}
