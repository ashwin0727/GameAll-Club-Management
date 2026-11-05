"use client";

import Link from "next/link";
import { ExternalLink } from "lucide-react";
import { Skeleton } from "@/components/ui/skeleton";
import { ErrorNote, PageTitle } from "@/features/admin/components/admin-shell";
import { ReviewActions } from "@/features/admin/components/review-actions";
import { VerificationBadge } from "@/features/admin/components/verification-badge";
import { formatDateTime } from "@/features/admin/format";
import { useReviewImage, useReviewLocation, useVenueVerification } from "@/features/admin/hooks";

type AmenityKey = "parking" | "changingRooms" | "toilets" | "cafeteria" | "equipmentRental";

const AMENITY_LABELS: [AmenityKey, string][] = [
  ["parking", "Free Parking"],
  ["changingRooms", "Changing Rooms"],
  ["toilets", "Toilets / Rest Room"],
  ["cafeteria", "Cafeteria"],
  ["equipmentRental", "Equipment Rental"],
];

/** One facility's map link and photos in full, to verify or reject, with a link on to its payout details. */
export function AdminVenueDetailPage({ facilityId }: { facilityId: string }) {
  const { data, isLoading, error } = useVenueVerification(facilityId);
  const reviewLocation = useReviewLocation();
  const reviewImage = useReviewImage();

  if (error) return <ErrorNote error={error} />;
  if (isLoading || !data) return <Skeleton className="h-72 w-full rounded-xl" />;

  const f = data.facility;
  if (!f) return <ErrorNote error={new Error("Facility not found.")} />;
  const failure = reviewLocation.error ?? reviewImage.error;
  const payoutPending = data.payoutMethods.filter((m) => m.verification === "PENDING").length;

  return (
    <div className="space-y-5">
      <PageTitle
        back={{ href: "/admin/venues", label: "All venues" }}
        title={f.name}
        subtitle={`${f.ownerName ?? "—"} · ${f.ownerEmail ?? "—"} · ${f.ownerPhone ?? "—"}`}
      />
      {failure && <ErrorNote error={failure} />}

      <section className="rounded-xl border border-border bg-card">
        <div className="flex flex-wrap items-center justify-between gap-3 border-b border-border px-5 py-3.5">
          <h2 className="text-sm font-semibold">Google Maps location</h2>
          {f.location.url ? <VerificationBadge status={f.location.status} /> : <span className="text-xs text-muted-foreground">No link given</span>}
        </div>
        <dl className="grid gap-x-8 gap-y-4 p-5 sm:grid-cols-2">
          <div className="sm:col-span-2">
            <dt className="text-xs font-medium uppercase tracking-wide text-muted-foreground">Link the owner gave</dt>
            <dd className="mt-0.5 break-all text-sm font-medium">
              {f.location.url ? (
                <a href={f.location.url} target="_blank" rel="noopener noreferrer" className="inline-flex items-center gap-1.5 text-primary hover:underline">
                  {f.location.url} <ExternalLink className="h-3.5 w-3.5 shrink-0" aria-hidden />
                </a>
              ) : (
                "—"
              )}
            </dd>
          </div>
          <div className="sm:col-span-2">
            <dt className="text-xs font-medium uppercase tracking-wide text-muted-foreground">Address on the facility (compare it with the map)</dt>
            <dd className="mt-0.5 text-sm font-medium">{f.address || "—"}</dd>
          </div>
          <div>
            <dt className="text-xs font-medium uppercase tracking-wide text-muted-foreground">Venue type</dt>
            <dd className="mt-0.5 text-sm font-medium">{f.venueType === "INDOOR" ? "Indoor" : f.venueType === "OUTDOOR" ? "Outdoor" : "—"}</dd>
          </div>
          <div>
            <dt className="text-xs font-medium uppercase tracking-wide text-muted-foreground">Amenities</dt>
            <dd className="mt-0.5 text-sm font-medium">{AMENITY_LABELS.filter(([k]) => f.amenities[k]).map(([, label]) => label).join(", ") || "None"}</dd>
          </div>
          {f.location.status === "VERIFIED" && f.location.verifiedAt && (
            <div>
              <dt className="text-xs font-medium uppercase tracking-wide text-muted-foreground">Verified on</dt>
              <dd className="mt-0.5 text-sm font-medium">{formatDateTime(f.location.verifiedAt)}</dd>
            </div>
          )}
          {f.location.note && (
            <div>
              <dt className="text-xs font-medium uppercase tracking-wide text-muted-foreground">{f.location.status === "REJECTED" ? "Reason given" : "Note"}</dt>
              <dd className="mt-0.5 text-sm font-medium">{f.location.note}</dd>
            </div>
          )}
        </dl>
        {f.location.url && (
          <div className="border-t border-border px-5 py-3.5">
            <ReviewActions
              id={`loc-${f.id}`}
              current={f.location.status}
              busy={reviewLocation.isPending}
              subject="this location"
              placeholder="e.g. The pin is on a different street from the address"
              onReview={(status, note) => reviewLocation.mutate({ facilityId: f.id, status, note })}
            />
          </div>
        )}
      </section>

      <section className="rounded-xl border border-border bg-card">
        <div className="border-b border-border px-5 py-3.5">
          <h2 className="text-sm font-semibold">Photos ({data.images.length})</h2>
        </div>
        {data.images.length === 0 ? (
          <p className="p-8 text-center text-sm text-muted-foreground">The owner has not uploaded a photo yet.</p>
        ) : (
          <ul className="grid gap-5 p-5 sm:grid-cols-2 lg:grid-cols-3">
            {data.images.map((img) => (
              <li key={img.id} className="overflow-hidden rounded-lg border border-border">
                <a href={img.url} target="_blank" rel="noopener noreferrer" aria-label="Open photo full size">
                  {/* eslint-disable-next-line @next/next/no-img-element -- remote photo of unknown size */}
                  <img src={img.url} alt="Facility" className="aspect-[3/2] w-full object-cover" />
                </a>
                <div className="space-y-3 p-3">
                  <div className="flex items-center justify-between gap-2">
                    <VerificationBadge status={img.status} />
                    <span className="text-xs text-muted-foreground">{formatDateTime(img.createdAt)}</span>
                  </div>
                  {img.note && <p className="text-xs text-muted-foreground">Reason given: {img.note}</p>}
                  <ReviewActions
                    id={img.id}
                    current={img.status}
                    busy={reviewImage.isPending}
                    subject="this photo"
                    placeholder="e.g. This is not a photo of the facility"
                    onReview={(status, note) => reviewImage.mutate({ imageId: img.id, status, note })}
                  />
                </div>
              </li>
            ))}
          </ul>
        )}
      </section>

      <section className="flex flex-wrap items-center justify-between gap-3 rounded-xl border border-border bg-card px-5 py-4">
        <div>
          <h2 className="text-sm font-semibold">Payout details</h2>
          <p className="text-sm text-muted-foreground">
            {data.payoutMethods.length === 0 ? "None added yet." : payoutPending > 0 ? `${payoutPending} waiting to be verified.` : "All checked."}
          </p>
        </div>
        {data.payoutMethods.length > 0 && (
          <Link href={`/admin/payouts/${f.id}`} className="text-sm font-semibold text-primary hover:underline">
            Open payout details
          </Link>
        )}
      </section>
    </div>
  );
}
