import { z } from "zod";

export const createMemberSchema = z.object({
  full_name: z.string().min(2, "Name must be at least 2 characters"),
  email: z.string().min(1, "Email is required").email("Enter a valid email"),
  phone: z
    .string()
    .regex(/^[6-9]\d{9}$/, "Enter a valid 10-digit Indian mobile number")
    .optional()
    .or(z.literal("")),
});

export type CreateMemberInput = z.infer<typeof createMemberSchema>;