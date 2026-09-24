import { describe, expect, it } from "vitest";
import {
  charges,
  composeAddress,
  composeNotes,
  composePaymentNotes,
  fieldErrors,
  furthestReachableStep,
  isStepComplete,
  validateStep,
  WIZARD_STEPS,
  type WizardDraft,
} from "@/features/memberships/add-member-wizard";

const NOW = new Date("2026-09-23T00:00:00Z");

function draft(overrides: Partial<WizardDraft> = {}): WizardDraft {
  return {
    fullName: "Arun Kumar",
    countryCode: "+91",
    phone: "9876543210",
    email: "",
    dateOfBirth: "",
    gender: "",
    address: "",
    city: "",
    pincode: "",
    emergencyName: "",
    emergencyCountryCode: "+91",
    emergencyPhone: "",
    sendWelcome: true,
    planId: "plan-1",
    planName: "Monthly Membership",
    startDate: "2026-09-23",
    durationDays: 30,
    membershipFeeInr: 2500,
    registrationFeeInr: 0,
    gstPercent: 0,
    schedule: { facilitySportId: "sport-1", courtId: "", daysOfWeek: [], times: [] },
    paymentTab: "offline",
    paymentAmount: 2500,
    paymentDate: "2026-09-23",
    paymentMethod: "Cash",
    paymentReference: "",
    receivedFrom: "Arun Kumar",
    collectedBy: "Staff",
    paymentNotes: "",
    ...overrides,
  };
}

describe("WIZARD_STEPS", () => {
  it("is the five steps from the design, in order", () => {
    expect(WIZARD_STEPS.map((s) => s.title)).toEqual([
      "Personal Information",
      "Select Plan",
      "Playing Schedule",
      "Review & Confirm",
      "Payment",
    ]);
  });
});

describe("charges", () => {
  it("adds GST on the fee, then the registration fee", () => {
    expect(charges({ membershipFeeInr: 2000, gstPercent: 18, registrationFeeInr: 500 })).toEqual({
      subTotal: 2000,
      gstAmount: 360,
      registration: 500,
      total: 2860,
    });
  });

  it("treats negative inputs as zero rather than crediting the member", () => {
    expect(charges({ membershipFeeInr: -100, gstPercent: -5, registrationFeeInr: -10 }).total).toBe(0);
  });
});

