import { describe, expect, it } from "vitest";
import { resolveEntryRoute } from "@/features/auth/entry-route";
import { safeRedirectPath } from "@/lib/redirects";

describe("resolveEntryRoute", () => {
  it("sends a first-time visitor from splash to welcome", () => {
    expect(
      resolveEntryRoute({ signedIn: false, deviceOnboarded: false, onboardingCompleted: false }),
    ).toBe("/welcome");
  });

  it("sends a returning signed-out visitor from splash to login", () => {
    expect(
      resolveEntryRoute({ signedIn: false, deviceOnboarded: true, onboardingCompleted: false }),
    ).toBe("/login");
  });

  it("sends a signed-in, fully onboarded user from splash to the dashboard", () => {
    expect(
      resolveEntryRoute({ signedIn: true, deviceOnboarded: true, onboardingCompleted: true }),
    ).toBe("/dashboard");
  });

  it("sends a signed-in user who hasn't finished facility setup to onboarding", () => {
    expect(
      resolveEntryRoute({ signedIn: true, deviceOnboarded: true, onboardingCompleted: false }),
    ).toBe("/onboarding/facility");
  });
});

describe("safeRedirectPath", () => {
  it("keeps an in-app path", () => {
    expect(safeRedirectPath("/reset-password")).toBe("/reset-password");
  });

  it.each(["https://evil.example.com", "//evil.example.com", "/\\evil.example.com", "", null])(
    "falls back for %s",
    (raw) => {
      expect(safeRedirectPath(raw)).toBe("/login");
    },
  );
});