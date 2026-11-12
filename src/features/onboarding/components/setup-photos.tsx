"use client";

import * as React from "react";
import { ImagePlus, X } from "lucide-react";
import { photoProblem } from "@/features/facility-profile/photos";
import { FieldError } from "@/features/onboarding/components/setup-fields";

export const MAX_SETUP_PHOTOS = 5;

/** "Facility Photos" panel: up to 5 photos (JPG/PNG/WebP, under 8 MB each), the first is the cover players see once GameAll verifies it. */
export function SetupPhotos({ files, onChange, error }: { files: File[]; onChange: (files: File[]) => void; error?: string }) {
  const inputRef = React.useRef<HTMLInputElement>(null);
  const [problem, setProblem] = React.useState<string | null>(null);
  const previews = React.useMemo(() => files.map((f) => URL.createObjectURL(f)), [files]);
  React.useEffect(() => () => previews.forEach((u) => URL.revokeObjectURL(u)), [previews]);

  function add(list: FileList | null) {
    if (!list) return;
    const next = [...files];
    let message: string | null = null;
    for (const file of Array.from(list)) {
      if (next.length >= MAX_SETUP_PHOTOS) {
        message = `You can add up to ${MAX_SETUP_PHOTOS} photos.`;
        break;
      }
      const why = photoProblem(file);
      if (why) {
        message = why;
        continue;
      }
      if (next.some((f) => f.name === file.name && f.size === file.size && f.lastModified === file.lastModified)) {
        message = "That photo is already added.";
        continue;
      }
      next.push(file);
    }
    setProblem(message);
    onChange(next);
    if (inputRef.current) inputRef.current.value = "";
  }

  return (
    <div>
      <h2 className="text-lg font-semibold leading-tight">
        Facility Photos
        <span className="ml-0.5 text-[#C62828]" aria-hidden="true">
          *
        </span>
      </h2>
      <p className="mt-0.5 text-sm font-normal text-[#666666]">Add clear photos of your facility (up to {MAX_SETUP_PHOTOS}). The first one is your cover.</p>
      <input
        ref={inputRef}
        id="facility-photos"
        type="file"
        accept="image/jpeg,image/png,image/webp"
        multiple
        className="sr-only"
        onChange={(e) => add(e.target.files)}
        aria-label="Upload facility photos"
      />

      <ul className="mt-4 grid grid-cols-2 gap-3">
        {files.map((file, i) => (
          <li key={`${file.name}-${i}`} className="relative aspect-[4/3] overflow-hidden rounded-lg border border-[#E5E1EF]">
            {/* eslint-disable-next-line @next/next/no-img-element -- local preview */}
            <img src={previews[i]} alt={`Facility photo ${i + 1}`} className="h-full w-full object-cover" />
            {i === 0 && <span className="absolute bottom-1.5 left-1.5 rounded-full bg-black/60 px-2 py-0.5 text-[10px] font-semibold text-white">Cover</span>}
            <button
              type="button"
              aria-label={`Remove photo ${i + 1}`}
              onClick={() => {
                setProblem(null);
                onChange(files.filter((_, j) => j !== i));
              }}
              className="absolute right-1.5 top-1.5 flex h-6 w-6 items-center justify-center rounded-full bg-white text-[#171717] shadow hover:bg-[#F1EBFF]"
            >
              <X className="h-3.5 w-3.5" aria-hidden="true" />
            </button>
          </li>
        ))}
        {files.length < MAX_SETUP_PHOTOS && (
          <li>
            <button
              type="button"
              onClick={() => inputRef.current?.click()}
              className="flex aspect-[4/3] w-full flex-col items-center justify-center gap-1.5 rounded-lg border border-dashed border-[#4817C2]/50 bg-[#F8F4FF] text-sm font-semibold text-[#4817C2] transition-colors hover:bg-[#F1EBFF] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#4817C2]"
            >
              <ImagePlus className="h-6 w-6" aria-hidden="true" />
              {files.length === 0 ? "Upload Photos" : "Upload More"}
            </button>
          </li>
        )}
      </ul>

      <p className="mt-2 text-xs font-normal text-[#666666]">
        {files.length} of {MAX_SETUP_PHOTOS} added · GameAll checks each photo before players see it.
      </p>
      {(problem || error) && <FieldError>{problem ?? error}</FieldError>}
    </div>
  );
}
