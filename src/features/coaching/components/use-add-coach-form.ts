"use client";

import { useEffect, useState } from "react";
import { ServiceError } from "@/services/shared/service-error";
import { getCoachingService } from "@/services/coaching";
import { getStaffService } from "@/services/staff";
import { isValidDateOfBirth, isValidEmail, isValidPhoneDigits, sanitizePhoneDigits } from "@/features/coaching/add-coach-validation";
import type { CoachCandidate, CoachStatus } from "@/features/coaching/types";
import type { RoleRow } from "@/features/staff/types";

export const DURATION_OPTIONS = [
  { value: "30", label: "30 minutes" },
  { value: "45", label: "45 minutes" },
  { value: "60", label: "1 hour" },
  { value: "90", label: "1.5 hours" },
  { value: "120", label: "2 hours" },
  { value: "custom", label: "Custom" },
];

export const AVATAR_MAX_BYTES = 2 * 1024 * 1024;
export const AVATAR_ACCEPT = ["image/jpeg", "image/png", "image/webp"];

interface NewPersonDraft {
  fullName: string;
  phone: string;
  email: string;
  dateOfBirth: string;
  roleId: string;
}

/**
 * All the Add Coach form's state and submit logic, independent of layout — the full-page route
 * (add-coach-page.tsx) and the slide-over (add-coach-sheet.tsx, the reference design's actual
 * entry point) both render the same fields via `AddCoachFormFields` and drive their own
 * page/sheet-shaped Cancel/Submit footer off this hook's `canSubmit`/`busy`/`submit`.
 */
