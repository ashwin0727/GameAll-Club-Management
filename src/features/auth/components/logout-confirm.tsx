"use client";

import { ConfirmDialog } from "@/components/shared/confirm-dialog";
import { useLogout } from "@/features/auth/hooks/use-auth";

/** "Log out of GameAll?" — the one confirmation every Log out / Sign out button goes through. */
export function LogoutConfirm({
  open,
  facilityName,
  onCancel,
}: {
  open: boolean;
  facilityName?: string | null;
  onCancel: () => void;
}) {
  const logout = useLogout();
  return (
    <ConfirmDialog
      open={open}
      destructive
      title="Log out of GameAll?"
      description={`You'll be signed out of ${facilityName ?? "your facility"} on this device. You can sign back in any time.`}
      confirmLabel="Log out"
      busyLabel="Logging out…"
      busy={logout.isPending}
      onConfirm={() => logout.mutate()}
      onCancel={onCancel}
    />
  );
}
