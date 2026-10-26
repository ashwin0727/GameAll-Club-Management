"use client";

import { useState } from "react";
import { Landmark, Smartphone } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Skeleton } from "@/components/ui/skeleton";
import { Textarea } from "@/components/ui/textarea";
import { ErrorNote, PageTitle } from "@/features/admin/components/admin-shell";
import { VerificationBadge } from "@/features/admin/components/verification-badge";
import { formatDateTime } from "@/features/admin/format";
import { usePayoutMethods, useReviewPayout } from "@/features/admin/hooks";
import type { AdminPayoutMethod, PayoutVerification } from "@/features/admin/service";

function Field({ label, value, mono = false }: { label: string; value: string | null; mono?: boolean }) {
  return (
    <div>
      <dt className="text-xs font-medium uppercase tracking-wide text-muted-foreground">{label}</dt>
      <dd className={mono ? "mt-0.5 select-all font-mono text-sm" : "mt-0.5 text-sm font-medium"}>{value || "—"}</dd>
    </div>
  );
}

function MethodCard({ m, onReview, busy }: { m: AdminPayoutMethod; busy: boolean; onReview: (status: PayoutVerification, note: string | null) => void }) {
  const [rejecting, setRejecting] = useState(false);
  const [note, setNote] = useState("");

  return (
    <article className="rounded-xl border border-border bg-card">
      <div className="flex flex-wrap items-center justify-between gap-3 border-b border-border px-5 py-3.5">
        <div className="flex items-center gap-2.5">
          {m.type === "BANK" ? <Landmark className="h-4 w-4 text-muted-foreground" aria-hidden /> : <Smartphone className="h-4 w-4 text-muted-foreground" aria-hidden />}
          <h2 className="text-sm font-semibold">{m.type === "BANK" ? "Bank account" : "UPI ID"}</h2>
          {m.primary && <span className="rounded-full bg-secondary px-2 py-0.5 text-[11px] font-medium">Primary</span>}
        </div>
        <VerificationBadge status={m.verification} />
      </div>

      <dl className="grid gap-x-8 gap-y-4 p-5 sm:grid-cols-2">
        <Field label="Account holder" value={m.accountHolderName} />
        {m.type === "BANK" ? (
          <>
            <Field label="Bank" value={m.bankName} />
            <Field label="Account number" value={m.accountNumber} mono />
            <Field label="IFSC" value={m.ifsc} mono />
          </>
        ) : (
          <Field label="UPI ID" value={m.upiId} mono />
        )}
        <Field label="Added" value={formatDateTime(m.createdAt)} />
        <Field label="Last changed" value={formatDateTime(m.updatedAt)} />
        {m.verification === "VERIFIED" && <Field label="Verified on" value={formatDateTime(m.verifiedAt)} />}
        {m.note && <Field label={m.verification === "REJECTED" ? "Reason given" : "Note"} value={m.note} />}
      </dl>

      <div className="border-t border-border px-5 py-3.5">
        {rejecting ? (
          <div className="space-y-3">
            <label className="block text-sm font-medium" htmlFor={`note-${m.id}`}>
              Why is this being rejected? The owner will see it.
            </label>
            <Textarea id={`note-${m.id}`} value={note} onChange={(e) => setNote(e.target.value)} rows={3} placeholder="e.g. Account holder name does not match the business" />
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
        ) : (
          <div className="flex flex-wrap gap-2">
            {m.verification !== "VERIFIED" && (
              <Button size="sm" disabled={busy} onClick={() => onReview("VERIFIED", null)}>
                Verify
              </Button>
            )}
            {m.verification !== "REJECTED" && (
              <Button variant="outline" size="sm" disabled={busy} onClick={() => setRejecting(true)}>
                Reject
              </Button>
            )}
            {m.verification !== "PENDING" && (
              <Button variant="ghost" size="sm" disabled={busy} onClick={() => onReview("PENDING", null)}>
                Back to pending
              </Button>
            )}
          </div>
        )}
      </div>
    </article>
  );
}

/** One facility's bank / UPI details, in full, with Verify and Reject. */
export function AdminPayoutDetailPage({ facilityId }: { facilityId: string }) {
  const { data, isLoading, error } = usePayoutMethods(facilityId);
  const review = useReviewPayout();

  if (error) return <ErrorNote error={error} />;
  if (isLoading || !data) return <Skeleton className="h-72 w-full rounded-xl" />;

  const f = data.facility;
  return (
    <div className="space-y-5">
      <PageTitle
        back={{ href: "/admin/payouts", label: "All payouts" }}
        title={f?.name ?? "Facility"}
        subtitle={f ? `${f.ownerName ?? "—"} · ${f.ownerEmail ?? "—"} · ${f.ownerPhone ?? "—"}` : undefined}
      />
      {review.error && <ErrorNote error={review.error} />}
      {data.methods.length === 0 ? (
        <p className="rounded-xl border border-border bg-card p-10 text-center text-sm text-muted-foreground">This facility has not added a bank account or UPI ID yet.</p>
      ) : (
        data.methods.map((m) => (
          <MethodCard key={m.id} m={m} busy={review.isPending} onReview={(status, note) => review.mutate({ methodId: m.id, status, note })} />
        ))
      )}
    </div>
  );
}
