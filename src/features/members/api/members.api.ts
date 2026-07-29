import type { SupabaseClient } from "@supabase/supabase-js";
import type { Database } from "@/types/database.types";
import type { MembersPage, MembersQuery } from "@/features/members/types";

export async function listMembers(
  supabase: SupabaseClient<Database>,
  { search, page, pageSize }: MembersQuery,
): Promise<MembersPage> {
  const from = page * pageSize;
  const to = from + pageSize - 1;

  let query = supabase
    .from("profiles")
    .select("id, full_name, phone, role, created_at", { count: "exact" })
    .eq("role", "member")
    .order("created_at", { ascending: false })
    .range(from, to);

  if (search.trim()) {
    query = query.ilike("full_name", `%${search.trim()}%`);
  }

  const { data, error, count } = await query;
  if (error) throw new Error(error.message);

  return { members: data ?? [], totalCount: count ?? 0 };
}