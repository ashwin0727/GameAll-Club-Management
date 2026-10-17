"use client";

import { AlertTriangle } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";

/**
 * The app's own confirmation modal — used instead of the browser's `window.confirm`, which shows
 * "localhost says…" and cannot be styled. A destructive one carries a warning icon and a red confirm button.
 * It stays open (buttons disabled, "working" label) while `busy`, and the caller closes it when the work is done.
 */
export function ConfirmDialog({
  open,
  title,
  description,
  confirmLabel = "Confirm",
  busyLabel = "Working…",
  cancelLabel = "Cancel",
  destructive = false,
  busy = false,
  onConfirm,
  onCancel,
}: {
  open: boolean;
  title: string;
  description: React.ReactNode;
  confirmLabel?: string;
  busyLabel?: string;
  cancelLabel?: string;
  destructive?: boolean;
  busy?: boolean;
  onConfirm: () => void;
  onCancel: () => void;
}) {
  return (
    <Dialog open={open} onOpenChange={(o) => !o && !busy && onCancel()}>
      <DialogContent className="max-w-md">
        <DialogHeader>
          <div className="flex items-start gap-3">
            {destructive && (
              <span className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-destructive/10 text-destructive">
                <AlertTriangle className="h-5 w-5" aria-hidden />
              </span>
            )}
            <div className="space-y-1.5 text-left">
              <DialogTitle>{title}</DialogTitle>
              <DialogDescription>{description}</DialogDescription>
            </div>
          </div>
        </DialogHeader>
        <DialogFooter>
          <Button type="button" variant="outline" disabled={busy} onClick={onCancel}>
            {cancelLabel}
          </Button>
          <Button type="button" variant={destructive ? "destructive" : "default"} disabled={busy} onClick={onConfirm}>
            {busy ? busyLabel : confirmLabel}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