describe("validateStep", () => {
  it("requires a name and a usable phone number", () => {
    expect(validateStep(1, draft())).toBeNull();
    expect(validateStep(1, draft({ fullName: "  " }))).toMatch(/full name/i);
    expect(validateStep(1, draft({ phone: "" }))).toMatch(/phone number/i);
    expect(validateStep(1, draft({ phone: "12345" }))).toMatch(/phone number is invalid/i);
  });

  it("accepts a phone number written with a country code", () => {
    expect(validateStep(1, draft({ phone: "+91 98765 43210" }))).toBeNull();
  });

  it("checks the pincode and the emergency contact number when given", () => {
    expect(validateStep(1, draft({ pincode: "600040" }))).toBeNull();
    expect(validateStep(1, draft({ pincode: "6000" }))).toMatch(/pincode is invalid/i);
    expect(validateStep(1, draft({ emergencyName: "Suresh", emergencyPhone: "9876512345" }))).toBeNull();
    expect(validateStep(1, draft({ emergencyPhone: "123" }))).toMatch(/emergency contact number is invalid/i);
  });

  it("only objects to an email when one was entered and it's malformed", () => {
    expect(validateStep(1, draft({ email: "" }))).toBeNull();
    expect(validateStep(1, draft({ email: "arun@club.in" }))).toBeNull();
    expect(validateStep(1, draft({ email: "not-an-email" }))).toMatch(/email address is invalid/i);
  });

  it("requires a plan with a duration and a start date", () => {
    expect(validateStep(2, draft())).toBeNull();
    expect(validateStep(2, draft({ planId: "" }))).toMatch(/membership plan is required/i);
    expect(validateStep(2, draft({ durationDays: 0 }))).toMatch(/membership plan is invalid/i);
    expect(validateStep(2, draft({ startDate: "" }))).toMatch(/start date is required/i);
  });

  it("defers the schedule step to the playing-schedule rules", () => {
    expect(validateStep(3, draft())).toBeNull(); // nothing picked — optional
    expect(
      validateStep(3, draft({ schedule: { facilitySportId: "sport-1", courtId: "", daysOfWeek: [1], times: ["06:00"] } })),
    ).not.toBeNull(); // hour picked, no court
    expect(
      validateStep(
        3,
        draft({ schedule: { facilitySportId: "sport-1", courtId: "court-1", daysOfWeek: [1], times: ["06:00"] } }),
      ),
    ).toBeNull();
  });

  it("never blocks the review step", () => {
    expect(validateStep(4, draft())).toBeNull();
  });

  it("needs a real amount on every payment tab", () => {
    expect(validateStep(5, draft())).toBeNull();
    expect(validateStep(5, draft({ paymentAmount: 0 }))).toMatch(/payment amount is required/i);
  });

  it("needs date, received-from and collected-by only on the offline/paid tabs, not the link tab", () => {
    expect(validateStep(5, draft({ paymentTab: "link", paymentDate: "", receivedFrom: "", collectedBy: "" }))).toBeNull();
    expect(validateStep(5, draft({ paymentTab: "offline", paymentDate: "" }))).toMatch(/payment date is required/i);
    expect(validateStep(5, draft({ paymentTab: "paid", receivedFrom: "" }))).toMatch(/received from is required/i);
    expect(validateStep(5, draft({ paymentTab: "paid", collectedBy: "" }))).toMatch(/collected by is required/i);
  });

  it("only requires a reference number for UPI/Bank Transfer, not Cash or Other", () => {
    expect(validateStep(5, draft({ paymentMethod: "Cash", paymentReference: "" }))).toBeNull();
    expect(validateStep(5, draft({ paymentMethod: "Other", paymentReference: "" }))).toBeNull();
    expect(validateStep(5, draft({ paymentMethod: "UPI", paymentReference: "" }))).toMatch(/reference \/ transaction id is required/i);
    expect(validateStep(5, draft({ paymentMethod: "Bank Transfer", paymentReference: "" }))).toMatch(
      /reference \/ transaction id is required/i,
    );
    expect(validateStep(5, draft({ paymentMethod: "UPI", paymentReference: "UTR123" }))).toBeNull();
    // Doesn't apply to the link tab, where nothing's been collected yet.
    expect(validateStep(5, draft({ paymentTab: "link", paymentMethod: "UPI", paymentReference: "" }))).toBeNull();
  });
});

describe("fieldErrors — Indian phone / name / pincode / GST rules", () => {
  it("requires an Indian mobile number to start with 6, 7, 8 or 9 and be exactly 10 digits", () => {
    expect(fieldErrors(1, draft({ phone: "5876543210" })).phone).toMatch(/phone number is invalid/i);
    expect(fieldErrors(1, draft({ phone: "0876543210" })).phone).toMatch(/phone number is invalid/i);
    expect(fieldErrors(1, draft({ phone: "987654321" })).phone).toBeDefined(); // 9 digits
    expect(fieldErrors(1, draft({ phone: "98765432100" })).phone).toBeDefined(); // 11 digits
    for (const first of ["6", "7", "8", "9"]) {
      expect(fieldErrors(1, draft({ phone: `${first}876543210` })).phone).toBeUndefined();
    }
  });

  it("strips a pasted +91 off the phone field before checking it", () => {
    expect(fieldErrors(1, draft({ phone: "+919876543210" })).phone).toBeUndefined();
    expect(fieldErrors(1, draft({ phone: "919876543210" })).phone).toBeUndefined();
  });

  it("only sanity-checks the length for a non-Indian code, since the 6-9 rule is India-specific", () => {
    expect(fieldErrors(1, draft({ countryCode: "+1", phone: "5876543210" })).phone).toBeUndefined();
    expect(fieldErrors(1, draft({ countryCode: "+1", phone: "123" })).phone).toBeDefined();
  });

  it("rejects a name with digits or symbols", () => {
    expect(fieldErrors(1, draft({ fullName: "Arun123" })).fullName).toBeDefined();
    expect(fieldErrors(1, draft({ fullName: "A" })).fullName).toBeDefined(); // too short
    expect(fieldErrors(1, draft({ fullName: "S. Kumar-Rao" })).fullName).toBeUndefined();
  });

  it("rejects a pincode starting with 0", () => {
    expect(fieldErrors(1, draft({ pincode: "012345" })).pincode).toBeDefined();
    expect(fieldErrors(1, draft({ pincode: "600040" })).pincode).toBeUndefined();
  });

  it("rejects a date of birth in the future or absurdly old", () => {
    expect(fieldErrors(1, draft({ dateOfBirth: "2030-01-01" }), NOW).dateOfBirth).toBeDefined();
    expect(fieldErrors(1, draft({ dateOfBirth: "1800-01-01" }), NOW).dateOfBirth).toBeDefined();
    expect(fieldErrors(1, draft({ dateOfBirth: "1998-08-12" }), NOW).dateOfBirth).toBeUndefined();
  });

  it("caps GST at India's 28% top slab", () => {
    expect(fieldErrors(2, draft({ gstPercent: 28 })).gstPercent).toBeUndefined();
    expect(fieldErrors(2, draft({ gstPercent: 29 })).gstPercent).toBeDefined();
    expect(fieldErrors(2, draft({ gstPercent: -1 })).gstPercent).toBeDefined();
  });

  it("keys each problem to its own field, not one blanket message", () => {
    const errors = fieldErrors(1, draft({ fullName: "", phone: "123", pincode: "1" }));
    expect(Object.keys(errors).sort()).toEqual(["fullName", "phone", "pincode"]);
  });
});

