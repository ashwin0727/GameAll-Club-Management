import { describe, expect, it } from "vitest";
import { queryRetryDelay, shouldRetryQuery } from "@/providers/query-retry";

describe("shouldRetryQuery", () => {
  it("retries a dropped connection once", () => {
    expect(shouldRetryQuery(0, new TypeError("Failed to fetch"))).toBe(true);
    expect(shouldRetryQuery(1, new TypeError("Failed to fetch"))).toBe(false);
  });

  it("does not repeat permission and database errors", () => {
    expect(shouldRetryQuery(0, { code: "42501", message: "You don't have permission" })).toBe(false);
    expect(shouldRetryQuery(0, { code: "23514" })).toBe(false);
    expect(shouldRetryQuery(0, { code: "P0002" })).toBe(false);
    expect(shouldRetryQuery(0, { status: 403 })).toBe(false);
    expect(shouldRetryQuery(0, { status: 404 })).toBe(false);
  });

  it("does retry a busy server and a timeout", () => {
    expect(shouldRetryQuery(0, { status: 503 })).toBe(true);
    expect(shouldRetryQuery(0, { status: 429 })).toBe(true);
    expect(shouldRetryQuery(0, { status: 408 })).toBe(true);
  });
});

describe("queryRetryDelay", () => {
  it("grows and is capped", () => {
    expect(queryRetryDelay(0)).toBeGreaterThanOrEqual(1_000);
    expect(queryRetryDelay(1)).toBeGreaterThanOrEqual(2_000);
    expect(queryRetryDelay(10)).toBeLessThan(8_400);
  });
});
