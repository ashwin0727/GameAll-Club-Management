"use client";

import Image from "next/image";
import Link from "next/link";
import { useEffect, useMemo, useState } from "react";
import { ArrowRight, CalendarCheck2, CircleAlert, ShieldCheck, WalletCards } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Skeleton } from "@/components/ui/skeleton";
import { BrandLogo } from "@/features/auth/components/brand-mark";
import { PublicBookingHeader } from "./public-booking-header";
import { APP_NAME } from "@/lib/constants";
import { cn } from "@/lib/utils";
import { getPublicBookingFacility } from "../public-booking";
import { nextHeroImageFallback, resolveFacilityHeroImage, type HeroImage } from "../hero-image";
import type { PublicBookingFacility } from "../types";

const FEATURES = [
  {
    icon: CalendarCheck2,
    title: "Easy Booking",
    body: "Book your favorite court in just a few steps.",
  },
  {
    icon: ShieldCheck,
    title: "Instant Confirmation",
    body: "Get real-time confirmation of your booking.",
  },
  {
    icon: WalletCards,
    title: "Pay at Venue",
    body: "Convenient offline payment at the venue.",
  },
];

/**
 * Step 0 of the public journey: the venue's own front door.
 *
 * Holds no booking logic — it names the venue, shows the sport, and hands
 * off to the existing flow at /book/<id>/booking with the facility already
 * chosen, so the player never picks it twice.
 */
export function PublicBookingLanding({ facilityId }: { facilityId: string }) {
  const [facility, setFacility] = useState<PublicBookingFacility | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let active = true;
    getPublicBookingFacility(facilityId)
      .then((f) => active && setFacility(f))
      .finally(() => active && setLoading(false));
    return () => {
      active = false;
    };
  }, [facilityId]);

  if (loading) return <LandingSkeleton />;
  if (!facility) return <FacilityNotFound />;

  return (
    <div className="mx-auto w-full max-w-5xl px-4 py-6 sm:py-10">
      <div className="overflow-hidden rounded-2xl border border-border bg-card shadow-sm">
        <PublicBookingHeader helpPhone={facility.helpPhone} />

        <div className="px-4 pb-8 pt-6 sm:px-8 sm:pb-10">
          <FacilityHero facility={facility} />

          <BookingFeatureHighlights />

          <div className="mt-8 flex flex-col items-center gap-3">
            <Button asChild size="lg" className="min-h-12 w-full sm:w-auto sm:min-w-64">
              <Link href={`/book/${facilityId}/booking`}>
                Start Booking <ArrowRight className="h-4 w-4" aria-hidden />
              </Link>
            </Button>
            <p className="text-xs text-muted-foreground">
              <ShieldCheck className="mr-1 inline h-3.5 w-3.5 text-primary" aria-hidden />
              Secure · Simple · Reliable
            </p>
          </div>
        </div>

        <PublicBookingFooter />
      </div>
    </div>
  );
}

function FacilityHero({ facility }: { facility: PublicBookingFacility }) {
  // The landing page shows one sport's artwork; a multi-sport venue leads
  // with its first, and the player picks properly on the next step.
  const sport = facility.sports[0] ?? null;
  const initial = useMemo(() => resolveFacilityHeroImage(facility, sport), [facility, sport]);
  const [image, setImage] = useState<HeroImage>(initial);

  useEffect(() => setImage(initial), [initial]);

  return (
    <section className="text-center">
      <p className="text-sm text-muted-foreground">Welcome to</p>
      <h1 className="mt-1 text-2xl font-bold tracking-tight text-primary sm:text-4xl">
        {facility.facilityName}
      </h1>
      <p className="mt-1 text-sm text-muted-foreground sm:text-base">Your game starts here.</p>

      <FacilityHeroImage
        image={image}
        facility={facility}
        onError={() => setImage((current) => nextHeroImageFallback(current, sport))}
      />
    </section>
  );
}

