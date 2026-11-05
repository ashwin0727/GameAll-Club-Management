"use client";

import Link from "next/link";
import { ChevronRight } from "lucide-react";
import { Skeleton } from "@/components/ui/skeleton";
import { ErrorNote, PageTitle } from "@/features/admin/components/admin-shell";
import { placeLabel } from "@/features/admin/format";
import { useVenueVerifications } from "@/features/admin/hooks";

/**
 * Venues page: the facilities that have given a Google Maps link, photos or payout details, with how many of each still need a
 * check. Open one to judge its location and photos (and jump to its payout details).
 */
export function AdminVenuesPage() {
  const { data, isLoading, error } = useVenueVerifications();

  return (
    <div>
      <PageTitle
        title="Venues"
        subtitle="Check each facility's Google Maps link and photos. Verified photos are what players see in the Player app; payout details are checked on the Payouts page."
      />
      {error ? (
        <ErrorNote error={error} />
      ) : isLoading ? (
        <Skeleton className="h-64 w-full rounded-xl" />
      ) : !data?.length ? (
        <p className="rounded-xl border border-border bg-card p-10 text-center text-sm text-muted-foreground">Nothing has been submitted for checking yet.</p>
      ) : (
        <ul className="divide-y divide-border overflow-hidden rounded-xl border border-border bg-card">
          {data.map((v) => {
            const locationPending = v.locationStatus === "PENDING";
            return (
              <li key={v.id}>
                <Link href={`/admin/venues/${v.id}`} className="flex items-center gap-4 px-4 py-4 transition-colors hover:bg-secondary/60 sm:px-5">
                  <div className="min-w-0 flex-1">
                    <p className="truncate font-semibold">{v.name}</p>
                    <p className="mt-0.5 truncate text-sm text-muted-foreground">
                      {v.ownerName ?? "—"} · {v.ownerEmail ?? "—"} · {placeLabel(v.city)}
                    </p>
                  </div>
                  <div className="flex shrink-0 flex-wrap justify-end gap-1.5 text-xs font-semibold">
                    {v.locationStatus === null && <span className="rounded-full bg-muted px-2.5 py-0.5 text-muted-foreground">No map link</span>}
                    {locationPending && <span className="rounded-full bg-warning/15 px-2.5 py-0.5 text-warning">Location to verify</span>}
                    {v.locationStatus === "VERIFIED" && <span className="rounded-full bg-primary/10 px-2.5 py-0.5 text-primary">Location verified</span>}
                    {v.locationStatus === "REJECTED" && <span className="rounded-full bg-destructive/10 px-2.5 py-0.5 text-destructive">Location rejected</span>}
                    {v.imagesTotal === 0 && <span className="rounded-full bg-muted px-2.5 py-0.5 text-muted-foreground">No photos</span>}
                    {v.imagesPending > 0 && <span className="rounded-full bg-warning/15 px-2.5 py-0.5 text-warning">{v.imagesPending} photo{v.imagesPending === 1 ? "" : "s"} to verify</span>}
                    {v.imagesVerified > 0 && <span className="rounded-full bg-primary/10 px-2.5 py-0.5 text-primary">{v.imagesVerified} photo{v.imagesVerified === 1 ? "" : "s"} verified</span>}
                    {v.imagesRejected > 0 && <span className="rounded-full bg-destructive/10 px-2.5 py-0.5 text-destructive">{v.imagesRejected} rejected</span>}
                    {v.payoutsPending > 0 && <span className="rounded-full bg-warning/15 px-2.5 py-0.5 text-warning">{v.payoutsPending} payout to verify</span>}
                  </div>
                  <ChevronRight className="h-4 w-4 shrink-0 text-muted-foreground" aria-hidden />
                </Link>
              </li>
            );
          })}
        </ul>
      )}
    </div>
  );
}
