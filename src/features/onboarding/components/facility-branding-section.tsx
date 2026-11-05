"use client";

import { FileUpload } from "@/components/shared/file-upload";
import { FacilityPhotosField } from "@/features/facility-profile/components/facility-photos-field";

export interface FacilityBrandingSectionProps {
  logo: File | string | null;
  onLogoChange: (file: File | null) => void;
  /** New photos picked on this screen (at least one is required to continue). */
  photos: File[];
  onPhotosChange: (files: File[]) => void;
  photosError?: string;
}

/** Logo (optional) and facility photos (at least one, checked by GameAll before players see them). */
export function FacilityBrandingSection({ logo, onLogoChange, photos, onPhotosChange, photosError }: FacilityBrandingSectionProps) {
  return (
    <div className="space-y-6">
      <FileUpload label="Facility Logo" hint="Optional. You can add your logo later." value={logo} onChange={onLogoChange} />
      <FacilityPhotosField files={photos} onFilesChange={onPhotosChange} error={photosError} />
    </div>
  );
}
