import type { MembershipService } from "@/services/memberships/membership.service";
import { SupabaseMembershipService } from "@/services/memberships/supabase-membership.service";

let instance: MembershipService | null = null;

/** Single entry point for the memberships implementation. */
export function getMembershipService(): MembershipService {
  instance ??= new SupabaseMembershipService();
  return instance;
}

/** Test seam: overrides the singleton for the current module instance. */
export function setMembershipService(service: MembershipService | null): void {
  instance = service;
}

export type { MembershipService } from "@/services/memberships/membership.service";