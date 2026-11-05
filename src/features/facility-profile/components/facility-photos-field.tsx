"use client";

import * as React from "react";
import { ImagePlus, X } from "lucide-react";
import { Label } from "@/components/ui/label";
import { MAX_FACILITY_PHOTOS, type FacilityImage, type VerificationStatus } from "@/features/facility-profile/types";
import { photoProblem } from "@/features/facility-profile/photos";
import { cn } from "@/lib/utils";

const STATUS_STYLE: Record<VerificationStatus, { label: string; className: string }> = {
  PENDING: { label: "Waiting for review", className: "bg-warning/15 text-warning" },
  VERIFIED: { label: "Verified", className: "bg-success/15 text-success" },
  REJECTED: { label: "Rejected", className: "bg-destructive/10 text-destructive" },
};

/**
 * Facility photos: at least one is required. [saved] are photos already stored (with the admin's verdict); [files] are new ones
 * picked but not uploaded yet. The first photo is the cover players see once it is verified.
 */
export function FacilityPhotosField({
  saved = [],
  files,
  onFilesChange,
  onRemoveSaved,
  busy = false,
  error,
}: {
  saved?: FacilityImage[];
  files: File[];
  onFilesChange: (files: File[]) => void;
  onRemoveSaved?: (image: FacilityImage) => void;
  busy?: boolean;
  error?: string;
}) {
  const inputRef = React.useRef<HTMLInputElement>(null);
  const [problem, setProblem] = React.useState<string | null>(null);
  const previews = React.useMemo(() => files.map((f) => URL.createObjectURL(f)), [files]);
  React.useEffect(() => () => previews.forEach((u) => URL.revokeObjectURL(u)), [previews]);
  const total = saved.length + files.length;

  function add(list: FileList | null) {
    if (!list) return;
    const next = [...files];
    setProblem(null);
    for (const file of Array.from(list)) {
      if (saved.length + next.length >= MAX_FACILITY_PHOTOS) {
        setProblem(`You can add up to ${MAX_FACILITY_PHOTOS} photos.`);
        break;
      }
      const why = photoProblem(file);
      if (why) {
        setProblem(why);
        continue;
      }
      next.push(file);
    }
    onFilesChange(next);
    if (inputRef.current) inputRef.current.value = "";
  }

  return (
    <div className="space-y-2">
      <Label htmlFor="facility-photos">Facility Photos</Label>
      <p className="text-xs text-muted-foreground">
        Add at least one clear photo of your facility (up to {MAX_FACILITY_PHOTOS}). GameAll checks each photo before players see it; the first one is the cover.
      </p>
      <input id="facility-photos" ref={inputRef} type="file" accept="image/jpeg,image/png,image/webp" multiple className="sr-only" onChange={(e) => add(e.target.files)} />

      <ul className="grid grid-cols-2 gap-3 sm:grid-cols-4">
        {saved.map((img, i) => (
          <li key={img.id} className="space-y-1.5">
            <div className="relative overflow-hidden rounded-lg border border-border">
              {/* eslint-disable-next-line @next/next/no-img-element -- remote photo of unknown size */}
              <img src={img.url} alt={`Facility photo ${i + 1}`} className="aspect-[4/3] w-full object-cover" />
              {onRemoveSaved && (
                <button
                  type="button"
                  aria-label={`Remove photo ${i + 1}`}
                  disabled={busy}
                  onClick={() => onRemoveSaved(img)}
                  className="absolute right-1.5 top-1.5 rounded-full bg-black/60 p-1 text-white hover:bg-black/80 disabled:opacity-50"
                >
                  <X className="h-3.5 w-3.5" aria-hidden />
                </button>
              )}
              {i === 0 && <span className="absolute bottom-1.5 left-1.5 rounded-full bg-black/60 px-2 py-0.5 text-[10px] font-semibold text-white">Cover</span>}
            </div>
            <span className={cn("inline-block rounded-full px-2 py-0.5 text-[11px] font-semibold", STATUS_STYLE[img.status].className)}>{STATUS_STYLE[img.status].label}</span>
            {img.status === "REJECTED" && img.note && <p className="text-xs text-destructive">{img.note}</p>}
          </li>
        ))}
        {files.map((file, i) => (
          <li key={`${file.name}-${i}`} className="space-y-1.5">
            <div className="relative overflow-hidden rounded-lg border border-border">
              {/* eslint-disable-next-line @next/next/no-img-element -- local preview */}
              <img src={previews[i]} alt={`New photo ${i + 1}`} className="aspect-[4/3] w-full object-cover" />
              <button
                type="button"
                aria-label={`Remove new photo ${i + 1}`}
                onClick={() => onFilesChange(files.filter((_, j) => j !== i))}
                className="absolute right-1.5 top-1.5 rounded-full bg-black/60 p-1 text-white hover:bg-black/80"
              >
                <X className="h-3.5 w-3.5" aria-hidden />
              </button>
              {saved.length === 0 && i === 0 && <span className="absolute bottom-1.5 left-1.5 rounded-full bg-black/60 px-2 py-0.5 text-[10px] font-semibold text-white">Cover</span>}
            </div>
            <span className="inline-block rounded-full bg-secondary px-2 py-0.5 text-[11px] font-semibold text-muted-foreground">Not uploaded yet</span>
          </li>
        ))}
        {total < MAX_FACILITY_PHOTOS && (
          <li>
            <button
              type="button"
              onClick={() => inputRef.current?.click()}
              className="flex aspect-[4/3] w-full flex-col items-center justify-center gap-1 rounded-lg border border-dashed border-input text-xs font-medium text-muted-foreground transition-colors hover:border-primary hover:text-primary"
            >
              <ImagePlus className="h-5 w-5" aria-hidden />
              Add photo
            </button>
          </li>
        )}
      </ul>

      {(problem || error) && (
        <p role="alert" className="text-xs text-destructive">
          {problem ?? error}
        </p>
      )}
    </div>
  );
}
