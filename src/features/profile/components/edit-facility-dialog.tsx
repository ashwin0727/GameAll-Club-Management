"use client";

import { useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { useQueryClient } from "@tanstack/react-query";
import { zodResolver } from "@hookform/resolvers/zod";
import { useForm, type Resolver } from "react-hook-form";
import { z } from "zod";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { useCurrentUser } from "@/features/auth/hooks/use-auth";
import { AmenitiesSection } from "@/features/facility-profile/components/amenities-section";
import { FacilityPhotosField } from "@/features/facility-profile/components/facility-photos-field";
import { VenueTypeField } from "@/features/facility-profile/components/venue-type-field";
import { isGoogleMapsLink } from "@/features/facility-profile/maps-link";
import { FacilityPhotos } from "@/features/facility-profile/photos";
import { NO_AMENITIES, type FacilityImage } from "@/features/facility-profile/types";
import { FacilityLocationSection } from "@/features/onboarding/components/facility-location-section";
import { FACILITY_TYPE_OPTIONS } from "@/features/onboarding/constants";
import type { Facility } from "@/features/onboarding/types";
import { facilityDetailsSchema, type FacilityDetailsInput } from "@/features/onboarding/validation";
import { getFacilityService } from "@/services/facility";

/**
 * What the dialog checks. A facility set up before the map link, venue type and photos existed ("older") may keep them empty; once
 * they have been given they stay required, and every new facility must give all three.
 */
function editSchema(older: boolean) {
  const link = older
    ? z.string().trim().refine((v) => v === "" || isGoogleMapsLink(v), "Paste a Google Maps link, e.g. https://maps.app.goo.gl/...")
    : z.string().trim().min(1, "Google Maps location link is required").refine(isGoogleMapsLink, "Paste a Google Maps link, e.g. https://maps.app.goo.gl/...");
  const venueType = older ? z.enum(["INDOOR", "OUTDOOR"]).optional() : z.enum(["INDOOR", "OUTDOOR"], { message: "Choose indoor or outdoor" });
  return facilityDetailsSchema.innerType().extend({ locationUrl: link, venueType }).refine((v) => v.facilityType !== "OTHER" || v.customFacilityType.trim().length > 0, {
    path: ["customFacilityType"],
    message: "Specify your facility type",
  });
}

/** Edit the facility's own details in place — address, map link, venue type, amenities and photos; the name and contact stay as set up. */
export function EditFacilityDialog({ facility, onClose }: { facility: Facility; onClose: () => void }) {
  const router = useRouter();
  const qc = useQueryClient();
  const { data: user } = useCurrentUser();
  const [saveError, setSaveError] = useState<string | null>(null);
  const photoService = useMemo(() => new FacilityPhotos(), []);
  const [saved, setSaved] = useState<FacilityImage[]>([]);
  const [newPhotos, setNewPhotos] = useState<File[]>([]);
  const [photoError, setPhotoError] = useState<string | undefined>();
  const [removing, setRemoving] = useState(false);
  // set up before the map link / venue type / photos were asked for
  const older = !facility.locationUrl && !facility.venueType;

  useEffect(() => {
    let live = true;
    photoService.list(facility.id).then((rows) => live && setSaved(rows), () => undefined);
    return () => {
      live = false;
    };
  }, [photoService, facility.id]);

  const schema = useMemo(() => editSchema(older), [older]);
  const {
    register,
    handleSubmit,
    watch,
    setValue,
    formState: { errors, isSubmitting },
  } = useForm<FacilityDetailsInput>({
    resolver: zodResolver(schema) as unknown as Resolver<FacilityDetailsInput>,
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
      locationUrl: facility.locationUrl ?? "",
      venueType: facility.venueType,
      amenities: facility.amenities ?? NO_AMENITIES,
    },
  });

  const state = watch("state");
  const venueType = watch("venueType");
  const amenities = watch("amenities") ?? NO_AMENITIES;
  const locationUrl = watch("locationUrl");
  const linkChanged = locationUrl.trim() !== (facility.locationUrl ?? "");

  async function removeSaved(image: FacilityImage) {
    if (!older && saved.length + newPhotos.length <= 1) {
      setPhotoError("Keep at least one photo of your facility.");
      return;
    }
    setPhotoError(undefined);
    setRemoving(true);
    try {
      await photoService.remove(image.id);
      setSaved((rows) => rows.filter((r) => r.id !== image.id));
    } catch (e) {
      setPhotoError(e instanceof Error ? e.message : "We couldn't remove that photo.");
    } finally {
      setRemoving(false);
    }
  }

  async function onSubmit(input: FacilityDetailsInput) {
    setSaveError(null);
    if (!older && saved.length + newPhotos.length === 0) {
      setPhotoError("Add at least one photo of your facility.");
      return;
    }
    try {
      // Only the address, map link, venue type and amenities can be changed here; the name, type and contact number stay as set up.
      await getFacilityService().updateFacility(facility.id, {
        address: {
          line1: input.addressLine.trim(),
          area: input.area.trim(),
          city: input.city.trim(),
          state: input.state,
          country: "India",
          pinCode: input.pinCode,
        },
        locationUrl: input.locationUrl.trim(),
        ...(input.venueType ? { venueType: input.venueType } : {}),
        amenities: input.amenities,
      });
      if (newPhotos.length > 0 && user) await photoService.addAll(facility.id, user.id, newPhotos);
      // The facility's name and address show on many pages; refresh everything that read them.
      await qc.invalidateQueries();
      router.refresh();
      onClose();
    } catch (e) {
      setSaveError(e instanceof Error && e.message ? e.message : "We couldn't save your facility details. Please try again.");
    }
  }

  return (
    <Dialog open onOpenChange={(open) => !open && !isSubmitting && onClose()}>
      <DialogContent className="max-h-[90vh] max-w-2xl overflow-y-auto">
        <form onSubmit={handleSubmit(onSubmit)} className="space-y-5" noValidate>
          <DialogHeader>
            <DialogTitle>Edit facility details</DialogTitle>
            <DialogDescription>
              You can update your address, map link, venue type, amenities and photos. The other details are fixed — contact GameAll support if they need to change.
            </DialogDescription>
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

          <VenueTypeField value={venueType} onChange={(v) => setValue("venueType", v, { shouldValidate: true, shouldDirty: true })} error={errors.venueType?.message} />

          <FacilityLocationSection
            register={register}
            errors={errors}
            state={state}
            linkRequired={!older}
            onStateChange={(value) => setValue("state", value, { shouldValidate: true, shouldDirty: true })}
          />
          {linkChanged && facility.locationUrl && <p className="-mt-3 text-xs text-muted-foreground">GameAll will check the new link again before it is marked verified.</p>}

          <div className="space-y-2">
            <Label>Amenities</Label>
            <AmenitiesSection value={amenities} onChange={(next) => setValue("amenities", next, { shouldDirty: true })} />
          </div>

          <FacilityPhotosField saved={saved} files={newPhotos} onFilesChange={setNewPhotos} onRemoveSaved={removeSaved} busy={removing} error={photoError} />

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
