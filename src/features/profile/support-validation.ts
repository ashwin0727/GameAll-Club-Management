import { z } from "zod";

export const SUPPORT_CATEGORIES = [
  { value: "GENERAL", label: "General question" },
  { value: "BILLING", label: "My GameAll plan & billing" },
  { value: "BOOKINGS", label: "Bookings" },
  { value: "PAYMENTS", label: "Payments & payouts" },
  { value: "TECHNICAL", label: "Something isn't working" },
  { value: "OTHER", label: "Other" },
] as const;

export const supportTicketSchema = z.object({
  category: z.enum(["GENERAL", "BILLING", "BOOKINGS", "PAYMENTS", "TECHNICAL", "OTHER"]),
  subject: z.string().trim().min(3, "Add a short subject (at least 3 characters).").max(140),
  message: z.string().trim().min(10, "Tell us a little more (at least 10 characters).").max(4000),
});
