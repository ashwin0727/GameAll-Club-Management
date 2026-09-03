"use client";

import { useState } from "react";
import { Check, Code2, Copy, ExternalLink, Share2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";

/**
 * Gives a club the two ways to put public booking in front of players:
 *
 *   1. a link to the hosted page, to share or link to from anywhere
 *   2. a one-line embed snippet that renders the same flow inside their own
 *      website
 *
 * The origin is read from the browser rather than configured, so the values
 * shown are always correct for whatever host this is served from — local,
 * staging or production.
 */
export function ShareBookingLink({ facilityId }: { facilityId: string }) {
  const [open, setOpen] = useState(false);
  const [copied, setCopied] = useState<"link" | "embed" | null>(null);

  const origin = typeof window !== "undefined" ? window.location.origin : "";
  const bookingUrl = `${origin}/book/${facilityId}`;
  const snippet = `<script src="${origin}/embed.js" data-facility="${facilityId}"></script>`;

  async function copy(value: string, which: "link" | "embed") {
    try {
      await navigator.clipboard.writeText(value);
      setCopied(which);
      setTimeout(() => setCopied(null), 2000);
    } catch {
      window.prompt("Copy this:", value);
    }
  }

  return (
    <>
      <Button type="button" size="sm" variant="outline" onClick={() => setOpen(true)}>
        <Share2 className="mr-1.5 h-4 w-4" /> Share booking page
      </Button>

      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent className="sm:max-w-lg">
          <DialogHeader>
            <DialogTitle>Share your booking page</DialogTitle>
            <DialogDescription>
              Two ways to let players book. Both use the same page and the same availability.
            </DialogDescription>
          </DialogHeader>

          <div className="space-y-5">
            <section className="space-y-2">
              <h3 className="text-sm font-medium">1. Share a link</h3>
              <p className="text-xs text-muted-foreground">
                Put this anywhere — WhatsApp, Instagram bio, a QR code at the venue.
              </p>
              <div className="flex items-center gap-2">
                <code className="min-w-0 flex-1 truncate rounded-lg bg-muted px-3 py-2 text-xs">{bookingUrl}</code>
                <Button type="button" size="sm" variant="outline" onClick={() => copy(bookingUrl, "link")}>
                  {copied === "link" ? <Check className="h-4 w-4" /> : <Copy className="h-4 w-4" />}
                  <span className="sr-only">Copy link</span>
                </Button>
                <Button type="button" size="sm" variant="outline" asChild>
                  <a href={bookingUrl} target="_blank" rel="noopener noreferrer">
                    <ExternalLink className="h-4 w-4" />
                    <span className="sr-only">Open booking page</span>
                  </a>
                </Button>
              </div>
            </section>

            <section className="space-y-2">
              <h3 className="flex items-center gap-1.5 text-sm font-medium">
                <Code2 className="h-4 w-4" aria-hidden /> 2. Embed in your own website
              </h3>
              <p className="text-xs text-muted-foreground">
                Paste this where the booking form should appear. It resizes itself to fit, and works on
                WordPress, Wix, Squarespace or plain HTML.
              </p>
              <div className="flex items-start gap-2">
                <code className="min-w-0 flex-1 break-all rounded-lg bg-muted px-3 py-2 text-xs">{snippet}</code>
                <Button type="button" size="sm" variant="outline" onClick={() => copy(snippet, "embed")}>
                  {copied === "embed" ? <Check className="h-4 w-4" /> : <Copy className="h-4 w-4" />}
                  <span className="sr-only">Copy embed code</span>
                </Button>
              </div>
            </section>
          </div>
        </DialogContent>
      </Dialog>
    </>
  );
}
