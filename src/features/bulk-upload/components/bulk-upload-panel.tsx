"use client";

import { useRef, useState } from "react";
import { AlertTriangle, CheckCircle2, Download, FileSpreadsheet, Loader2, Upload } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import type { BulkError } from "@/features/bulk-upload/spreadsheet";
import { cn } from "@/lib/utils";

interface Props {
  /** "Members" / "Students" — used in the headings and buttons. */
  noun: "Members" | "Students";
  /** When set the whole panel is switched off and this says why (e.g. no active plan). */
  disabledReason?: string | null;
  onDownloadTemplate: () => Promise<void>;
  /** Reads and checks the chosen file; resolves with every problem found (empty = good to upload) and the row count. */
  onValidate: (file: File) => Promise<{ errors: BulkError[]; count: number }>;
  /** Creates everyone from the last successful validation. Navigates away itself when done. */
  onUpload: (onProgress: (done: number, total: number) => void) => Promise<void>;
  className?: string;
}

/** The "Bulk Upload" block above the single-person form: sample download → choose file → check → upload. */
export function BulkUploadPanel({ noun, disabledReason, onDownloadTemplate, onValidate, onUpload, className }: Props) {
  const inputRef = useRef<HTMLInputElement>(null);
  const [fileName, setFileName] = useState<string | null>(null);
  const [checking, setChecking] = useState(false);
  const [errors, setErrors] = useState<BulkError[]>([]);
  const [readyCount, setReadyCount] = useState<number | null>(null);
  const [progress, setProgress] = useState<{ done: number; total: number } | null>(null);
  const [failure, setFailure] = useState<string | null>(null);
  const disabled = Boolean(disabledReason);
  const uploading = progress !== null;
  const singular = noun === "Members" ? "member" : "student";

  async function choose(file: File | undefined) {
    setErrors([]);
    setReadyCount(null);
    setFailure(null);
    if (!file) return;
    setFileName(file.name);
    setChecking(true);
    try {
      const result = await onValidate(file);
      setErrors(result.errors);
      setReadyCount(result.errors.length === 0 ? result.count : null);
    } catch {
      setFailure("That file couldn't be checked. Please try again.");
    } finally {
      setChecking(false);
      if (inputRef.current) inputRef.current.value = "";
    }
  }

  async function upload() {
    setFailure(null);
    setProgress({ done: 0, total: readyCount ?? 0 });
    try {
      await onUpload((done, total) => setProgress({ done, total }));
    } catch {
      setFailure("The upload was interrupted. Check the list before uploading again so nobody is added twice.");
      setProgress(null);
    }
  }

  return (
    <Card className={cn("space-y-4 rounded-xl border-dashed p-4", disabled && "opacity-70", className)}>
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div className="flex items-start gap-3">
          <span className="flex h-10 w-10 shrink-0 items-center justify-center rounded-lg bg-primary/10 text-primary">
            <FileSpreadsheet className="h-5 w-5" aria-hidden />
          </span>
          <div>
            <h3 className="text-sm font-semibold text-foreground">Bulk Upload</h3>
            <p className="text-xs text-muted-foreground">
              Add many {noun.toLowerCase()} at once from an Excel sheet. Everyone gets a Razorpay payment link by SMS.
            </p>
          </div>
        </div>
        <Button type="button" variant="outline" size="sm" disabled={disabled || uploading} onClick={() => void onDownloadTemplate()}>
          <Download className="mr-1.5 h-4 w-4" aria-hidden />
          Download Sample Excel
        </Button>
      </div>

      {disabled ? (
        <p className="rounded-lg bg-muted/60 px-3 py-2 text-xs text-muted-foreground" role="note">
          {disabledReason}
        </p>
      ) : (
        <>
          <div className="flex flex-wrap items-center gap-3">
            <input
              ref={inputRef}
              type="file"
              accept=".xlsx,application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
              className="sr-only"
              aria-label={`Upload ${noun} Excel File`}
              onChange={(e) => void choose(e.target.files?.[0])}
            />
            <Button type="button" variant="outline" size="sm" disabled={checking || uploading} onClick={() => inputRef.current?.click()}>
              {checking ? <Loader2 className="mr-1.5 h-4 w-4 animate-spin" aria-hidden /> : <Upload className="mr-1.5 h-4 w-4" aria-hidden />}
              {checking ? "Checking…" : "Choose Filled Excel"}
            </Button>
            {fileName && <span className="text-xs text-muted-foreground">{fileName}</span>}
            {readyCount !== null && (
              <Button type="button" size="sm" disabled={uploading} onClick={() => void upload()}>
                {uploading ? <Loader2 className="mr-1.5 h-4 w-4 animate-spin" aria-hidden /> : null}
                {uploading ? `Uploading ${progress!.done}/${progress!.total}…` : `Upload ${readyCount} ${readyCount === 1 ? singular : noun.toLowerCase()}`}
              </Button>
            )}
          </div>

          {readyCount !== null && !uploading && (
            <p className="flex items-center gap-1.5 text-xs text-success" role="status">
              <CheckCircle2 className="h-4 w-4" aria-hidden />
              All {readyCount} {readyCount === 1 ? "row looks" : "rows look"} good. Review, then upload.
            </p>
          )}
          {failure && (
            <p className="text-xs text-destructive" role="alert">
              {failure}
            </p>
          )}
          {errors.length > 0 && (
            <div className="space-y-2" role="alert">
              <p className="flex items-center gap-1.5 text-xs font-medium text-destructive">
                <AlertTriangle className="h-4 w-4" aria-hidden />
                Nothing was uploaded — fix {errors.length === 1 ? "this problem" : `these ${errors.length} problems`} and choose the file again.
              </p>
              <div className="max-h-56 overflow-auto rounded-lg border border-border">
                <table className="w-full text-left text-xs">
                  <thead className="sticky top-0 bg-muted/80 text-muted-foreground">
                    <tr>
                      <th className="px-3 py-1.5 font-medium">Row</th>
                      <th className="px-3 py-1.5 font-medium">Column</th>
                      <th className="px-3 py-1.5 font-medium">Problem</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-border/60">
                    {errors.map((e, i) => (
                      <tr key={i}>
                        <td className="whitespace-nowrap px-3 py-1.5 tabular-nums">{e.row > 0 ? e.row : "—"}</td>
                        <td className="whitespace-nowrap px-3 py-1.5">{e.column || "—"}</td>
                        <td className="px-3 py-1.5 text-destructive">{e.message}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </div>
          )}
        </>
      )}
    </Card>
  );
}
