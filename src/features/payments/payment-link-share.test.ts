import { describe, expect, it } from "vitest";
import { paymentLinkMessage, whatsappNumber, whatsappShareUrl } from "@/features/payments/payment-link-share";

describe("whatsappNumber", () => {
  it("adds 91 to a bare 10-digit mobile and strips punctuation", () => {
    expect(whatsappNumber("98765 43210")).toBe("919876543210");
    expect(whatsappNumber("+91 98765-43210")).toBe("919876543210");
    expect(whatsappNumber("919876543210")).toBe("919876543210");
  });
  it("is null for something that is not a number", () => {
    expect(whatsappNumber("12345")).toBeNull();
    expect(whatsappNumber(null)).toBeNull();
  });
});

describe("paymentLinkMessage / whatsappShareUrl", () => {
  const message = paymentLinkMessage({ guestName: "Arun", description: "Court 1 · 20 Oct, 6:00 PM", amountLabel: "₹800.00", url: "https://rzp.io/i/abc" });
  it("greets, states the amount and carries the link", () => {
    expect(message).toBe("Hi Arun, please pay ₹800.00 to confirm your booking (Court 1 · 20 Oct, 6:00 PM): https://rzp.io/i/abc");
  });
  it("opens WhatsApp on the guest's number, or the contact picker without one", () => {
    expect(whatsappShareUrl("9876543210", message)).toBe(`https://wa.me/919876543210?text=${encodeURIComponent(message)}`);
    expect(whatsappShareUrl("", message).startsWith("https://wa.me/?text=")).toBe(true);
  });
});
