"use client";

import { useState } from "react";
import { ExternalLink } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Skeleton } from "@/components/ui/skeleton";
import { Textarea } from "@/components/ui/textarea";
import { REVIEW_BADGE } from "@/features/admin/components/admin-reviews-page";
import { ErrorNote, PageTitle } from "@/features/admin/components/admin-shell";
import { ReviewActions } from "@/features/admin/components/review-actions";
import { VerificationBadge } from "@/features/admin/components/verification-badge";
import { formatDateTime, humanize, inr } from "@/features/admin/format";
import { useDecideSetup, useReviewImage, useReviewLocation, useReviewPayout, useSetupReview } from "@/features/admin/hooks";
import type { AdminSetupReview } from "@/features/admin/service";
import { cn } from "@/lib/utils";

const DAYS = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];

function Section({ title, aside, children }: { title: string; aside?: React.ReactNode; children: React.ReactNode }) {
  return (
    <section className="rounded-xl border border-border bg-card">
      <div className="flex flex-wrap items-center justify-between gap-3 border-b border-border px-5 py-3.5">
        <h2 className="text-sm font-semibold">{title}</h2>
        {aside}
      </div>
      <div className="p-5">{children}</div>
    </section>
  );
}

function Item({ label, children, wide }: { label: string; children: React.ReactNode; wide?: boolean }) {
  return (
    <div className={wide ? "sm:col-span-2" : undefined}>
      <dt className="text-xs font-medium uppercase tracking-wide text-muted-foreground">{label}</dt>
      <dd className="mt-0.5 break-words text-sm font-medium">{children || "—"}</dd>
    </div>
  );
}

const time = (t: string | null) => (t ? t.slice(0, 5) : "");
const mask = (n: string | null) => (n ? `${"•".repeat(Math.max(n.length - 4, 0))}${n.slice(-4)}` : "—");

function dayLabel(r: AdminSetupReview["pricing"]["rules"][number]): string {
  const when = r.dayType === "ALL_DAYS" ? "Every day" : r.dayType === "WEEKDAYS" ? "Mon – Fri" : r.dayType === "WEEKENDS" ? "Sat – Sun" : "Chosen days";
  return r.fullDay ? `${when}, all day` : `${when}, ${time(r.start)} – ${time(r.end)}`;
}

