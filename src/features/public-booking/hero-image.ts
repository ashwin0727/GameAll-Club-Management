import type { PublicBookingFacility, PublicBookingSport } from "./types";

/**
 * Sport slugs from the `sports` catalogue seeded in 0001_init. Kept here as
 * the set we ship artwork for — anything outside it falls back to the
 * branded panel rather than guessing at a filename that doesn't exist.
 */
export const SPORT_IMAGE_KEYS = [
  "badminton",
  "pickleball",
  "cricket",
  "football",
  "tennis",
] as const;

export type SportImageKey = (typeof SPORT_IMAGE_KEYS)[number];

export interface HeroImage {
  /** `null` means: render the branded fallback panel, not an <img>. */
  src: string | null;
  alt: string;
  /** Where the choice came from — surfaced for tests and debugging. */
  source: "facility" | "sport" | "none";
}

function isSportImageKey(key: string | null | undefined): key is SportImageKey {
  return !!key && (SPORT_IMAGE_KEYS as readonly string[]).includes(key);
}

/**
 * Chooses the hero image for a facility's landing page, in priority order:
 *
 *   1. the image the owner configured for this venue
 *   2. artwork for the sport being booked
 *   3. nothing — the caller renders a branded panel instead
 *
 * Deliberately never returns a badminton court for a football turf: with no
 * sport match and no configured image, it returns `null` so the page shows
 * the venue's name over a branded background rather than the wrong sport.
 */
export function resolveFacilityHeroImage(
  facility: Pick<PublicBookingFacility, "facilityName" | "heroImageUrl">,
  sport?: Pick<PublicBookingSport, "name" | "sportKey"> | null,
): HeroImage {
  const configured = facility.heroImageUrl?.trim();
  if (configured) {
    return {
      src: configured,
      alt: `${facility.facilityName}`,
      source: "facility",
    };
  }

  if (isSportImageKey(sport?.sportKey)) {
    return {
      src: `/sports/${sport.sportKey}.jpg`,
      alt: `${sport.name} court at ${facility.facilityName}`,
      source: "sport",
    };
  }

  return {
    src: null,
    alt: facility.facilityName,
    source: "none",
  };
}

/**
 * The step after a chosen image fails to load in the browser. A configured
 * image that 404s drops to the sport's artwork; sport artwork that is
 * missing drops to the branded panel. Prevents a broken-image icon on a
 * page whose whole job is to look trustworthy.
 */
export function nextHeroImageFallback(current: HeroImage, sport?: Pick<PublicBookingSport, "name" | "sportKey"> | null): HeroImage {
  if (current.source === "facility" && isSportImageKey(sport?.sportKey)) {
    return {
      src: `/sports/${sport.sportKey}.jpg`,
      alt: `${sport.name} court`,
      source: "sport",
    };
  }
  return { src: null, alt: current.alt, source: "none" };
}
