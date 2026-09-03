import { describe, expect, it } from "vitest";
import { routeAction } from "./public-routes";

const SIGNED_OUT = false;
const SIGNED_IN = true;

describe("routeAction — public booking and membership links", () => {
  it("lets a signed-out player open a booking link", () => {
    expect(routeAction("/book/facility-123", SIGNED_OUT)).toBe("allow");
  });

  it("lets a signed-out player open a membership join link", () => {
    expect(routeAction("/join/facility-123", SIGNED_OUT)).toBe("allow");
  });

  it("does not bounce a signed-in owner previewing their own booking page", () => {
    // Bouncing to /dashboard here would also break the embedded widget for
    // any visitor who happens to have an account.
    expect(routeAction("/book/facility-123", SIGNED_IN)).toBe("allow");
  });

  it("does not bounce a signed-in user off a join link", () => {
    expect(routeAction("/join/facility-123", SIGNED_IN)).toBe("allow");
  });

  it("allows the embed query form of a booking link", () => {
    expect(routeAction("/book/facility-123", SIGNED_OUT)).toBe("allow");
  });

  it("does not treat a lookalike prefix as public", () => {
    expect(routeAction("/bookings", SIGNED_OUT)).toBe("to-login");
    expect(routeAction("/bookings/new", SIGNED_OUT)).toBe("to-login");
  });
});

describe("routeAction — management pages stay guarded", () => {
  it.each([
    "/dashboard",
    "/guest-bookings",
    "/memberships",
    "/finance",
    "/membership-sessions",
  ])("sends a signed-out visitor from %s to login", (path) => {
    expect(routeAction(path, SIGNED_OUT)).toBe("to-login");
  });

  it("lets a signed-in user into the dashboard", () => {
    expect(routeAction("/dashboard", SIGNED_IN)).toBe("allow");
  });
});

describe("routeAction — auth screens", () => {
  it("lets a signed-out visitor reach login and signup", () => {
    expect(routeAction("/login", SIGNED_OUT)).toBe("allow");
    expect(routeAction("/signup", SIGNED_OUT)).toBe("allow");
  });

  it("bounces a signed-in user off the signed-out screens", () => {
    expect(routeAction("/login", SIGNED_IN)).toBe("to-dashboard");
    expect(routeAction("/signup", SIGNED_IN)).toBe("to-dashboard");
  });

  it("keeps the session-tolerant routes reachable while signed in", () => {
    expect(routeAction("/reset-password", SIGNED_IN)).toBe("allow");
    expect(routeAction("/", SIGNED_IN)).toBe("allow");
  });
});