/** Everything one owner entered — Facility Information → Payout — with the verification tools, and the final approve / send back. */
export function AdminReviewDetailPage({ facilityId }: { facilityId: string }) {
  const { data, isLoading, error } = useSetupReview(facilityId);
  const decide = useDecideSetup();
  const reviewLocation = useReviewLocation();
  const reviewImage = useReviewImage();
  const reviewPayout = useReviewPayout();
  const [reveal, setReveal] = useState<Record<string, boolean>>({});
  const [sendingBack, setSendingBack] = useState(false);
  const [note, setNote] = useState("");

  if (error) return <ErrorNote error={error} />;
  if (isLoading || !data) return <Skeleton className="h-72 w-full rounded-xl" />;

  const f = data.facility;
  const status = data.review.status;
  const failure = decide.error ?? reviewLocation.error ?? reviewImage.error ?? reviewPayout.error;
  const verifiedPayouts = data.payoutMethods.filter((m) => m.verification === "VERIFIED").length;
  const s = data.payoutSettings;

  return (
    <div className="space-y-5">
      <PageTitle
        back={{ href: "/admin/reviews", label: "All approvals" }}
        title={f.name}
        subtitle={`${data.owner.name ?? "—"} · ${data.owner.email ?? "—"} · ${data.owner.phone ?? "—"}`}
      />
      {failure && <ErrorNote error={failure} />}

      <section className="flex flex-wrap items-center justify-between gap-4 rounded-xl border border-border bg-card px-5 py-4">
        <div>
          <span className={cn("rounded-full px-2.5 py-0.5 text-xs font-semibold", REVIEW_BADGE[status].className)}>{REVIEW_BADGE[status].label}</span>
          <p className="mt-2 text-sm text-muted-foreground">
            {status === "PENDING" && `Submitted ${formatDateTime(data.review.submittedAt)}. Check every section below, verify the payout details, then decide.`}
            {status === "APPROVED" && `Approved ${formatDateTime(data.review.reviewedAt)}.`}
            {status === "REJECTED" && `Sent back ${formatDateTime(data.review.reviewedAt)}: ${data.review.note ?? ""}`}
            {status === "NOT_SUBMITTED" && "The owner has not finished setup."}
          </p>
        </div>
        {status !== "NOT_SUBMITTED" && !sendingBack && (
          <div className="flex flex-wrap gap-2">
            {status !== "APPROVED" && (
              <Button disabled={decide.isPending || verifiedPayouts === 0} onClick={() => decide.mutate({ facilityId, decision: "APPROVED", note: null })}>
                Approve
              </Button>
            )}
            <Button variant="outline" disabled={decide.isPending} onClick={() => setSendingBack(true)}>
              {status === "APPROVED" ? "Revoke & send back" : "Send back"}
            </Button>
          </div>
        )}
        {status === "PENDING" && verifiedPayouts === 0 && !sendingBack && (
          <p className="w-full text-xs text-muted-foreground">Verify at least one payout method below to enable Approve.</p>
        )}
        {sendingBack && (
          <div className="w-full space-y-3">
            <label htmlFor="send-back-note" className="block text-sm font-medium">
              What needs to change? The owner will see this.
            </label>
            <Textarea id="send-back-note" rows={3} value={note} onChange={(e) => setNote(e.target.value)} placeholder="e.g. The Google Maps pin is on a different street, and the IFSC does not match the bank." />
            <div className="flex gap-2">
              <Button
                variant="destructive"
                disabled={decide.isPending || note.trim().length === 0}
                onClick={() =>
                  decide.mutate(
                    { facilityId, decision: "REJECTED", note: note.trim() },
                    {
                      onSuccess: () => {
                        setSendingBack(false);
                        setNote("");
                      },
                    },
                  )
                }
              >
                Send back to owner
              </Button>
              <Button variant="outline" onClick={() => setSendingBack(false)}>
                Cancel
              </Button>
            </div>
          </div>
        )}
      </section>

      <Section title="1 · Facility information">
        <dl className="grid gap-x-8 gap-y-4 sm:grid-cols-2">
          <Item label="Name">{f.name}</Item>
          <Item label="Type">{f.type ? humanize(f.type) : ""}</Item>
          <Item label="Ownership">{f.ownership ? humanize(f.ownership) : ""}</Item>
          <Item label="Time zone">{f.timezone}</Item>
          <Item label="Business email">{f.businessEmail}</Item>
          <Item label="Business phone">{f.businessPhone}</Item>
          <Item label="WhatsApp">{f.whatsapp}</Item>
          <Item label="Contact person">{[f.contactPerson, f.contactRole].filter(Boolean).join(" · ")}</Item>
          <Item label="Address" wide>{f.address}</Item>
          <Item label="Description" wide>{f.description}</Item>
          <Item label="Amenities" wide>{[...f.amenities.map(humanize), ...f.customAmenities].join(", ") || "None"}</Item>
          <Item label="Booking rules" wide>
            {[
              f.allowOnlineBooking && "Online booking",
              f.allowWalkIn && "Walk-in booking",
              f.advancePaymentRequired && "Advance payment required",
              f.allowCancellations && "Cancellations allowed",
            ]
              .filter(Boolean)
              .join(", ") || "—"}
          </Item>
        </dl>
      </Section>

      <Section title="Google Maps location" aside={f.location.url ? <VerificationBadge status={f.location.status} /> : <span className="text-xs text-muted-foreground">No link given</span>}>
        {f.location.url ? (
          <div className="space-y-4">
            <a href={f.location.url} target="_blank" rel="noopener noreferrer" className="inline-flex items-center gap-1.5 break-all text-sm font-medium text-primary hover:underline">
              {f.location.url} <ExternalLink className="h-3.5 w-3.5 shrink-0" aria-hidden />
            </a>
            <p className="text-sm text-muted-foreground">Compare the pin with the address above.</p>
            <ReviewActions
              id={`loc-${f.id}`}
              current={f.location.status}
              busy={reviewLocation.isPending}
              subject="this location"
              placeholder="e.g. The pin is on a different street from the address"
              onReview={(st, n) => reviewLocation.mutate({ facilityId: f.id, status: st, note: n })}
            />
          </div>
        ) : (
          <p className="text-sm text-muted-foreground">—</p>
        )}
      </Section>

      <Section title={`Photos (${data.images.length})`}>
        {data.images.length === 0 ? (
          <p className="text-sm text-muted-foreground">No photos uploaded.</p>
        ) : (
          <ul className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
            {data.images.map((img) => (
              <li key={img.id} className="overflow-hidden rounded-lg border border-border">
                <a href={img.url} target="_blank" rel="noopener noreferrer" aria-label="Open photo full size">
                  {/* eslint-disable-next-line @next/next/no-img-element -- remote photo of unknown size */}
                  <img src={img.url} alt="Facility" className="aspect-[3/2] w-full object-cover" />
                </a>
                <div className="space-y-3 p-3">
                  <VerificationBadge status={img.status} />
                  <ReviewActions
                    id={img.id}
                    current={img.status}
                    busy={reviewImage.isPending}
                    subject="this photo"
                    placeholder="e.g. This is not a photo of the facility"
                    onReview={(st, n) => reviewImage.mutate({ imageId: img.id, status: st, note: n })}
                  />
                </div>
              </li>
            ))}
          </ul>
        )}
      </Section>

      <Section title="2 · Sports & courts">
        <p className="mb-3 text-sm">
          <span className="font-medium">Sports: </span>
          {data.sports.filter((x) => x.active).map((x) => x.name).join(", ") || "—"}
        </p>
        <ul className="divide-y divide-border rounded-lg border border-border text-sm">
          {data.courts.map((c, i) => (
            <li key={`${c.name}-${i}`} className="flex flex-wrap items-center justify-between gap-2 px-4 py-2.5">
              <span className="font-medium">{c.name}</span>
              <span className="text-muted-foreground">
                {[c.sport, c.surface].filter(Boolean).join(" · ")} · {humanize(c.status)}
              </span>
            </li>
          ))}
        </ul>
      </Section>

      <Section title="3 · Operating hours" aside={data.hours.sportWise ? <span className="text-xs text-muted-foreground">Sport-wise hours are on (per-court schedules)</span> : undefined}>
        {data.hours.days.length === 0 ? (
          <p className="text-sm text-muted-foreground">No hours saved.</p>
        ) : (
          <ul className="grid gap-x-8 gap-y-1.5 text-sm sm:grid-cols-2">
            {data.hours.days.map((d) => (
              <li key={d.day} className="flex justify-between gap-3">
                <span className="font-medium">{DAYS[d.day]}</span>
                <span className="text-muted-foreground">{d.closed ? "Closed" : d.is24 ? "Open 24 hours" : d.slots.map((t) => `${time(t.start)} – ${time(t.end)}`).join(", ")}</span>
              </li>
            ))}
          </ul>
        )}
      </Section>

      <Section title="4 · Pricing" aside={<span className="text-xs text-muted-foreground">{data.pricing.mode === "BY_COURT" ? "Priced by court" : "Priced by sport"}</span>}>
        {data.pricing.rules.length === 0 ? (
          <p className="text-sm text-muted-foreground">No prices saved.</p>
        ) : (
          <ul className="divide-y divide-border rounded-lg border border-border text-sm">
            {data.pricing.rules.map((r, i) => (
              <li key={i} className="flex flex-wrap items-center justify-between gap-2 px-4 py-2.5">
                <span className="font-medium">{r.court ? `${r.sport ?? ""} · ${r.court}` : (r.sport ?? "—")}</span>
                <span className="text-muted-foreground">
                  {dayLabel(r)} · <span className="font-semibold text-foreground">{inr(r.amountMinor / 100)}</span> / {r.unit === "PER_SESSION" ? "session" : r.unit === "PER_MATCH" ? "match" : r.unit === "PER_30_MINUTES" ? "30 min" : "hour"}
                </span>
              </li>
            ))}
          </ul>
        )}
      </Section>

      <Section title="5 · Payout" aside={<span className="text-xs text-muted-foreground">{verifiedPayouts} of {data.payoutMethods.length} verified</span>}>
        {data.payoutMethods.length === 0 ? (
          <p className="text-sm text-muted-foreground">No payout account added.</p>
        ) : (
          <ul className="space-y-4">
            {data.payoutMethods.map((m) => (
              <li key={m.id} className="rounded-lg border border-border p-4">
                <div className="mb-3 flex flex-wrap items-center gap-2">
                  <span className="text-sm font-semibold">{m.type === "BANK" ? "Bank account" : "UPI"}</span>
                  {m.primary && <span className="rounded-full bg-primary/10 px-2 py-0.5 text-xs font-semibold text-primary">Primary</span>}
                  <VerificationBadge status={m.verification} />
                </div>
                <dl className="mb-4 grid gap-x-8 gap-y-3 sm:grid-cols-2">
                  <Item label="Account holder">{m.accountHolderName}</Item>
                  {m.type === "BANK" ? (
                    <>
                      <Item label="Bank">{m.bankName}</Item>
                      <Item label="Account number">
                        <span className="font-mono">{reveal[m.id] ? m.accountNumber : mask(m.accountNumber)}</span>{" "}
                        <button type="button" className="ml-1 text-xs font-semibold text-primary hover:underline" onClick={() => setReveal((p) => ({ ...p, [m.id]: !p[m.id] }))}>
                          {reveal[m.id] ? "Hide" : "Reveal"}
                        </button>
                      </Item>
                      <Item label="IFSC">
                        <span className="font-mono">{m.ifsc}</span>
                      </Item>
                      <Item label="Account type">{m.accountType ? humanize(m.accountType) : ""}</Item>
                    </>
                  ) : (
                    <Item label="UPI ID">
                      <span className="font-mono">{m.upiId}</span>
                    </Item>
                  )}
                  {m.note && <Item label="Note" wide>{m.note}</Item>}
                </dl>
                <ReviewActions
                  id={m.id}
                  current={m.verification}
                  busy={reviewPayout.isPending}
                  subject="this payout method"
                  placeholder="e.g. The account holder name does not match the facility owner"
                  onReview={(st, n) => reviewPayout.mutate({ methodId: m.id, status: st, note: n })}
                />
              </li>
            ))}
          </ul>
        )}
        {s && (
          <dl className="mt-5 grid gap-x-8 gap-y-3 border-t border-border pt-5 sm:grid-cols-2">
            <Item label="Settlement">{humanize(s.settlement_frequency)}</Item>
            <Item label="Minimum payout">{inr(s.minimum_payout_inr)}</Item>
            <Item label="Included earnings">
              {[s.include_bookings && "Bookings", s.include_memberships && "Memberships", s.include_coaching && "Coaching"].filter(Boolean).join(", ")}
            </Item>
            <Item label="Rules">{[s.auto_payout ? "Auto payout" : "Manual payout", s.hold_for_review && "Held for review"].filter(Boolean).join(", ")}</Item>
          </dl>
        )}
      </Section>

      {data.events.length > 0 && (
        <Section title="History">
          <ul className="space-y-1.5 text-sm">
            {data.events.map((e, i) => (
              <li key={i} className="flex flex-wrap justify-between gap-2">
                <span>
                  <span className="font-medium">{humanize(e.action)}</span>
                  {e.note ? ` — ${e.note}` : ""}
                </span>
                <span className="text-muted-foreground">{formatDateTime(e.at)}</span>
              </li>
            ))}
          </ul>
        </Section>
      )}
    </div>
  );
}
