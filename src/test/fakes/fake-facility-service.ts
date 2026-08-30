import type { Facility, FacilityInput } from "@/features/onboarding/types";
import type { FacilityService } from "@/services/facility/facility.service";
import { setFacilityService } from "@/services/facility";

/**
 * In-memory stand-in for SupabaseFacilityService, for tests. Mirrors the
 * "current authenticated user" concept the real RLS-backed service relies
 * on via `setCurrentUserId` — call it after installFakeAuthService so
 * getFacility()/createFacility() know which user is "signed in".
 */
export class FakeFacilityService implements FacilityService {
  private facilities: Facility[] = [];
  private currentUserId: string | null = null;

  setCurrentUserId(id: string | null): void {
    this.currentUserId = id;
  }

  async createFacility(input: FacilityInput): Promise<Facility> {
    const now = new Date().toISOString();
    const facility: Facility = {
      ...input,
      id: crypto.randomUUID(),
      ownerId: this.currentUserId ?? input.ownerId,
      status: input.status ?? "ACTIVE",
      onboardingStep: "FACILITY_DETAILS",
      createdAt: now,
      updatedAt: now,
      membershipAccessDays: [0, 1, 2, 3, 4, 5, 6],
    };
    this.facilities.push(facility);
    return facility;
  }

  async getFacility(): Promise<Facility | null> {
    return this.facilities.find((f) => f.ownerId === this.currentUserId) ?? null;
  }

  async getFacilities(): Promise<Facility[]> {
    return this.facilities.filter((f) => f.ownerId === this.currentUserId);
  }

  async updateFacility(id: string, patch: Partial<FacilityInput>): Promise<Facility> {
    const index = this.facilities.findIndex((f) => f.id === id);
    const existing = this.facilities[index];
    if (index === -1 || !existing) throw new Error("Facility not found");
    const updated: Facility = { ...existing, ...patch, updatedAt: new Date().toISOString() } as Facility;
    this.facilities[index] = updated;
    return updated;
  }

  async updateOnboardingStep(facilityId: string, step: Facility["onboardingStep"]): Promise<void> {
    const index = this.facilities.findIndex((f) => f.id === facilityId);
    const existing = this.facilities[index];
    if (index === -1 || !existing) return;
    this.facilities[index] = { ...existing, onboardingStep: step };
  }
}

/** Test seam: builds a fake, injects it via setFacilityService, returns it for assertions/overrides. */
export function installFakeFacilityService(): FakeFacilityService {
  const service = new FakeFacilityService();
  setFacilityService(service);
  return service;
}