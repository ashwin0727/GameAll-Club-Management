import { describe, expect, it } from "vitest";
import { resolveEntryRoute } from "@/features/auth/entry-route";
import { safeRedirectPath } from "@/lib/redirects";

describe("resolveEntryRoute", () => {
  it("sends a first-time visitor from splash to welcome", () => {
    expect(resolveEntryRoute({ signedIn: false, deviceOnboarded: false })).toBe("/welcome");
  });

  it("sends a returning signed-out visitor from splash to login", () => {
    expect(resolveEntryRoute({ signedIn: false, deviceOnboarded: true })).toBe("/login");
  });

  it("sends a signed-in user from splash to the dashboard", () => {
    expect(resolveEntryRoute({ signedIn: true, deviceOnboarded: true })).toBe("/dashboard");
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