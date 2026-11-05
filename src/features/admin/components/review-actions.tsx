"use client";

import { useState } from "react";
import { Button } from "@/components/ui/button";
import { Textarea } from "@/components/ui/textarea";
import type { PayoutVerification } from "@/features/admin/service";

/**
 * Verify / Reject / Back to pending for one thing the admin is checking (a map link, a photo). Rejecting needs a reason, which the
 * owner then sees. [subject] words the prompt ("this link", "this photo").
 */
export function ReviewActions({
  id,
  current,
  busy,
  subject,
  placeholder,
  onReview,
}: {
  id: string;
  current: PayoutVerification;
  busy: boolean;
  subject: string;
  placeholder: string;
  onReview: (status: PayoutVerification, note: string | null) => void;
}) {
  const [rejecting, setRejecting] = useState(false);
  const [note, setNote] = useState("");

  if (rejecting) {
    return (
      <div className="space-y-3">
        <label className="block text-sm font-medium" htmlFor={`note-${id}`}>
          Why is {subject} being rejected? The owner will see it.
        </label>
        <Textarea id={`note-${id}`} value={note} onChange={(e) => setNote(e.target.value)} rows={3} placeholder={placeholder} />
        <div className="flex gap-2">
          <Button
            variant="destructive"
            size="sm"
            disabled={busy || note.trim().length === 0}
            onClick={() => {
              onReview("REJECTED", note.trim());
              setRejecting(false);
              setNote("");
            }}
          >
            Reject
          </Button>
          <Button variant="outline" size="sm" onClick={() => setRejecting(false)}>
            Cancel
          </Button>
        </div>
      </div>
    );
  }

  return (
    <div className="flex flex-wrap gap-2">
      {current !== "VERIFIED" && (
        <Button size="sm" disabled={busy} onClick={() => onReview("VERIFIED", null)}>
          Verify
        </Button>
      )}
      {current !== "REJECTED" && (
        <Button variant="outline" size="sm" disabled={busy} onClick={() => setRejecting(true)}>
          Reject
        </Button>
      )}
      {current !== "PENDING" && (
        <Button variant="ghost" size="sm" disabled={busy} onClick={() => onReview("PENDING", null)}>
          Back to pending
        </Button>
      )}
    </div>
  );
}
