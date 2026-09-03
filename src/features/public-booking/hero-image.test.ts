import { describe, expect, it } from "vitest";
import { nextHeroImageFallback, resolveFacilityHeroImage } from "./hero-image";

const facility = (heroImageUrl?: string | null) => ({
  facilityName: "Skyline Arena",
  heroImageUrl: heroImageUrl ?? null,
});

const sport = (sportKey: string | null, name = "Badminton") => ({ name, sportKey });

describe("resolveFacilityHeroImage", () => {
  it("prefers the image the owner configured for the venue", () => {
    const result = resolveFacilityHeroImage(facility("https://cdn/x.jpg"), sport("badminton"));
    expect(result).toMatchObject({ src: "https://cdn/x.jpg", source: "facility" });
  });

  it("ignores a configured value that is only whitespace", () => {
    expect(resolveFacilityHeroImage(facility("   "), sport("badminton")).source).toBe("sport");
  });

  it("falls back to artwork for the sport being booked", () => {
    expect(resolveFacilityHeroImage(facility(), sport("football", "Football")).src).toBe("/sports/football.jpg");
  });

  it("picks the sport's own image, not a generic one", () => {
    // The whole point: a football turf must never render a badminton court.
    expect(resolveFacilityHeroImage(facility(), sport("cricket", "Cricket")).src).toBe("/sports/cricket.jpg");
    expect(resolveFacilityHeroImage(facility(), sport("tennis", "Tennis")).src).toBe("/sports/tennis.jpg");
    expect(resolveFacilityHeroImage(facility(), sport("pickleball", "Pickleball")).src).toBe("/sports/pickleball.jpg");
  });

  it("returns no image for a sport we don't ship artwork for", () => {
    // Better a branded panel than the wrong sport's photograph.
    const result = resolveFacilityHeroImage(facility(), sport("kabaddi", "Kabaddi"));
    expect(result).toMatchObject({ src: null, source: "none" });
  });

  it("returns no image when there is no sport at all", () => {
    expect(resolveFacilityHeroImage(facility(), null).source).toBe("none");
  });

  it("describes the image for screen readers", () => {
    expect(resolveFacilityHeroImage(facility(), sport("badminton")).alt).toBe(
      "Badminton court at Skyline Arena",
    );
    expect(resolveFacilityHeroImage(facility("https://cdn/x.jpg")).alt).toBe("Skyline Arena");
  });
});

describe("nextHeroImageFallback", () => {
  it("drops a broken venue image to the sport's artwork", () => {
    const first = resolveFacilityHeroImage(facility("https://cdn/broken.jpg"), sport("tennis", "Tennis"));
    expect(nextHeroImageFallback(first, sport("tennis", "Tennis"))).toMatchObject({
      src: "/sports/tennis.jpg",
      source: "sport",
    });
  });

  it("drops broken sport artwork to the branded panel", () => {
    const first = resolveFacilityHeroImage(facility(), sport("tennis", "Tennis"));
    expect(nextHeroImageFallback(first, sport("tennis", "Tennis")).src).toBeNull();
  });

  it("drops a broken venue image straight to the panel when the sport has no artwork", () => {
    const first = resolveFacilityHeroImage(facility("https://cdn/broken.jpg"), sport("kabaddi", "Kabaddi"));
    expect(nextHeroImageFallback(first, sport("kabaddi", "Kabaddi")).src).toBeNull();
  });
});
