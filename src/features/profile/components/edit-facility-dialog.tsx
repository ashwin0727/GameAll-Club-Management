"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { useQueryClient } from "@tanstack/react-query";
import { zodResolver } from "@hookform/resolvers/zod";
import { useForm } from "react-hook-form";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { useCurrentUser } from "@/features/auth/hooks/use-auth";
import { FacilityLocationSection } from "@/features/onboarding/components/facility-location-section";
import { FACILITY_TYPE_OPTIONS } from "@/features/onboarding/constants";
import type { Facility } from "@/features/onboarding/types";
import { facilityDetailsSchema, type FacilityDetailsInput } from "@/features/onboarding/validation";
import { getFacilityService } from "@/services/facility";

/** Edit the facility's own details in place — the same fields and rules as setup, without leaving the page. */
export function EditFacilityDialog({ facility, onClose }: { facility: Facility; onClose: () => void }) {
  const router = useRouter();
  const qc = useQueryClient();
  const { data: user } = useCurrentUser();
  const [saveError, setSaveError] = useState<string | null>(null);

  const {
    register,
    handleSubmit,
    watch,
    setValue,
    formState: { errors, isSubmitting },
  } = useForm<FacilityDetailsInput>({
    resolver: zodResolver(facilityDetailsSchema),
    mode: "onTouched",
    defaultValues: {
      facilityName: facility.name,
      facilityType: facility.type,
      customFacilityType: facility.customType ?? "",
      businessPhone: facility.businessPhone.replace(/^\+?91(?=\d{10}$)/, ""),
      addressLine: facility.address.line1,
      area: facility.address.area,
      city: facility.address.city,
      state: facility.address.state,
      pinCode: facility.address.pinCode,
      description: facility.description ?? "",
    },
  });

  const state = watch("state");
  const description = watch("description") ?? "";

  async function onSubmit(input: FacilityDetailsInput) {
    setSaveError(null);
    try {
      // Only the address and description can be changed here; the name, type and contact number stay as set up.
      await getFacilityService().updateFacility(facility.id, {
        address: {
          line1: input.addressLine.trim(),
          area: input.area.trim(),
          city: input.city.trim(),
          state: input.state,
          country: "India",
          pinCode: input.pinCode,
        },
        description: input.description?.trim() || undefined,
      });
      // The facility's name and address show on many pages; refresh everything that read them.
      await qc.invalidateQueries();
      router.refresh();
      onClose();
    } catch {
      setSaveError("We couldn't save your facility details. Please try again.");
    }
  }

  return (
    <Dialog open onOpenChange={(open) => !open && !isSubmitting && onClose()}>
      <DialogContent className="max-h-[90vh] max-w-2xl overflow-y-auto">
        <form onSubmit={handleSubmit(onSubmit)} className="space-y-5" noValidate>
          <DialogHeader>
            <DialogTitle>Edit facility details</DialogTitle>
            <DialogDescription>You can update your address and description. The other details are fixed — contact GameAll support if they need to change.</DialogDescription>
          </DialogHeader>

          <div className="grid gap-4 sm:grid-cols-2" aria-label="Details that can't be changed">
            {[
              ["Facility name", facility.name],
              ["Facility type", facility.type === "OTHER" ? (facility.customType ?? "Other") : (FACILITY_TYPE_OPTIONS.find((o) => o.value === facility.type)?.label ?? facility.type)],
              ["Business contact number", facility.businessPhone.replace(/^\+?91(?=\d{10}$)/, "")],
              ["Business email", user?.email ?? facility.businessEmail],
            ].map(([label, value]) => (
              <div key={label} className="space-y-1.5">
                <Label>{label}</Label>
                <Input value={value} disabled readOnly className="bg-muted/60" />
              </div>
            ))}
          </div>

          <FacilityLocationSection
            register={register}
            errors={errors}
            state={state}
            onStateChange={(value) => setValue("state", value, { shouldValidate: true, shouldDirty: true })}
          />

          <div className="space-y-2">
            <Label htmlFor="facility-description">About your facility</Label>
            <Textarea
              id="facility-description"
              rows={3}
              maxLength={500}
              value={description}
              onChange={(e) => setValue("description", e.target.value, { shouldDirty: true })}
              placeholder="A line or two about what you offer."
            />
            <p className="text-right text-xs text-muted-foreground">{description.length}/500</p>
            {errors.description?.message && <p className="text-xs text-destructive">{errors.description.message}</p>}
          </div>

          {saveError && (
            <p role="alert" className="text-sm text-destructive">
              {saveError}
            </p>
          )}

          <DialogFooter>
            <Button type="button" variant="outline" onClick={onClose} disabled={isSubmitting}>
              Cancel
            </Button>
            <Button type="submit" disabled={isSubmitting}>
              {isSubmitting ? "Saving…" : "Save changes"}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
