import type { SupabaseClient } from "@supabase/supabase-js";
import type { Database } from "@/types/database.types";
import type { LoginInput } from "@/features/auth/validation";
import type { Profile } from "@/features/auth/types";

export async function signInWithPassword(
  supabase: SupabaseClient<Database>,
  input: LoginInput,
): Promise<void> {
  const { error } = await supabase.auth.signInWithPassword(input);
  if (error) throw new Error(error.message);
}

export async function signOut(supabase: SupabaseClient<Database>): Promise<void> {
  const { error } = await supabase.auth.signOut();
  if (error) throw new Error(error.message);
}

export async function getCurrentProfile(
  supabase: SupabaseClient<Database>,
): Promise<Profile | null> {
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return null;

  const { data, error } = await supabase.from("profiles").select("*").eq("id", user.id).single();
  if (error) throw new Error(error.message);
  return data;
}