function FacilityHeroImage({
  image,
  facility,
  onError,
}: {
  image: HeroImage;
  facility: PublicBookingFacility;
  onError: () => void;
}) {
  return (
    <div
      className={cn(
        "relative mt-5 w-full overflow-hidden rounded-xl border border-border",
        // 16:9 on mobile, wider and shallower on desktop, so the court fills
        // the card without the image being stretched to fit.
        "aspect-[16/9] sm:aspect-[16/7]",
      )}
    >
      {image.src ? (
        <>
          <Image
            src={image.src}
            alt={image.alt}
            fill
            sizes="(max-width: 640px) 100vw, 1024px"
            className="object-cover"
            onError={onError}
            priority
          />
          {/* Just enough to keep any overlaid text legible — the court should
              still read as the subject of the photograph. */}
          <div
            className="pointer-events-none absolute inset-0 bg-gradient-to-t from-black/35 via-transparent to-transparent"
            aria-hidden
          />
        </>
      ) : (
        <FacilityImageFallback facility={facility} />
      )}
    </div>
  );
}

/** Shown when no image is configured and we ship no artwork for the sport. */
function FacilityImageFallback({ facility }: { facility: PublicBookingFacility }) {
  return (
    <div className="flex h-full w-full flex-col items-center justify-center gap-2 bg-gradient-to-br from-primary/15 via-muted to-background px-6 text-center">
      <BrandLogo className="h-10 w-10" />
      <p className="text-base font-semibold sm:text-lg">{facility.facilityName}</p>
      <p className="text-xs text-muted-foreground">Your game starts here.</p>
    </div>
  );
}

function BookingFeatureHighlights() {
  return (
    <ul className="mt-7 grid gap-3 sm:grid-cols-3">
      {FEATURES.map(({ icon: Icon, title, body }) => (
        <li key={title} className="flex items-start gap-3 rounded-xl border border-border p-4 sm:flex-col sm:items-center sm:text-center">
          <span className="flex h-9 w-9 shrink-0 items-center justify-center rounded-lg bg-primary/12 text-primary">
            <Icon className="h-4.5 w-4.5" aria-hidden />
          </span>
          <div className="min-w-0">
            <p className="text-sm font-semibold">{title}</p>
            <p className="mt-0.5 text-xs text-muted-foreground">{body}</p>
          </div>
        </li>
      ))}
    </ul>
  );
}

function PublicBookingFooter() {
  return (
    <footer className="border-t border-border px-4 py-4 text-center sm:px-8">
      <p className="text-[11px] text-muted-foreground">
        © {new Date().getFullYear()} {APP_NAME}. All rights reserved.
      </p>
    </footer>
  );
}

function LandingSkeleton() {
  return (
    <div className="mx-auto w-full max-w-5xl px-4 py-6 sm:py-10" aria-busy>
      <div className="overflow-hidden rounded-2xl border border-border bg-card">
        <div className="flex items-center justify-between gap-3 border-b border-border px-4 py-4 sm:px-8">
          <div className="flex items-center gap-2.5">
            <Skeleton className="h-8 w-8 rounded-lg" />
            <Skeleton className="h-4 w-24" />
          </div>
          <Skeleton className="h-8 w-28" />
        </div>
        <div className="space-y-5 px-4 pb-8 pt-6 sm:px-8">
          <div className="flex flex-col items-center gap-2">
            <Skeleton className="h-3 w-20" />
            <Skeleton className="h-8 w-56" />
            <Skeleton className="h-3 w-40" />
          </div>
          <Skeleton className="aspect-[16/9] w-full rounded-xl sm:aspect-[16/7]" />
          <div className="grid gap-3 sm:grid-cols-3">
            {[0, 1, 2].map((i) => (
              <Skeleton key={i} className="h-20 rounded-xl" />
            ))}
          </div>
          <div className="flex justify-center">
            <Skeleton className="h-12 w-full sm:w-64" />
          </div>
        </div>
      </div>
    </div>
  );
}

function FacilityNotFound() {
  return (
    <div className="mx-auto w-full max-w-md px-4 py-16 text-center">
      <span className="mx-auto flex h-14 w-14 items-center justify-center rounded-full bg-muted">
        <CircleAlert className="h-7 w-7 text-muted-foreground" aria-hidden />
      </span>
      <h1 className="mt-4 text-lg font-semibold">Facility Not Found</h1>
      <p className="mt-1 text-sm text-muted-foreground">
        We couldn&apos;t find this booking page. Please check the link and try again.
      </p>
      <Button asChild variant="outline" className="mt-6 min-h-11">
        <Link href="/">Back to {APP_NAME}</Link>
      </Button>
    </div>
  );
}
