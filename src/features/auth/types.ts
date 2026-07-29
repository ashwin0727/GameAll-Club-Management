import { z } from "zod";
import type { Role } from "@/types/database.types";

export const profileSchema = z.object({
  id: z.string().uuid(),
  full_name: z.string().min(1),
  avatar_url: z.string().url().nullable(),
  role: z.enum(["admin", "staff", "member"]),
  phone: z.string().nullable(),
  created_at: z.string(),
});

export type Profile = z.infer<typeof profileSchema>;
export type { Role };