export function useAddCoachForm(facilityId: string | null) {
  const [candidates, setCandidates] = useState<CoachCandidate[]>([]);
  const [roles, setRoles] = useState<RoleRow[]>([]);
  const [rolesError, setRolesError] = useState<string | null>(null);

  const [mode, setMode] = useState<"pick" | "new">("pick");
  const [userId, setUserId] = useState("");
  const [newPerson, setNewPerson] = useState<NewPersonDraft>({ fullName: "", phone: "", email: "", dateOfBirth: "", roleId: "" });
  const [avatarFile, setAvatarFile] = useState<File | null>(null);
  const [avatarPreview, setAvatarPreview] = useState<string | null>(null);
  const [avatarError, setAvatarError] = useState<string | null>(null);

  const [sportIds, setSportIds] = useState<string[]>([]);
  const [expertiseLevels, setExpertiseLevels] = useState<string[]>([]);
  const [experience, setExperience] = useState("");
  const [certifications, setCertifications] = useState("");

  const [status, setStatus] = useState<CoachStatus>("ACTIVE");
  const [duration, setDuration] = useState("60");
  const [customDuration, setCustomDuration] = useState("");
  const [bio, setBio] = useState("");

  const [creatingStaff, setCreatingStaff] = useState(false);
  const [uploadingPhoto, setUploadingPhoto] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    return () => {
      if (avatarPreview) URL.revokeObjectURL(avatarPreview);
    };
  }, [avatarPreview]);

  useEffect(() => {
    if (!facilityId) return;
    getCoachingService()
      .listCoachCandidates(facilityId)
      .then(setCandidates)
      .catch(() => setCandidates([]));
    setRolesError(null);
    getStaffService()
      .listRoles(facilityId)
      .then((rows) => {
        setRoles(rows);
        const coachRole = rows.find((r) => /coach/i.test(r.name));
        if (coachRole) setNewPerson((p) => (p.roleId ? p : { ...p, roleId: coachRole.id }));
      })
      .catch((e) => {
        setRoles([]);
        setRolesError(e instanceof ServiceError ? e.message : "Could not load roles for the new-person form.");
      });
  }, [facilityId]);

  function pickAvatar(file: File | undefined) {
    if (!file) return;
    setAvatarError(null);
    if (!AVATAR_ACCEPT.includes(file.type)) {
      setAvatarError("Please choose a JPG, PNG or WEBP image.");
      return;
    }
    if (file.size > AVATAR_MAX_BYTES) {
      setAvatarError("That photo is larger than 2MB.");
      return;
    }
    setAvatarFile(file);
    setAvatarPreview((prev) => {
      if (prev) URL.revokeObjectURL(prev);
      return URL.createObjectURL(file);
    });
  }

  function toggle(list: string[], setList: (v: string[]) => void, value: string) {
    setList(list.includes(value) ? list.filter((v) => v !== value) : [...list, value]);
  }

  /** Digits-only, capped at 10, as the phone field is typed into — invalid characters and a
   *  too-long paste never make it into state at all, rather than being flagged after the fact. */
  function setPhone(raw: string) {
    setNewPerson((p) => ({ ...p, phone: sanitizePhoneDigits(raw) }));
  }

  const selectedCandidate = candidates.find((c) => c.userId === userId) ?? null;
  const canSubmit =
    (mode === "pick"
      ? Boolean(userId)
      : Boolean(newPerson.fullName.trim() && newPerson.roleId) &&
        isValidEmail(newPerson.email) &&
        isValidPhoneDigits(newPerson.phone) &&
        isValidDateOfBirth(newPerson.dateOfBirth)) &&
    sportIds.length > 0 &&
    expertiseLevels.length > 0 &&
    (duration !== "custom" || Number(customDuration) > 0);

  async function submit(): Promise<{ coachId: string; name: string }> {
    if (!facilityId || !canSubmit) throw new Error("Form is incomplete");
    setBusy(true);
    setError(null);
    try {
      let coachUserId = userId;
      let displayName = selectedCandidate?.fullName ?? "";

      if (mode === "new") {
        let avatarUrl: string | null = null;
        if (avatarFile) {
          setUploadingPhoto(true);
          try {
            avatarUrl = await getStaffService().uploadAvatar(avatarFile);
          } finally {
            setUploadingPhoto(false);
          }
        }
        setCreatingStaff(true);
        try {
          const result = await getStaffService().createStaff({
            facilityId,
            fullName: newPerson.fullName.trim(),
            email: newPerson.email.trim(),
            phone: newPerson.phone.trim() || null,
            roleId: newPerson.roleId,
            avatarUrl,
          });
          coachUserId = result.userId;
          displayName = newPerson.fullName.trim();
        } finally {
          setCreatingStaff(false);
        }
      }

      const coachId = await getCoachingService().addCoach(facilityId, coachUserId, {
        experienceYears: experience.trim() ? Number(experience) : null,
        certifications: certifications.trim() || null,
        bio: bio.trim() || null,
        status,
        sportIds,
        expertiseLevels,
        defaultSessionDurationMinutes: duration === "custom" ? Number(customDuration) : Number(duration),
        dateOfBirth: mode === "new" && newPerson.dateOfBirth ? newPerson.dateOfBirth : null,
      });
      return { coachId, name: displayName };
    } catch (e) {
      setError(e instanceof ServiceError ? e.message : "Could not add the coach.");
      throw e;
    } finally {
      setBusy(false);
    }
  }

  return {
    candidates,
    roles,
    rolesError,
    mode,
    setMode,
    userId,
    setUserId,
    newPerson,
    setNewPerson,
    avatarPreview,
    avatarError,
    pickAvatar,
    sportIds,
    setSportIds,
    expertiseLevels,
    setExpertiseLevels,
    experience,
    setExperience,
    certifications,
    setCertifications,
    status,
    setStatus,
    duration,
    setDuration,
    customDuration,
    setCustomDuration,
    bio,
    setBio,
    toggle,
    setPhone,
    selectedCandidate,
    canSubmit,
    busy,
    creatingStaff,
    uploadingPhoto,
    error,
    submit,
  };
}

export type AddCoachFormState = ReturnType<typeof useAddCoachForm>;
