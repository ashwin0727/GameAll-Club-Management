import { describe, expect, it } from "vitest";
import { resolveTournamentAppLinks, type TournamentAppConfig } from "@/config/tournament-app";

function config(over: Partial<TournamentAppConfig> = {}): TournamentAppConfig {
  return {
    webUrl: null,
    deepLink: null,
    androidStoreUrl: null,
    iosStoreUrl: null,
    previewImages: [{ src: "/x.png", label: "x" }],
    ...over,
  };
}

describe("resolveTournamentAppLinks", () => {
  it("returns no links and no CTAs when nothing is configured", () => {
    const r = resolveTournamentAppLinks(config());
    expect(r.openUrl).toBeNull();
    expect(r.hasStores).toBe(false);
    expect(r.availabilityLabel).toBeNull();
  });

  it("prefers the web URL for openUrl", () => {
    const r = resolveTournamentAppLinks(
      config({ webUrl: "https://web", deepLink: "app://x", androidStoreUrl: "https://play" }),
    );
    expect(r.openUrl).toBe("https://web");
  });

  it("falls back web → deep link → android → ios", () => {
    expect(resolveTournamentAppLinks(config({ deepLink: "app://x", iosStoreUrl: "https://ios" })).openUrl).toBe("app://x");
    expect(resolveTournamentAppLinks(config({ iosStoreUrl: "https://ios" })).openUrl).toBe("https://ios");
  });

  it("labels platform availability from the store links present", () => {
    expect(resolveTournamentAppLinks(config({ androidStoreUrl: "a", iosStoreUrl: "i" })).availabilityLabel).toBe(
      "Available on Android and iOS",
    );
    expect(resolveTournamentAppLinks(config({ androidStoreUrl: "a" })).availabilityLabel).toBe("Available on Android");
    expect(resolveTournamentAppLinks(config({ iosStoreUrl: "i" })).availabilityLabel).toBe("Available on iOS");
  });

  it("sets hasStores when either store link exists", () => {
    expect(resolveTournamentAppLinks(config({ androidStoreUrl: "a" })).hasStores).toBe(true);
    expect(resolveTournamentAppLinks(config({ webUrl: "https://web" })).hasStores).toBe(false);
  });
});
