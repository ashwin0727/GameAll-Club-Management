"use client";

import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { FileUpload } from "@/components/shared/file-upload";

const DESCRIPTION_MAX = 500;

export interface FacilityBrandingSectionProps {
  description: string;
  onDescriptionChange: (value: string) => void;
  logo: File | string | null;
  onLogoChange: (file: File | null) => void;
}

export function FacilityBrandingSection({
  description,
  onDescriptionChange,
  logo,
  onLogoChange,
}: FacilityBrandingSectionProps) {
  return (
    <div className="space-y-5">
      <FileUpload
        label="Facility Logo"
        hint="Optional. You can add your logo later."
        value={logo}
        onChange={onLogoChange}
      />

      <div className="space-y-2">
        <Label htmlFor="facility-description">About Your Facility</Label>
        <Textarea
          id="facility-description"
          placeholder="Tell customers a little about your facility..."
          maxLength={DESCRIPTION_MAX}
          value={description}
          onChange={(e) => onDescriptionChange(e.target.value)}
          className="min-h-[6rem]"
        />
        <p className="text-right text-xs text-muted-foreground">
          {description.length} / {DESCRIPTION_MAX}
        </p>
      </div>
    </div>
  );
}
