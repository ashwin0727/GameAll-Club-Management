import type { MembershipSessionService } from "@/services/membership-sessions/membership-session.service";
import { SupabaseMembershipSessionService } from "@/services/membership-sessions/supabase-membership-session.service";

let instance: MembershipSessionService | null = null;

/** Single entry point for the membership-sessions implementation. */
export function getMembershipSessionService(): MembershipSessionService {
  instance ??= new SupabaseMembershipSessionService();
  return instance;
}

/** Test seam: overrides the singleton for the current module instance. */
export function setMembershipSessionService(service: MembershipSessionService | null): void {
  instance = service;
}

export type { MembershipSessionService } from "@/services/membership-sessions/membership-session.service";