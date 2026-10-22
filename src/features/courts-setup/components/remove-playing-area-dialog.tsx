"use client";

import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";

export function RemovePlayingAreaDialog({
  open,
  onOpenChange,
  label,
  onConfirm,
  pending = false,
  blockedBy,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  label: string;
  onConfirm: () => void;
  pending?: boolean;
  /** What is still ahead on this court ("2 upcoming bookings, …"): when set, removal is refused until it is moved. */
  blockedBy?: string;
}) {
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>{blockedBy ? `This ${label.toLowerCase()} can't be removed yet` : `Remove this ${label.toLowerCase()}?`}</DialogTitle>
          <DialogDescription>
            {blockedBy
              ? `It still has ${blockedBy}. Move or cancel ${blockedBy.includes(",") || /^[2-9]|^\\d\\d/.test(blockedBy) ? "them" : "it"} first, then remove the ${label.toLowerCase()}.`
              : `Removing a ${label.toLowerCase()} will make it unavailable for new bookings, memberships and coaching. Everything already recorded on it stays in your history.`}
          </DialogDescription>
        </DialogHeader>
        <DialogFooter>
          {blockedBy ? (
            <Button type="button" onClick={() => onOpenChange(false)}>
              Got it
            </Button>
          ) : (
            <>
              <Button type="button" variant="outline" disabled={pending} onClick={() => onOpenChange(false)}>
                Cancel
              </Button>
              <Button type="button" variant="destructive" disabled={pending} onClick={onConfirm}>
                {pending ? "Removing…" : "Remove"}
              </Button>
            </>
          )}
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}