"use client";

import { useEffect, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { zodResolver } from "@hookform/resolvers/zod";
import { Controller, useForm } from "react-hook-form";
import { ArrowLeft, ArrowRight, BadgeCheck, ChevronRight, FileText, Loader2, MapPin, ShieldCheck, Sofa, UserRound } from "lucide-react";
import { toast } from "sonner";
import { FormMessage } from "@/features/auth/components/form-message";
import { useCurrentUser } from "@/features/auth/hooks/use-auth";
import { sanitizePhoneDigits } from "@/features/coaching/add-coach-validation";
import { FacilityPhotos } from "@/features/facility-profile/photos";
import {
  CONTACT_ROLE_OPTIONS,
  DEFAULT_POLICIES,
  OWNERSHIP_OPTIONS,
  POLICY_OPTIONS,
} from "@/features/facility-profile/types";
import { SetupAmenities } from "@/features/onboarding/components/setup-amenities";
import { CardHeading, CheckRow, Field, Segmented, SetupCard, SetupInput, SetupSelect, SetupTextarea } from "@/features/onboarding/components/setup-fields";
import { SetupPhotos } from "@/features/onboarding/components/setup-photos";
import { DEFAULT_FACILITY_TYPE, FACILITY_TYPE_OPTIONS, INDIAN_STATES } from "@/features/onboarding/constants";
import { useOnboardingStore } from "@/features/onboarding/state/onboarding-store";
import type { Facility, FacilityType } from "@/features/onboarding/types";
import { customAmenityProblem, facilityDetailsSchema, type FacilityDetailsInput } from "@/features/onboarding/validation";
import { getFacilityService } from "@/services/facility";
import { cn } from "@/lib/utils";

type Draft = Partial<FacilityDetailsInput>;

const STATE_OPTIONS = INDIAN_STATES.map((s) => ({ value: s, label: s }));
const ROLE_OPTIONS = CONTACT_ROLE_OPTIONS.map((r) => ({ value: r, label: r }));
const DESCRIPTION_MAX = 500;

/** Digits only, capped at 10 — a pasted "+91 98765-43210" or a stray letter never lands in a phone field. */
const phoneInput = {
  inputMode: "numeric" as const,
  maxLength: 10,
  type: "tel" as const,
  placeholder: "98765 43210",
};
function cleanPhone(e: { target: { value: string } }) {
  e.target.value = sanitizePhoneDigits(e.target.value.replace(/^\s*\+?91(?=\d{10}\s*$)/, ""));
}

function formDefaults(d: Draft, ownerName = ""): Partial<FacilityDetailsInput> {
  return {
    facilityName: d.facilityName ?? "",
    facilityType: d.facilityType ?? DEFAULT_FACILITY_TYPE,
    customFacilityType: d.customFacilityType ?? "",
    ownershipType: d.ownershipType ?? "OWNED",
    businessPhone: d.businessPhone ?? "",
    whatsappNumber: d.whatsappNumber ?? "",
    description: d.description ?? "",
    addressLine: d.addressLine ?? "",
    area: d.area ?? "",
    city: d.city ?? "",
    state: d.state ?? "",
    pinCode: d.pinCode ?? "",
    locationUrl: d.locationUrl ?? "",
    contactPersonName: d.contactPersonName ?? ownerName,
    contactPersonRole: d.contactPersonRole ?? "Facility Owner",
    contactAlternatePhone: d.contactAlternatePhone ?? "",
    policies: d.policies ?? DEFAULT_POLICIES,
    amenityKeys: d.amenityKeys ?? [],
    customAmenities: d.customAmenities ?? [],
  };
}

export function FacilityDetailsForm() {
  const router = useRouter();
  const { data: user } = useCurrentUser();
  const draft = useOnboardingStore((s) => s.draft);
  const setDraft = useOnboardingStore((s) => s.setDraft);
  const completeFacilityDetails = useOnboardingStore((s) => s.completeFacilityDetails);
  const [photos, setPhotos] = useState<File[]>([]);
  const [photosError, setPhotosError] = useState<string | undefined>();
  const [saveError, setSaveError] = useState<string | null>(null);
  // If a later step (the photos) fails after the facility was created, retrying must not create a second facility.
  const createdFacility = useRef<Facility | null>(null);

  const {
    register,
    handleSubmit,
    watch,
    setValue,
    getValues,
    control,
    reset,
    trigger,
    formState: { errors, isSubmitting },
  } = useForm<FacilityDetailsInput>({
    resolver: zodResolver(facilityDetailsSchema),
    mode: "onTouched",
    defaultValues: formDefaults(draft),
  });

  const facilityType = watch("facilityType");
  const description = watch("description") ?? "";
  const policies = watch("policies") ?? DEFAULT_POLICIES;
  const amenityKeys = watch("amenityKeys") ?? [];
  const customAmenities = watch("customAmenities") ?? [];
  const addressForMap = [watch("addressLine"), watch("area"), watch("city"), watch("pinCode")].filter(Boolean).join(", ");

  // Mirrors every field change into the store (debounced ~400ms) so a refresh never loses what was typed.
  // `watch` (not a closure over `values`) gives the live value; the last keystroke is never dropped.
  useEffect(() => {
    let timeout: ReturnType<typeof setTimeout>;
    const subscription = watch((value) => {
      clearTimeout(timeout);
      timeout = setTimeout(() => setDraft(value as Draft), 400);
    });
    return () => {
      clearTimeout(timeout);
      subscription.unsubscribe();
    };
  }, [watch, setDraft]);

  // The store uses skipHydration so the first client render matches the server's empty draft. Once hydrated,
  // pull the persisted draft into the form (defaultValues are only read once, before the store rehydrated).
  useEffect(() => {
    const unsub = useOnboardingStore.persist.onFinishHydration((state) => {
      reset(formDefaults(state.draft, user?.name ?? ""));
    });
    useOnboardingStore.persist.rehydrate();
    return unsub;
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // The contact number is the mobile the owner already verified by OTP at signup: use it, locked, with a Verified badge.
  const verifiedMobile = user?.verifiedMobile;
  useEffect(() => {
    if (verifiedMobile) setValue("businessPhone", verifiedMobile, { shouldValidate: true });
  }, [verifiedMobile, setValue]);

  // Pre-fill the contact person with the account holder's name once we know it (never over something already typed).
  useEffect(() => {
    if (user?.name && !getValues("contactPersonName")) setValue("contactPersonName", user.name);
  }, [user?.name, getValues, setValue]);

  function saveDraft() {
    setDraft(getValues() as Draft);
    toast.success("Draft saved. You can pick up where you left off.");
  }

  const onInvalid = () => {
    if (photos.length === 0) setPhotosError("Add at least one photo of your facility.");
    setSaveError("Please fix the highlighted fields to continue.");
  };

  const onSubmit = async (input: FacilityDetailsInput) => {
    if (!user) {
      setSaveError("We couldn't save your facility details. Please try again.");
      return;
    }
    if (photos.length === 0) {
      setPhotosError("Add at least one photo of your facility.");
      setSaveError("Please fix the highlighted fields to continue.");
      return;
    }
    setPhotosError(undefined);
    setSaveError(null);

    try {
      const service = getFacilityService();
      let facility = createdFacility.current;
      if (!facility) {
        facility = await service.createFacility({
          ownerId: user.id,
          name: input.facilityName.trim(),
          // Safe: zod validated facilityType against the same literal values as FacilityType.
          type: input.facilityType as FacilityType,
          customType: input.facilityType === "OTHER" ? input.customFacilityType : undefined,
          businessEmail: user.email,
          businessPhone: input.businessPhone.trim(),
          description: input.description.trim() || undefined,
          address: {
            line1: input.addressLine.trim(),
            area: input.area.trim(),
            city: input.city.trim(),
            state: input.state,
            country: "India",
            pinCode: input.pinCode,
          },
        });
        createdFacility.current = facility;
      }

      // Everything the create call doesn't take, then the photos (they go to GameAll's admin for checking).
      const photoService = new FacilityPhotos();
      await service.updateFacility(facility.id, {
        locationUrl: input.locationUrl.trim(),
        ownershipType: input.ownershipType,
        whatsappNumber: input.whatsappNumber,
        contactPerson: { name: input.contactPersonName, role: input.contactPersonRole, alternatePhone: input.contactAlternatePhone },
        policies: input.policies,
        amenityKeys: input.amenityKeys,
        customAmenities: input.customAmenities,
      });
      await photoService.addAll(facility.id, user.id, photos);
      // Done: if the owner comes back to this screen they start from the facility that now exists.
      setPhotos([]);

      await service.updateOnboardingStep(facility.id, "SPORTS");
      completeFacilityDetails(facility);
      router.push("/onboarding/sports");
    } catch (e) {
      setSaveError(e instanceof Error && e.message ? e.message : "We couldn't save your facility details. Please try again.");
    }
  };

  return (
    <form onSubmit={handleSubmit(onSubmit, onInvalid)} className="space-y-5" noValidate>
      {saveError && <FormMessage>{saveError}</FormMessage>}

      {/* ── Facility information + photos ─────────────────────────────── */}
      <SetupCard className="grid gap-6 lg:grid-cols-[1fr_320px] lg:gap-0 lg:p-0">
        <div className="space-y-4 lg:p-6">
          <div className="grid gap-4 sm:grid-cols-2 2xl:grid-cols-[1.1fr_1.1fr_1fr]">
            <Field id="facility-name" label="Facility Name" required error={errors.facilityName?.message}>
              <SetupInput id="facility-name" placeholder="e.g. Champz Turf" maxLength={100} invalid={!!errors.facilityName} {...register("facilityName")} />
            </Field>
            <Field id="facility-type" label="Facility Type" required error={errors.facilityType?.message as string | undefined}>
              <Controller
                control={control}
                name="facilityType"
                render={({ field }) => (
                  <SetupSelect id="facility-type" value={field.value} onChange={(v) => field.onChange(v)} onBlur={field.onBlur} options={FACILITY_TYPE_OPTIONS} invalid={!!errors.facilityType} />
                )}
              />
            </Field>
            <div>
              <span className="mb-1.5 block text-sm font-semibold">
                Ownership Type
                <span className="ml-0.5 text-[#C62828]" aria-hidden="true">
                  *
                </span>
              </span>
              <Controller
                control={control}
                name="ownershipType"
                render={({ field }) => <Segmented label="Ownership type" value={field.value} onChange={field.onChange} options={OWNERSHIP_OPTIONS} invalid={!!errors.ownershipType} />}
              />
            </div>
          </div>

          {facilityType === "OTHER" && (
            <Field id="custom-facility-type" label="Specify Facility Type" required error={errors.customFacilityType?.message}>
              <SetupInput id="custom-facility-type" placeholder="e.g. Basketball Court" maxLength={50} invalid={!!errors.customFacilityType} {...register("customFacilityType")} />
            </Field>
          )}

          <Field id="address-line" label="Address" required error={errors.addressLine?.message}>
            <SetupInput id="address-line" placeholder="Building / street, e.g. 12, Iyyapanthangal Main Road" maxLength={250} invalid={!!errors.addressLine} {...register("addressLine")} />
          </Field>

          <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
            <Field id="area" label="Area / Locality" required error={errors.area?.message}>
              <SetupInput id="area" placeholder="e.g. Iyyapanthangal" maxLength={100} invalid={!!errors.area} {...register("area")} />
            </Field>
            <Field id="city" label="City" required error={errors.city?.message}>
              <SetupInput id="city" placeholder="e.g. Chennai" invalid={!!errors.city} {...register("city")} />
            </Field>
            <Field id="state" label="State" required error={errors.state?.message as string | undefined}>
              <Controller
                control={control}
                name="state"
                render={({ field }) => <SetupSelect id="state" value={field.value} onChange={field.onChange} onBlur={field.onBlur} options={STATE_OPTIONS} placeholder="Select state" invalid={!!errors.state} />}
              />
            </Field>
            <Field id="pin-code" label="PIN Code" required error={errors.pinCode?.message}>
              <SetupInput
                id="pin-code"
                inputMode="numeric"
                placeholder="600056"
                maxLength={6}
                invalid={!!errors.pinCode}
                {...register("pinCode", { onChange: (e) => (e.target.value = e.target.value.replace(/\D/g, "").slice(0, 6)) })}
              />
            </Field>
          </div>

          <Field
            id="location-url"
            label="Set Location on Map"
            required
            error={errors.locationUrl?.message}
            hint="Open your facility in Google Maps, tap Share, copy the link and paste it here. GameAll checks it points at the right place."
          >
            <div className="flex flex-col gap-2 sm:flex-row">
              <div className="flex-1">
                <SetupInput
                  id="location-url"
                  inputMode="url"
                  placeholder="https://maps.app.goo.gl/..."
                  leading={<MapPin className="h-4 w-4 text-[#4817C2]" aria-hidden="true" />}
                  invalid={!!errors.locationUrl}
                  {...register("locationUrl")}
                />
              </div>
              <a
                href={`https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(addressForMap || "sports facility")}`}
                target="_blank"
                rel="noreferrer"
                className="flex h-11 shrink-0 items-center justify-center gap-1 rounded-lg border border-[#E5E1EF] bg-[#F7F5FB] px-4 text-sm font-semibold hover:bg-[#F1EBFF]"
              >
                Open Google Maps
                <ChevronRight className="h-4 w-4" aria-hidden="true" />
              </a>
            </div>
          </Field>

          <div className="grid items-start gap-4 sm:grid-cols-2 2xl:grid-cols-3">
            {verifiedMobile ? (
              <div>
                <span className="mb-1.5 flex items-center gap-2 text-sm font-semibold leading-5">
                  <span>
                    Contact Number
                    <span className="ml-0.5 text-[#C62828]" aria-hidden="true">
                      *
                    </span>
                  </span>
                  <span className="flex items-center gap-1 text-xs font-semibold text-[#2E7D32]">
                    <BadgeCheck className="h-3.5 w-3.5" aria-hidden="true" />
                    Verified
                  </span>
                </span>
                <div aria-label="Verified contact number" className="flex h-11 items-center gap-2 rounded-lg border border-[#E5E1EF] bg-[#F7F5FB] px-3 text-[15px]">
                  <span className="text-[#666666]">+91</span>
                  <span>{verifiedMobile}</span>
                </div>
                <p className="mt-1.5 text-xs font-normal text-[#666666]">The mobile number you verified when you signed up. Shown to players.</p>
              </div>
            ) : (
              <Field id="business-phone" label="Contact Number" required error={errors.businessPhone?.message} hint="Shown to players. It doesn't have to match your personal number.">
                <SetupInput id="business-phone" invalid={!!errors.businessPhone} {...phoneInput} {...register("businessPhone", { onChange: cleanPhone })} />
              </Field>
            )}
            <Field id="whatsapp-number" label="WhatsApp Number" optional error={errors.whatsappNumber?.message}>
              <SetupInput id="whatsapp-number" invalid={!!errors.whatsappNumber} {...phoneInput} {...register("whatsappNumber", { onChange: cleanPhone })} />
            </Field>
            <div>
              <span className="mb-1.5 flex items-center gap-2 text-sm font-semibold leading-5">
                <span>
                  Email Address
                  <span className="ml-0.5 text-[#C62828]" aria-hidden="true">
                    *
                  </span>
                </span>
                <span className="flex items-center gap-1 text-xs font-semibold text-[#2E7D32]">
                  <BadgeCheck className="h-3.5 w-3.5" aria-hidden="true" />
                  Verified
                </span>
              </span>
              <div aria-label="Email address" className="flex h-11 items-center rounded-lg border border-[#E5E1EF] bg-[#F7F5FB] px-3 text-[15px]">
                <span className="truncate">{user?.email ?? ""}</span>
              </div>
            </div>
          </div>

          <div>
            <Field id="description" label="Facility Description" optional error={errors.description?.message}>
              <SetupTextarea id="description" maxLength={DESCRIPTION_MAX} placeholder="Tell us about your facility (e.g., key features, location highlights, etc.)" invalid={!!errors.description} {...register("description")} />
              <p className={cn("mt-1 text-right text-xs", description.length >= DESCRIPTION_MAX ? "font-semibold text-[#C62828]" : "text-[#666666]")}>
                {description.length} / {DESCRIPTION_MAX}
              </p>
            </Field>
          </div>
        </div>

        <div className="border-t border-[#E5E1EF] lg:border-l lg:border-t-0 lg:p-6">
          <SetupPhotos files={photos} onChange={(f) => { setPhotos(f); if (f.length > 0) setPhotosError(undefined); }} error={photosError} />
        </div>
      </SetupCard>

      {/* ── Contact person + policies ──────────────────────────────────── */}
      <div className="grid gap-5 lg:grid-cols-2">
        <SetupCard>
          <CardHeading icon={<UserRound className="h-7 w-7" aria-hidden="true" />} title="Facility Contact Person" description="Primary person to reach for bookings and operations." />
          <div className="grid items-start gap-4 sm:grid-cols-2">
            <Field id="contact-name" label="Person Name" required error={errors.contactPersonName?.message}>
              <SetupInput id="contact-name" maxLength={80} placeholder="Full name" invalid={!!errors.contactPersonName} {...register("contactPersonName")} />
            </Field>
            <Field id="contact-role" label="Role / Designation" required error={errors.contactPersonRole?.message as string | undefined}>
              <Controller
                control={control}
                name="contactPersonRole"
                render={({ field }) => <SetupSelect id="contact-role" value={field.value} onChange={field.onChange} onBlur={field.onBlur} options={ROLE_OPTIONS} invalid={!!errors.contactPersonRole} />}
              />
            </Field>
            <Field id="contact-alt" label="Alternate Number" optional error={errors.contactAlternatePhone?.message}>
              <SetupInput id="contact-alt" invalid={!!errors.contactAlternatePhone} {...phoneInput} {...register("contactAlternatePhone", { onChange: cleanPhone })} />
            </Field>
          </div>
        </SetupCard>

        <SetupCard>
          <CardHeading icon={<ShieldCheck className="h-7 w-7" aria-hidden="true" />} title="Facility Policies" description="Set basic rules for players (shown on your facility page)." />
          <div className="flex flex-col gap-3.5">
            {POLICY_OPTIONS.map((p) => (
              <CheckRow key={p.key} id={`policy-${p.key}`} label={p.label} hint={p.hint} checked={policies[p.key]} onChange={(next) => setValue("policies", { ...policies, [p.key]: next }, { shouldDirty: true })} />
            ))}
          </div>
        </SetupCard>
      </div>

      {/* ── Amenities ──────────────────────────────────────────────────── */}
      <SetupCard>
        <CardHeading icon={<Sofa className="h-7 w-7" aria-hidden="true" />} title="Amenities & Facilities" />
        <SetupAmenities
          keys={amenityKeys}
          onKeysChange={(next) => setValue("amenityKeys", next as FacilityDetailsInput["amenityKeys"], { shouldDirty: true })}
          custom={customAmenities}
          onCustomChange={(next) => {
            setValue("customAmenities", next, { shouldDirty: true });
            void trigger("customAmenities");
          }}
          validateCustom={customAmenityProblem}
          error={errors.customAmenities?.message ?? (Array.isArray(errors.customAmenities) ? errors.customAmenities.find?.((e) => e?.message)?.message : undefined)}
        />
      </SetupCard>

      {/* ── Actions ────────────────────────────────────────────────────── */}
      <div className="flex flex-wrap items-center justify-between gap-3 border-t border-[#E5E1EF] pt-5">
        <button
          type="button"
          onClick={saveDraft}
          className="flex h-12 items-center gap-2 rounded-lg border border-[#E5E1EF] bg-white px-5 text-sm font-semibold hover:bg-[#FBFAFE] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#4817C2]"
        >
          <FileText className="h-4 w-4" aria-hidden="true" />
          Save as Draft
        </button>
        <div className="flex items-center gap-3">
          <button
            type="button"
            onClick={() => router.push("/onboarding/welcome")}
            className="flex h-12 items-center gap-2 rounded-lg border border-[#E5E1EF] bg-white px-6 text-sm font-semibold hover:bg-[#FBFAFE] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#4817C2]"
          >
            <ArrowLeft className="h-4 w-4" aria-hidden="true" />
            Back
          </button>
          <button
            type="submit"
            disabled={isSubmitting}
            className="flex h-12 min-w-[130px] items-center justify-center gap-2 rounded-lg bg-[#4817C2] px-7 text-sm font-semibold text-white transition-colors hover:bg-[#39109F] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#4817C2] focus-visible:ring-offset-2 disabled:opacity-70"
          >
            {isSubmitting ? (
              <>
                <Loader2 className="h-4 w-4 animate-spin" aria-hidden="true" />
                Saving…
              </>
            ) : (
              <>
                Next
                <ArrowRight className="h-4 w-4" aria-hidden="true" />
              </>
            )}
          </button>
        </div>
      </div>
    </form>
  );
}
