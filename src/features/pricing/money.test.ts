import { describe, expect, it } from "vitest";
import { fromMinorUnits, formatCurrency, toMinorUnits } from "@/features/pricing/money";

describe("toMinorUnits", () => {
  it("converts a whole rupee amount to paise", () => {
    expect(toMinorUnits("400", "INR")).toBe(40000);
  });

  it("converts a fractional amount to paise", () => {
    expect(toMinorUnits("400.50", "INR")).toBe(40050);
  });

  it("pads a short fraction", () => {
    expect(toMinorUnits("400.5", "INR")).toBe(40050);
  });

  it("truncates an over-long fraction rather than rounding unpredictably", () => {
    expect(toMinorUnits("400.999", "INR")).toBe(40099);
  });
});

describe("fromMinorUnits", () => {
  it("converts paise back to a rupee amount", () => {
    expect(fromMinorUnits(40000, "INR")).toBe(400);
  });

  it("round-trips through toMinorUnits", () => {
    expect(fromMinorUnits(toMinorUnits("1500", "INR"), "INR")).toBe(1500);
  });
});

describe("formatCurrency", () => {
  it("formats a whole amount without decimals", () => {
    expect(formatCurrency(40000, "INR")).toBe("₹400");
  });

  it("formats a fractional amount with two decimals", () => {
    expect(formatCurrency(40050, "INR")).toBe("₹400.50");
  });

  it("uses Indian digit grouping for large amounts", () => {
    expect(formatCurrency(150000, "INR")).toBe("₹1,500");
  });
});