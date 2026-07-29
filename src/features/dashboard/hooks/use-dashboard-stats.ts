"use client";

import { useQuery } from "@tanstack/react-query";
import { createClient } from "@/lib/supabase/client";
import { getDashboardStats } from "@/features/dashboard/api/dashboard.api";

export function useDashboardStats() {
  const supabase = createClient();
  return useQuery({
    queryKey: ["dashboard", "stats"],
    queryFn: () => getDashboardStats(supabase),
  });
}