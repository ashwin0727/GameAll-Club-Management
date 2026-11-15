"use client";

import * as React from "react";
import { LogOut, X } from "lucide-react";
import { Dialog, DialogContent, DialogDescription, DialogTitle } from "@/components/ui/dialog";
import { useLogout } from "@/features/auth/hooks/use-auth";

const DOOR_PICTURE = "/logout-door.png";

/** "Log Out?" — the one confirmation every Log out / Sign out button goes through. */
export function LogoutConfirm({
  open,
  onCancel,
}: {
  open: boolean;
  /** Kept so existing callers still compile; the wording no longer names the facility. */
  facilityName?: string | null;
  onCancel: () => void;
}) {
  const logout = useLogout();
  const busy = logout.isPending;

  // The picture is fetched and decoded as soon as the page is up (this component is always mounted), so it is already there
  // when the popup opens, and the picture and the words appear together.
  React.useEffect(() => {
    const img = new window.Image();
    img.src = DOOR_PICTURE;
    void img.decode?.().catch(() => undefined);
  }, []);
  return (
    <Dialog open={open} onOpenChange={(o) => !o && !busy && onCancel()}>
      <DialogContent onOpenAutoFocus={(e) => { e.preventDefault(); (e.currentTarget as HTMLElement).focus(); }} className="focus:outline-none max-w-[420px] rounded-3xl border-0 bg-[#FBFAFD] p-6 pb-7 shadow-2xl sm:p-8 [&>button.absolute]:hidden">
        <button
          type="button"
          aria-label="Close"
          disabled={busy}
          onClick={onCancel}
          className="absolute right-4 top-4 flex h-9 w-9 items-center justify-center rounded-full bg-[#EEEAF7] text-[#171717] transition-colors hover:bg-[#E5E1EF] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#4817C2] disabled:opacity-50"
        >
          <X className="h-4 w-4" aria-hidden="true" />
        </button>

        {/* eslint-disable-next-line @next/next/no-img-element -- preloaded above; the optimiser would fetch a different URL on open */}
        <img src={DOOR_PICTURE} alt="" aria-hidden="true" width={540} height={390} decoding="sync" className="mx-auto h-auto w-[200px]" />

        <div className="mt-2 text-center">
          <DialogTitle className="text-[28px] font-bold leading-tight tracking-tight text-[#171717]">Log Out?</DialogTitle>
          <DialogDescription className="mx-auto mt-3 max-w-[300px] text-base font-normal leading-snug text-[#3F3F46]">
            Are you sure you want to log out of your GameAll account?
          </DialogDescription>
        </div>

        <div className="mt-7 grid grid-cols-2 gap-4">
          <button
            type="button"
            disabled={busy}
            onClick={onCancel}
            className="h-14 rounded-xl border border-[#C9C4DA] bg-white text-base font-bold text-[#171717] transition-colors hover:bg-[#F7F5FB] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#4817C2] disabled:opacity-50"
          >
            Cancel
          </button>
          <button
            type="button"
            disabled={busy}
            onClick={() => logout.mutate()}
            className="flex h-14 items-center justify-center gap-2.5 rounded-xl bg-gradient-to-b from-[#5B21D6] to-[#4817C2] text-base font-bold text-white shadow-[0_6px_14px_rgba(72,23,194,0.3)] transition hover:from-[#4817C2] hover:to-[#39109F] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#4817C2] focus-visible:ring-offset-2 disabled:opacity-70"
          >
            <LogOut className="h-5 w-5" aria-hidden="true" />
            {busy ? "Logging out…" : "Log Out"}
          </button>
        </div>
      </DialogContent>
    </Dialog>
  );
}
