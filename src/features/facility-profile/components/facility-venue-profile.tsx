"use client";

import { useQuery } from "@tanstack/react-query";
import { ExternalLink } from "lucide-react";
import { FacilityPhotos } from "@/features/facility-profile/photos";
import { AMENITY_OPTIONS, NO_AMENITIES, type VerificationStatus } from "@/features/facility-profile/types";
import type { Facility } from "@/features/onboarding/types";
import { cn } from "@/lib/utils";

const STATUS: Record<VerificationStatus, { label: string; className: string }> = {
  PENDING: { label: "Waiting for GameAll to verify", className: "bg-warning/15 text-warning" },
  VERIFIED: { label: "Verified", className: "bg-success/15 text-success" },
  REJECTED: { label: "Rejected", className: "bg-destructive/10 text-destructive" },
};

function StatusChip({ status }: { status: VerificationStatus }) {
  return <span className={cn("inline-block rounded-full px-2 py-0.5 text-[11px] font-semibold", STATUS[status].className)}>{STATUS[status].label}</span>;
}

/** The venue profile on the owner's page: map link and its check, indoor/outdoor, amenities and photos with their checks. */
export function FacilityVenueProfile({ facility }: { facility: Facility }) {
  const { data: images } = useQuery({
    queryKey: ["facility-images", facility.id],
    queryFn: () => new FacilityPhotos().list(facility.id),
  });
  const amenities = facility.amenities ?? NO_AMENITIES;
  const on = AMENITY_OPTIONS.filter((a) => amenities[a.key]);
  const location = facility.locationVerification;

  return (
    <div className="space-y-5 sm:col-span-2">
      <dl className="grid gap-4 sm:grid-cols-2">
        <div>
          <dt className="text-xs font-medium uppercase tracking-wide text-muted-foreground">Venue type</dt>
          <dd className="mt-0.5 text-sm font-medium">{facility.venueType === "INDOOR" ? "Indoor" : facility.venueType === "OUTDOOR" ? "Outdoor" : "—"}</dd>
        </div>
        <div>
          <dt className="text-xs font-medium uppercase tracking-wide text-muted-foreground">Amenities</dt>
          <dd className="mt-0.5 text-sm font-medium">{on.length === 0 ? "None" : on.map((a) => a.label).join(", ")}</dd>
        </div>
        <div className="sm:col-span-2">
          <dt className="text-xs font-medium uppercase tracking-wide text-muted-foreground">Google Maps location</dt>
          <dd className="mt-0.5 space-y-1 text-sm font-medium">
            {facility.locationUrl ? (
              <>
                <a href={facility.locationUrl} target="_blank" rel="noopener noreferrer" className="inline-flex max-w-full items-center gap-1.5 break-all text-primary hover:underline">
                  {facility.locationUrl} <ExternalLink className="h-3.5 w-3.5 shrink-0" aria-hidden />
                </a>
                <div className="space-y-1">
                  {location && <StatusChip status={location.status} />}
                  {location?.status === "REJECTED" && location.note && <p className="text-xs text-destructive">{location.note}</p>}
                </div>
              </>
            ) : (
              "—"
            )}
          </dd>
        </div>
      </dl>

      {images && images.length > 0 && (
        <div>
          <p className="mb-2 text-xs font-medium uppercase tracking-wide text-muted-foreground">Photos</p>
          <ul className="grid grid-cols-2 gap-3 sm:grid-cols-4">
            {images.map((img, i) => (
              <li key={img.id} className="space-y-1.5">
                {/* eslint-disable-next-line @next/next/no-img-element -- remote photo of unknown size */}
                <img src={img.url} alt={`Facility photo ${i + 1}`} className="aspect-[4/3] w-full rounded-lg border border-border object-cover" />
                <StatusChip status={img.status} />
                {img.status === "REJECTED" && img.note && <p className="text-xs text-destructive">{img.note}</p>}
              </li>
            ))}
          </ul>
        </div>
      )}
    </div>
  );
}
