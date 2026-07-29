import { z } from "zod";
import type { Role } from "@/types/database.types";

export const memberSchema = z.object({
  id: z.string().uuid(),
  full_name: z.string().min(1),
  phone: z.string().nullable(),
  role: z.custom<Role>(),
  created_at: z.string(),
});

export type Member = z.infer<typeof memberSchema>;

export interface MembersPage {
  members: Member[];
  totalCount: number;
}

export interface MembersQuery {
  search: string;
  page: number;
  pageSize: number;
}