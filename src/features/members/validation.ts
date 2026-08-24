import { z } from "zod";

const PHONE_RE = /^[6-9]\d{9}$/;

/** A Member is a facility customer record, not a login — name and mobile number are the only required fields. */
export const memberFormSchema = z.object({
  full_name: z.string().min(2, "Name must be at least 2 characters"),
  phone: z.string().regex(PHONE_RE, "Enter a valid 10-digit Indian mobile number"),
  email: z.string().email("Enter a valid email").optional().or(z.literal("")),
  date_of_birth: z.string().optional().or(z.literal("")),
  gender: z.string().optional().or(z.literal("")),
  notes: z.string().optional().or(z.literal("")),
});

export type MemberFormInput = z.infer<typeof memberFormSchema>;

export function validateMemberName(name: string): string | null {
  if (name.trim().length === 0) return "Member name is required.";
  if (name.trim().length < 2) return "Enter at least 2 characters.";
  return null;
}

export function validateMemberPhone(phone: string): string | null {
  if (phone.trim().length === 0) return "Mobile number is required.";
  if (!PHONE_RE.test(phone.trim())) return "Enter a valid 10-digit mobile number.";
  return null;
}