import { describe, expect, it } from "vitest";
import {
  draftFromOnboarding,
  emptyDraft,
  isStepValid,
  resumeStep,
  stepPayload,
  type OnboardingDraft,
} from "@/features/coaching/components/use-coach-onboarding";
import type { CoachOnboarding } from "@/features/coaching/types";

const ctx = { hasSavedPayout: false };

function withIdentity(d: OnboardingDraft): OnboardingDraft {
  return {
    ...d,
    mode: "new",
    newPerson: { firstName: "Ravi", lastName: "Kumar", phone: "9876543210", email: "ravi@x.com", roleId: "r1" },
    displayName: "Ravi Kumar",
  };
}

describe("isStepValid", () => {
  it("step 1 needs a name, a valid email and a complete phone for a new person", () => {
    const d = emptyDraft();
    expect(isStepValid(1, d, ctx)).toBe(false);
    expect(isStepValid(1, withIdentity(d), ctx)).toBe(true);
    expect(isStepValid(1, { ...withIdentity(d), newPerson: { ...withIdentity(d).newPerson, phone: "98765" } }, ctx)).toBe(false);
    expect(isStepValid(1, { ...withIdentity(d), newPerson: { ...withIdentity(d).newPerson, phone: "" } }, ctx)).toBe(false); // mandatory
    expect(isStepValid(1, { ...withIdentity(d), newPerson: { ...withIdentity(d).newPerson, email: "nope" } }, ctx)).toBe(false);
  });

  it("step 1 is valid for a picked existing staff member", () => {
    expect(isStepValid(1, { ...emptyDraft(), mode: "pick", userId: "u1", displayName: "Asha" }, ctx)).toBe(true);
    expect(isStepValid(1, { ...emptyDraft(), mode: "pick", userId: "", displayName: "Asha" }, ctx)).toBe(false);
  });

  it("step 2 needs a niche, a sport, an expertise level and a non-negative experience", () => {
    const ok = { ...emptyDraft(), niche: "Badminton", sportIds: ["s1"], expertiseLevels: ["Beginner"], experience: "5" };
    expect(isStepValid(2, ok, ctx)).toBe(true);
    expect(isStepValid(2, { ...ok, niche: "" }, ctx)).toBe(false);
    expect(isStepValid(2, { ...ok, sportIds: [] }, ctx)).toBe(false);
    expect(isStepValid(2, { ...ok, expertiseLevels: [] }, ctx)).toBe(false);
    expect(isStepValid(2, { ...ok, experience: "-1" }, ctx)).toBe(false);
  });

  it("step 3 needs a format and a duration; the three coaching amounts are optional but must be valid when filled", () => {
    const ok: OnboardingDraft = { ...emptyDraft(), sessionFormats: ["ONE_TO_ONE"], sessionDurations: [60] };
    expect(isStepValid(3, ok, ctx)).toBe(true); // all three amounts blank
    expect(isStepValid(3, { ...ok, perSessionRate: "500", weeklyRate: "2000", monthlyRate: "7000" }, ctx)).toBe(true);
    expect(isStepValid(3, { ...ok, weeklyRate: "2000" }, ctx)).toBe(true); // just one filled
    for (const bad of ["0", "-5", "10.5", "abc"]) {
      expect(isStepValid(3, { ...ok, perSessionRate: bad }, ctx)).toBe(false);
      expect(isStepValid(3, { ...ok, weeklyRate: bad }, ctx)).toBe(false);
      expect(isStepValid(3, { ...ok, monthlyRate: bad }, ctx)).toBe(false);
    }
    expect(isStepValid(3, { ...ok, sessionFormats: [] }, ctx)).toBe(false);
    expect(isStepValid(3, { ...ok, sessionDurations: [] }, ctx)).toBe(false);
  });

  const bank: OnboardingDraft["payout"] = {
    entityType: "INDIVIDUAL",
    legalName: "",
    businessAddress: "",
    taxId: "abcde 1234f",
    payoutMethod: "BANK_TRANSFER",
    accountHolderName: "Ravi Kumar",
    accountNumber: "123456789012",
    confirmAccountNumber: "123456789012",
    ifsc: "sbin 0001234",
    upiId: "",
    payoutFrequency: "MONTHLY",
    cancellationPolicy: "",
  };

  it("step 4 normalises pasted PAN/IFSC and needs a matching account-number confirmation", () => {
    const d = { ...emptyDraft(), payout: bank };
    expect(isStepValid(4, d, ctx)).toBe(true);
    expect(isStepValid(4, { ...d, payout: { ...bank, confirmAccountNumber: "123456789013" } }, ctx)).toBe(false);
    expect(isStepValid(4, { ...d, payout: { ...bank, ifsc: "abc" } }, ctx)).toBe(false);
    expect(isStepValid(4, { ...d, payout: { ...bank, taxId: "12345" } }, ctx)).toBe(false);
    expect(isStepValid(4, { ...d, payout: { ...bank, accountHolderName: "" } }, ctx)).toBe(false);
  });

  it("step 4 for UPI needs a valid UPI id and no bank fields; a business needs name + address", () => {
    const upi = { ...emptyDraft(), payout: { ...bank, payoutMethod: "UPI" as const, upiId: "ravi@okhdfc", accountNumber: "", confirmAccountNumber: "", ifsc: "" } };
    expect(isStepValid(4, upi, ctx)).toBe(true);
    expect(isStepValid(4, { ...upi, payout: { ...upi.payout, upiId: "ravi@" } }, ctx)).toBe(false);
    expect(isStepValid(4, { ...upi, payout: { ...upi.payout, entityType: "BUSINESS" } }, ctx)).toBe(false);
    expect(isStepValid(4, { ...upi, payout: { ...upi.payout, entityType: "BUSINESS", legalName: "Ravi Sports", businessAddress: "1 Main Rd" } }, ctx)).toBe(true);
  });

  it("step 4 accepts blank secrets when a payout is already saved (they are masked on screen)", () => {
    const d = { ...emptyDraft(), payout: { ...bank, taxId: "", accountNumber: "", confirmAccountNumber: "", ifsc: "" } };
    expect(isStepValid(4, d, { hasSavedPayout: false })).toBe(false);
    expect(isStepValid(4, d, { hasSavedPayout: true })).toBe(true);
  });

  it("step 5 needs all four agreements", () => {
    const all = { terms: true, ethics: true, privacy: true, commission: true };
    expect(isStepValid(5, { ...emptyDraft(), agreements: all }, ctx)).toBe(true);
    expect(isStepValid(5, { ...emptyDraft(), agreements: { ...all, commission: false } }, ctx)).toBe(false);
  });
});

