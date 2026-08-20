"use client";

import * as React from "react";
import { Button } from "@/components/ui/button";
import { FieldError } from "@/features/auth/components/text-field";
import { ACCEPTED_LOGO_TYPES, MAX_LOGO_SIZE_BYTES } from "@/features/onboarding/constants";
import { cn } from "@/lib/utils";

export interface FileUploadProps {
  id?: string;
  label: string;
  hint?: string;
  value: File | string | null;
  onChange: (file: File | null) => void;
  className?: string;
}

const ACCEPT_ATTR = ACCEPTED_LOGO_TYPES.join(",");

function previewSrc(value: File | string | null): string | null {
  if (!value) return null;
  return typeof value === "string" ? value : URL.createObjectURL(value);
}

export function FileUpload({ id = "facility-logo", label, hint, value, onChange, className }: FileUploadProps) {
  const inputRef = React.useRef<HTMLInputElement>(null);
  const [error, setError] = React.useState<string | null>(null);
  const preview = React.useMemo(() => previewSrc(value), [value]);

  React.useEffect(() => {
    return () => {
      if (preview?.startsWith("blob:")) URL.revokeObjectURL(preview);
    };
  }, [preview]);

  function handleFiles(files: FileList | null) {
    const file = files?.[0];
    if (!file) return;

    if (!ACCEPTED_LOGO_TYPES.includes(file.type)) {
      setError("Upload a PNG, JPG, JPEG or WebP image.");
      return;
    }
    if (file.size > MAX_LOGO_SIZE_BYTES) {
      setError("File must be smaller than 5MB.");
      return;
    }

    setError(null);
    onChange(file);
  }

  return (
    <div className={cn("space-y-2", className)}>
      <input
        ref={inputRef}
        id={id}
        aria-label={label}
        type="file"
        accept={ACCEPT_ATTR}
        className="sr-only"
        onChange={(e) => handleFiles(e.target.files)}
      />

      {!value ? (
        <button
          type="button"
          onClick={() => inputRef.current?.click()}
          onDragOver={(e) => e.preventDefault()}
          onDrop={(e) => {
            e.preventDefault();
            handleFiles(e.dataTransfer.files);
          }}
          className="flex h-24 w-full items-center justify-center rounded-lg border border-dashed border-input text-sm font-medium text-muted-foreground transition-colors hover:border-primary hover:text-primary"
        >
          + Upload Logo
        </button>
      ) : (
        <div className="flex items-center gap-4">
          {preview && (
            // eslint-disable-next-line @next/next/no-img-element
            <img
              src={preview}
              alt="Facility logo preview"
              className="h-16 w-16 rounded-lg border border-border object-cover"
            />
          )}
          <div className="flex gap-2">
            <Button type="button" variant="outline" size="sm" onClick={() => inputRef.current?.click()}>
              Replace
            </Button>
            <Button type="button" variant="ghost" size="sm" onClick={() => onChange(null)}>
              Remove
            </Button>
          </div>
        </div>
      )}

      {hint && !error && <p className="text-xs text-muted-foreground">{hint}</p>}
      {error && <FieldError>{error}</FieldError>}
    </div>
  );
}
