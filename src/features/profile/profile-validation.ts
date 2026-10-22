import { z } from "zod";

/** An Indian mobile number, with or without +91 / spaces: 10 digits starting 6–9. Empty is allowed. */
export function normalisePhone(input: string): string {
  return input.replace(/[\s-]/g, "").replace(/^\+?91(?=\d{10}$)/, "");
}

export const profileEditSchema = z.object({
  fullName: z.string().trim().min(2, "Enter your name.").max(80, "That name is too long."),
  phone: z
    .string()
    .trim()
    .refine((v) => v === "" || /^[6-9]\d{9}$/.test(normalisePhone(v)), "Enter a valid 10-digit mobile number."),
});

export type ProfileEditInput = z.infer<typeof profileEditSchema>;

/** "+91 98765 43210" for a stored 10-digit number; anything else is shown as stored. */
export function formatPhone(phone: string | null | undefined): string {
  if (!phone) return "";
  const n = normalisePhone(phone);
  return /^\d{10}$/.test(n) ? `+91 ${n.slice(0, 5)} ${n.slice(5)}` : phone;
}
