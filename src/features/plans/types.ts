export type BillingInterval = "month" | "year";

export interface PlanOption {
  code: string;
  name: string;
  description: string | null;
  monthlyMinor: number;
  yearlyMinor: number;
  currency: string;
  /** null = unlimited. */
  maxCourts: number | null;
  maxStaff: number | null;
  featureFlags: string[];
  features: string[];
  isPopular: boolean;
  trialDays: number;
  pageKeys: string[];
}

/** What a club's plan grants right now (my_facility_plan). Null on the context means the club has no plan: unrestricted. */
export interface PlanSnapshot {
  planCode: string;
  /** The plan whose rules apply today — Basic once a chosen plan has lapsed. */
  effectiveCode: string;
  name: string;
  status: "active" | "trialing" | "cancelled";
  interval: BillingInterval;
  priceMinor: number;
  /** yyyy-mm-dd — the last covered day. */
  validTill: string;
  onTrial: boolean;
  lapsed: boolean;
  daysLeft: number;
  maxCourts: number | null;
  maxStaff: number | null;
  features: string[];
  pageKeys: string[];
}
