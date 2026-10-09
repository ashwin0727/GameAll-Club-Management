import { describe, expect, it } from "vitest";
import { featureCountLabel, planCategoryLabel, planSubtitle, planTotalAmountInr } from "@/features/memberships/plan-created";

describe("plan-created helpers", () => {
  it("totals price, joining fee and security deposit", () => {
    expect(planTotalAmountInr({ priceInr: 2500, joiningFeeInr: 200, securityDepositInr: null })).toBe(2700);
    expect(planTotalAmountInr({ priceInr: 2500, joiningFeeInr: null, securityDepositInr: null })).toBe(2500);
  });
  it("shortens the category", () => {
    expect(planCategoryLabel("Regular Membership")).toBe("Regular Plan");
    expect(planCategoryLabel("Other")).toBe("Other");
    expect(planCategoryLabel(null)).toBeNull();
  });
  it("joins category and sport", () => {
    expect(planSubtitle("Regular Membership", "Badminton")).toBe("Regular Plan • Badminton");
    expect(planSubtitle(null, "Badminton")).toBe("Badminton");
  });
  it("pluralises features", () => {
    expect(featureCountLabel(6)).toBe("6 features");
    expect(featureCountLabel(1)).toBe("1 feature");
  });
});
