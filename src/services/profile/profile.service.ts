import type {
  FacilityPlan,
  NotificationPrefs,
  PayoutMethod,
  PayoutMethodInput,
  ProfileStats,
  ProfileUpdate,
  SupportTicket,
  SupportTicketInput,
} from "@/features/profile/types";

/** The profile hub's data boundary: plan, payout details, support and personal settings. */
export interface ProfileService {
  /** GameAll's plan for this facility, or null when none has been set up yet. */
  getPlan(facilityId: string): Promise<FacilityPlan | null>;
  getStats(facilityId: string): Promise<ProfileStats>;

  updateProfile(update: ProfileUpdate): Promise<void>;
  uploadAvatar(file: File): Promise<string>;
  getNotificationPrefs(): Promise<NotificationPrefs>;
  saveNotificationPrefs(prefs: NotificationPrefs): Promise<void>;

  listPayoutMethods(facilityId: string): Promise<PayoutMethod[]>;
  addPayoutMethod(facilityId: string, input: PayoutMethodInput): Promise<PayoutMethod>;
  updatePayoutMethod(methodId: string, input: PayoutMethodInput): Promise<PayoutMethod>;
  setPrimaryPayoutMethod(methodId: string): Promise<void>;
  deletePayoutMethod(methodId: string): Promise<void>;

  listSupportTickets(facilityId: string): Promise<SupportTicket[]>;
  createSupportTicket(facilityId: string, input: SupportTicketInput): Promise<SupportTicket>;
}