describe("stepPayload", () => {
  it("converts rupees to paise (blank amounts become null) and normalises codes", () => {
    const d: OnboardingDraft = { ...emptyDraft(), sessionFormats: ["GROUP"], sessionDurations: [60], perSessionRate: "500", monthlyRate: "7000" };
    const p3 = stepPayload(3, d) as { perSessionRateMinor: number | null; weeklyRateMinor: number | null; monthlyRateMinor: number | null };
    expect(p3.perSessionRateMinor).toBe(50000);
    expect(p3.weeklyRateMinor).toBeNull();
    expect(p3.monthlyRateMinor).toBe(700000);
    const p4 = stepPayload(4, { ...d, payout: { ...emptyDraft().payout, taxId: "abcde 1234f", ifsc: "sbin 0001234" } }) as { taxId: string; ifsc: string };
    expect(p4.taxId).toBe("ABCDE1234F");
    expect(p4.ifsc).toBe("SBIN0001234");
  });
});

describe("resuming a saved draft", () => {
  const saved: CoachOnboarding = {
    coachId: "c1",
    userId: "u1",
    currentStep: 3,
    stepsDone: [1, 2],
    onboardingStatus: "DRAFT",
    payoutStatus: "PENDING",
    canManagePayouts: true,
    data: {
      displayName: "Ravi Kumar", location: "Chennai", timezone: "Asia/Kolkata", languages: ["English"], shortBio: "Hi", dateOfBirth: null,
      niche: "Badminton", subSpecialties: [], experienceYears: 5, targetAudience: ["Kids"], methodology: "", certificates: [],
      sportIds: ["s1"], expertiseLevels: ["Beginner"], sessionFormats: [], sessionDurations: [], defaultSessionDurationMinutes: null,
      perSessionRateMinor: null, weeklyRateMinor: null, monthlyRateMinor: null, availability: [],
    },
    payout: null,
  };

  it("opens at the saved step and restores the saved values (not a blank form)", () => {
    expect(resumeStep(saved)).toBe(3);
    const d = draftFromOnboarding(saved);
    expect(d.mode).toBe("pick");
    expect(d.userId).toBe("u1");
    expect(d.niche).toBe("Badminton");
    expect(d.experience).toBe("5");
    expect(d.sportIds).toEqual(["s1"]);
  });

  it("clamps a bad step into 1..5", () => {
    expect(resumeStep({ ...saved, currentStep: 9 })).toBe(5);
    expect(resumeStep({ ...saved, currentStep: 0 })).toBe(1);
  });
});