describe("composeAddress / composeNotes", () => {
  it("joins the address line, city and pincode", () => {
    expect(composeAddress(draft({ address: "No. 12, Anna Nagar", city: "Chennai", pincode: "600040" }))).toBe(
      "No. 12, Anna Nagar, Chennai - 600040",
    );
  });

  it("returns undefined when nothing was entered", () => {
    expect(composeAddress(draft())).toBeUndefined();
  });

  it("works with only some of the fields filled in", () => {
    expect(composeAddress(draft({ city: "Chennai" }))).toBe("Chennai");
    expect(composeAddress(draft({ pincode: "600040" }))).toBe("600040");
  });

  it("records the emergency contact as a note", () => {
    expect(composeNotes(draft({ emergencyName: "Suresh Sharma", emergencyPhone: "9876512345" }))).toBe(
      "Emergency contact: Suresh Sharma — +91 9876512345",
    );
  });

  it("returns undefined when no emergency contact was given", () => {
    expect(composeNotes(draft())).toBeUndefined();
  });
});

describe("composePaymentNotes", () => {
  it("folds the offline-payment details record_membership_payment can't store into one note", () => {
    expect(
      composePaymentNotes(
        draft({
          paymentTab: "offline",
          paymentAmount: 2500,
          paymentDate: "2026-09-23",
          paymentMethod: "Cash",
          paymentReference: "UTR123",
          receivedFrom: "Rahul Sharma",
          collectedBy: "Arjun Kumar",
          paymentNotes: "Paid in full.",
        }),
      ),
    ).toBe(
      "Payment: ₹2,500 on 2026-09-23 via Cash. Ref: UTR123. Received from Rahul Sharma, collected by Arjun Kumar. Paid in full.",
    );
  });

  it("skips the reference and free-text notes when they're empty", () => {
    expect(composePaymentNotes(draft({ paymentTab: "paid", paymentReference: "", paymentNotes: "" }))).toBe(
      "Payment: ₹2,500 on 2026-09-23 via Cash. Received from Arun Kumar, collected by Staff.",
    );
  });

  it("is undefined for the payment-link tab — there's nothing collected yet to record", () => {
    expect(composePaymentNotes(draft({ paymentTab: "link" }))).toBeUndefined();
  });
});

describe("furthestReachableStep / isStepComplete", () => {
  it("stops at the first step that isn't finished", () => {
    expect(furthestReachableStep(draft({ fullName: "" }))).toBe(1);
    expect(furthestReachableStep(draft({ planId: "" }))).toBe(2);
    expect(
      furthestReachableStep(
        draft({ schedule: { facilitySportId: "sport-1", courtId: "", daysOfWeek: [1], times: ["06:00"] } }),
      ),
    ).toBe(3);
  });

  it("reaches the end once every step is valid", () => {
    expect(furthestReachableStep(draft())).toBe(5);
  });

  it("only marks a step complete once it's behind you and valid", () => {
    expect(isStepComplete(1, draft(), 3)).toBe(true);
    expect(isStepComplete(3, draft(), 3)).toBe(false);
    expect(isStepComplete(1, draft({ fullName: "" }), 3)).toBe(false);
  });
});
