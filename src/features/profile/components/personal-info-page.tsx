"use client";

import { useState } from "react";
import { Skeleton } from "@/components/ui/skeleton";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { useCurrentUser } from "@/features/auth/hooks/use-auth";
import type { Profile } from "@/features/auth/types";
import { EditFacilityDialog } from "@/features/profile/components/edit-facility-dialog";
import { useFacility } from "@/features/facility/hooks/use-facility";
import { FACILITY_TYPE_OPTIONS } from "@/features/onboarding/constants";
import { formatPhone } from "@/features/profile/profile-validation";
import { ProfileAvatar } from "@/features/profile/components/profile-hero";
import { InfoRow, PageMessage, SectionCard, SubPageHeader } from "@/features/profile/components/profile-shared";

const ROLE_TITLE: Record<Profile["role"], string> = { admin: "Facility Owner", staff: "Facility Staff", member: "Member" };

function formatDate(iso: string): string {
  return new Date(iso).toLocaleDateString("en-IN", { day: "numeric", month: "short", year: "numeric" });
}

/** Personal Information: who you are, and the facility you run. */
export function PersonalInfoPage({ profile }: { profile: Profile }) {
  const { data: facility, isLoading, isError } = useFacility();
  const { data: user } = useCurrentUser();
  const [editingFacility, setEditingFacility] = useState(false);
  const isOwner = !!facility && facility.ownerId === user?.id;
  // Until a personal number is added, the facility's own contact number stands in for it.
  const mobile = profile.phone || facility?.businessPhone || null;

  return (
    <div className="space-y-4">
      <SubPageHeader
        title="Personal Information"
        description="Your account details and the facility they belong to."
      />

      <SectionCard>
        <div className="flex flex-col gap-5 sm:flex-row sm:items-start">
          <ProfileAvatar profile={profile} size="md" />
          <dl className="grid flex-1 gap-4 sm:grid-cols-2">
            <InfoRow label="Full name" value={profile.full_name} />
            <InfoRow label="Role" value={ROLE_TITLE[profile.role]} />
            <InfoRow label="Mobile number" value={formatPhone(mobile)} />
            <InfoRow label="Email address" value={profile.email} />
            <InfoRow label="Member since" value={formatDate(profile.created_at)} />
          </dl>
        </div>
      </SectionCard>

      <SectionCard
        title="Your Facility"
        description="What you entered when you set the facility up."
        action={
          isOwner && (
            <Button type="button" variant="ghost" size="sm" className="h-8 text-xs" onClick={() => setEditingFacility(true)}>
              Edit
            </Button>
          )
        }
      >
        {isLoading ? (
          <Skeleton className="h-40 w-full rounded-lg" />
        ) : isError ? (
          <PageMessage tone="error">Unable to load your facility. Please try again.</PageMessage>
        ) : !facility ? (
          <PageMessage>No facility is set up for this account yet.</PageMessage>
        ) : (
          <div className="space-y-5">
            <div className="flex items-center gap-3">
              {facility.logoUrl ? (
                // eslint-disable-next-line @next/next/no-img-element -- remote logo, rendered at a fixed small size
                <img src={facility.logoUrl} alt="" className="h-14 w-14 rounded-xl border border-border object-cover" />
              ) : (
                <span className="flex h-14 w-14 items-center justify-center rounded-xl bg-primary/10 text-lg font-semibold text-primary">
                  {facility.name.slice(0, 1).toUpperCase()}
                </span>
              )}
              <div className="min-w-0">
                <p className="truncate text-base font-semibold">{facility.name}</p>
                <Badge variant={facility.status === "ACTIVE" ? "success" : "secondary"} className={facility.status === "ACTIVE" ? "bg-success/15 text-success" : ""}>
                  {facility.status === "ACTIVE" ? "Active" : "Inactive"}
                </Badge>
              </div>
            </div>
            <dl className="grid gap-4 sm:grid-cols-2">
              <InfoRow
                label="Facility type"
                value={facility.type === "OTHER" ? (facility.customType ?? "Other") : (FACILITY_TYPE_OPTIONS.find((o) => o.value === facility.type)?.label ?? facility.type)}
              />
              <InfoRow label="Business email" value={facility.businessEmail} />
              <InfoRow label="Business phone" value={formatPhone(facility.businessPhone)} />
              <InfoRow label="City" value={facility.address.city} />
              <div className="sm:col-span-2">
                <InfoRow
                  label="Address"
                  value={[facility.address.line1, facility.address.area, facility.address.city, facility.address.state, facility.address.pinCode]
                    .filter(Boolean)
                    .join(", ")}
                />
              </div>
              {facility.description && (
                <div className="sm:col-span-2">
                  <InfoRow label="About" value={facility.description} />
                </div>
              )}
              <InfoRow label="Facility added" value={formatDate(facility.createdAt)} />
            </dl>
          </div>
        )}
      </SectionCard>
      {editingFacility && facility && <EditFacilityDialog facility={facility} onClose={() => setEditingFacility(false)} />}
    </div>
  );
}
