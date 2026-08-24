/**
 * A Member is a facility CUSTOMER/PLAYER record — never a GameAll
 * authenticated user. It has no login, no password, and no Supabase Auth
 * account by default. `userId` exists only for a future, explicit "Invite
 * to GameAll" flow that links a member to a real login; normal member
 * creation always leaves it null.
 */
export interface Member {
  id: string;
  facilityId: string;
  fullName: string;
  phone: string;
  email: string | null;
  dateOfBirth: string | null;
  gender: string | null;
  notes: string | null;
  status: "ACTIVE" | "INACTIVE";
  userId: string | null;
  createdAt: string;
  updatedAt: string;
}

export interface MemberInput {
  facilityId: string;
  fullName: string;
  phone: string;
  email?: string | null;
  dateOfBirth?: string | null;
  gender?: string | null;
  notes?: string | null;
}