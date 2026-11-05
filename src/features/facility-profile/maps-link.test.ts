import { describe, expect, it } from "vitest";
import { isGoogleMapsLink } from "@/features/facility-profile/maps-link";

describe("isGoogleMapsLink", () => {
  it.each([
    "https://maps.app.goo.gl/AbCdEf123",
    "https://goo.gl/maps/xyz",
    "https://www.google.com/maps/place/Smash+Arena/@13.08,80.27,17z",
    "https://google.co.in/maps?q=13.08,80.27",
    "https://maps.google.com/?q=13.08,80.27",
    "https://g.page/smash-arena",
    "  https://maps.app.goo.gl/AbCdEf123  ",
  ])("accepts %s", (url) => expect(isGoogleMapsLink(url)).toBe(true));

  it.each([
    "",
    "not a link",
    "maps.app.goo.gl/AbCdEf123",
    "https://example.com/maps/place",
    "https://www.google.com/search?q=turf",
    "https://goo.gl/other",
    "ftp://maps.google.com/x",
    "https://maps.app.goo.gl/",
    "https://evil.com/?https://maps.google.com",
  ])("rejects %j", (url) => expect(isGoogleMapsLink(url)).toBe(false));
});
