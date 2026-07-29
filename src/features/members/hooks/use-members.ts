"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { createClient } from "@/lib/supabase/client";
import { listMembers } from "@/features/members/api/members.api";
import type { MembersQuery } from "@/features/members/types";
import type { CreateMemberInput } from "@/features/members/validation";

const MEMBERS_KEY = "members" as const;

export function useMembers(query: MembersQuery) {
  const supabase = createClient();
  return useQuery({
    queryKey: [MEMBERS_KEY, query],
    queryFn: () => listMembers(supabase, query),
    placeholderData: (previous) => previous,
  });
}

async function createMember(input: CreateMemberInput): Promise<{ id: string }> {
  const res = await fetch("/api/members", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(input),
  });
  const body = await res.json();
  if (!res.ok) throw new Error(body.error ?? "Failed to create member");
  return body;
}

export function useCreateMember() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: createMember,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: [MEMBERS_KEY] });
    },
  });
}