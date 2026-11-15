"use client";

import * as React from "react";
import Link from "next/link";
import { Clock, Send, X } from "lucide-react";
import { Dialog, DialogContent, DialogDescription, DialogTitle } from "@/components/ui/dialog";
import { cn } from "@/lib/utils";

const PICTURE = "/submit-review.png";

/**
 * "Confirm & Submit for Review": shown when the owner finishes setup (Payout step). Both statements have to be ticked before the setup
 * is sent to GameAll for approval; nothing is submitted until then. A wide, two-column card on the web.
 */
export function SubmitForReviewDialog({
  open,
  busy = false,
  onSubmit,
  onCancel,
}: {
  open: boolean;
  busy?: boolean;
  onSubmit: () => void;
  onCancel: () => void;
}) {
  const [accurate, setAccurate] = React.useState(false);
  const [terms, setTerms] = React.useState(false);

  // every time it opens it starts unticked: agreeing is a fresh decision
  React.useEffect(() => {
    if (open) {
      setAccurate(false);
      setTerms(false);
    }
  }, [open]);

  // fetched as soon as the page is up, so the picture and the words appear together
  React.useEffect(() => {
    const img = new window.Image();
    img.src = PICTURE;
  }, []);

  const ready = accurate && terms && !busy;

  return (
    <Dialog open={open} onOpenChange={(o) => !o && !busy && onCancel()}>
      <DialogContent onOpenAutoFocus={(e) => { e.preventDefault(); (e.currentTarget as HTMLElement).focus(); }} className="focus:outline-none max-w-[820px] rounded-3xl border-0 bg-white p-5 shadow-2xl sm:p-8 [&>button.absolute]:hidden">
        <button
          type="button"
          aria-label="Close"
          disabled={busy}
          onClick={onCancel}
          className="absolute right-4 top-4 flex h-9 w-9 items-center justify-center rounded-full bg-[#EEEAF7] text-[#171717] transition-colors hover:bg-[#E5E1EF] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#4817C2] disabled:opacity-50"
        >
          <X className="h-4 w-4" aria-hidden="true" />
        </button>

        <div className="grid items-center gap-6 sm:grid-cols-[minmax(0,0.75fr)_1px_minmax(0,1.6fr)] sm:gap-8">
          {/* eslint-disable-next-line @next/next/no-img-element -- preloaded above */}
          <img src={PICTURE} alt="" aria-hidden="true" width={720} height={580} decoding="sync" className="mx-auto h-auto w-[170px] sm:w-full" />
          <div className="hidden h-full min-h-[200px] w-px bg-[#E5E1EF] sm:block" aria-hidden="true" />

          <div className="min-w-0">
            <DialogTitle className="text-2xl font-bold leading-tight tracking-tight text-[#171717] sm:text-[28px]">Confirm &amp; Submit for Review</DialogTitle>
            <DialogDescription className="mt-2 text-sm leading-snug text-[#555555]">
              Please review and confirm the following before submitting your facility details for GameAll&apos;s approval.
            </DialogDescription>

            <div className="mt-5 space-y-4">
              <label className="flex cursor-pointer items-start gap-3 text-sm leading-snug">
                <input
                  type="checkbox"
                  checked={accurate}
                  onChange={(e) => setAccurate(e.target.checked)}
                  disabled={busy}
                  className="mt-0.5 h-5 w-5 shrink-0 cursor-pointer rounded accent-[#4817C2]"
                />
                <span>
                  I confirm that all the information and documents I have provided about my facility, including its address, contact details, sports,
                  courts, operating hours, pricing, amenities and payout information, are <strong>true, accurate and up to date.</strong>
                </span>
              </label>
              <label className="flex cursor-pointer items-start gap-3 text-sm leading-snug">
                <input
                  type="checkbox"
                  checked={terms}
                  onChange={(e) => setTerms(e.target.checked)}
                  disabled={busy}
                  className="mt-0.5 h-5 w-5 shrink-0 cursor-pointer rounded accent-[#4817C2]"
                />
                <span>
                  I have read and agree to GameAll&apos;s{" "}
                  <Link href="/terms" target="_blank" rel="noopener noreferrer" className="font-semibold text-[#4817C2] underline">
                    Terms and Conditions
                  </Link>{" "}
                  and{" "}
                  <Link href="/privacy" target="_blank" rel="noopener noreferrer" className="font-semibold text-[#4817C2] underline">
                    Privacy Policy
                  </Link>
                  .
                </span>
              </label>
            </div>
          </div>
        </div>

        <div className="mt-6 flex items-center gap-4 rounded-2xl bg-[#F3EFFF] p-4">
          <span className="flex h-11 w-11 shrink-0 items-center justify-center rounded-full bg-[#E6DEFB] text-[#4817C2]">
            <Clock className="h-5 w-5" aria-hidden="true" />
          </span>
          <div className="min-w-0 border-l border-[#D9D0F4] pl-4">
            <p className="text-base font-bold text-[#4817C2]">What happens next?</p>
            <p className="mt-0.5 text-sm leading-snug text-[#555555]">
              Your facility setup will be sent to our team for review. Approval usually takes <strong className="text-[#4817C2]">up to 24 hours</strong>.
              We&apos;ll notify you once it&apos;s approved.
            </p>
          </div>
        </div>

        <div className="mt-6 grid gap-3 sm:grid-cols-2">
          <button
            type="button"
            disabled={busy}
            onClick={onCancel}
            className="h-14 rounded-xl border border-[#4817C2]/50 bg-white text-base font-bold text-[#171717] transition-colors hover:bg-[#FBFAFE] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#4817C2] disabled:opacity-50"
          >
            Cancel
          </button>
          <button
            type="button"
            disabled={!ready}
            onClick={onSubmit}
            className={cn(
              "flex h-14 items-center justify-center gap-2.5 rounded-xl bg-gradient-to-b from-[#5B21D6] to-[#4817C2] text-base font-bold text-white shadow-[0_6px_14px_rgba(72,23,194,0.3)] transition focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#4817C2] focus-visible:ring-offset-2",
              ready ? "hover:from-[#4817C2] hover:to-[#39109F]" : "cursor-not-allowed opacity-50",
            )}
          >
            <Send className="h-5 w-5" aria-hidden="true" />
            {busy ? "Submitting…" : "Submit for Review"}
          </button>
        </div>
      </DialogContent>
    </Dialog>
  );
}
