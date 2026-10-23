import { describe, expect, it } from "vitest";
import { tenDigitMobile } from "./mobile-otp";
import { resolveEntryRoute } from "@/features/auth/entry-route";

describe("tenDigitMobile", () => {
  it("accepts common Indian formats", () => {
    expect(tenDigitMobile("98765 43210")).toBe("9876543210");
    expect(tenDigitMobile("+91 98765-43210")).toBe("9876543210");
    expect(tenDigitMobile("+919876543210")).toBe("9876543210");
    expect(tenDigitMobile("09876543210")).toBe("9876543210");
  });

  it("rejects numbers that cannot be a mobile", () => {
    expect(tenDigitMobile("1234567890")).toBeNull();
    expect(tenDigitMobile("98765")).toBeNull();
    expect(tenDigitMobile("")).toBeNull();
  });
});

describe("resolveEntryRoute with a pending mobile verification", () => {
  it("sends a signed-in owner who has not verified their mobile to /verify-mobile", () => {
    expect(
      resolveEntryRoute({ signedIn: true, deviceOnboarded: true, onboardingCompleted: false, mobileVerificationPending: true }),
    ).toBe("/verify-mobile");
  });
});
