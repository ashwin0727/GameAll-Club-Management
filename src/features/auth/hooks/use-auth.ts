"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import { getCurrentProfile, signInWithPassword, signOut } from "@/features/auth/api/auth.api";
import type { LoginInput } from "@/features/auth/validation";

const CURRENT_PROFILE_KEY = ["auth", "current-profile"] as const;

export function useCurrentProfile() {
  const supabase = createClient();
  return useQuery({
    queryKey: CURRENT_PROFILE_KEY,
    queryFn: () => getCurrentProfile(supabase),
  });
}

export function useLogin() {
  const supabase = createClient();
  const router = useRouter();
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (input: LoginInput) => signInWithPassword(supabase, input),
    onSuccess: async () => {
      await queryClient.invalidateQueries({ queryKey: CURRENT_PROFILE_KEY });
      router.push("/dashboard");
      router.refresh();
    },
  });
}

export function useLogout() {
  const supabase = createClient();
  const router = useRouter();
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: () => signOut(supabase),
    onSuccess: async () => {
      queryClient.clear();
      router.push("/login");
      router.refresh();
    },
  });
}