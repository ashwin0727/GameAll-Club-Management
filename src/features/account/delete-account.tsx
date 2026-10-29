"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { AlertTriangle } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { createClient } from "@/lib/supabase/client";

type Outcome = { status: "deleted" } | { status: "pending"; unsettledCount: number; unsettledInr: number };

/** Calls the delete-account edge function. The person can only ever delete themselves: the server reads who they are from their sign-in. */
async function requestDeletion(): Promise<Outcome> {
  const supabase = createClient();
  const { data, error } = await supabase.functions.invoke<Outcome & { error?: string }>("delete-account", { body: { confirm: true } });
  if (error) {
    let message = "We could not delete your account. Please try again or contact support.";
    const ctx = (error as { context?: Response }).context;
    if (ctx && typeof ctx.json === "function") {
      try {
        const body = (await ctx.json()) as { error?: string };
        if (body.error) message = body.error;
      } catch {
        /* keep the default */
      }
    }
    throw new Error(message);
  }
  if (!data || (data.status !== "deleted" && data.status !== "pending")) throw new Error("We could not delete your account. Please try again.");
  return data;
}

const CONFIRM_WORD = "DELETE";

/** The confirmation: says exactly what goes, asks the person to type DELETE, then deletes and signs out. */
export function DeleteAccountDialog({ open, onClose }: { open: boolean; onClose: () => void }) {
  const router = useRouter();
  const qc = useQueryClient();
  const [typed, setTyped] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [pending, setPending] = useState<Extract<Outcome, { status: "pending" }> | null>(null);

  async function signOutAndLeave(to: string) {
    try {
      await createClient().auth.signOut({ scope: "local" });
    } catch {
      /* the account is gone or closed either way */
    }
    qc.clear();
    router.replace(to);
    router.refresh();
  }

  async function confirm() {
    setBusy(true);
    setError(null);
    try {
      const outcome = await requestDeletion();
      if (outcome.status === "deleted") {
        await signOutAndLeave("/login?deleted=1");
      } else {
        setPending(outcome);
      }
    } catch (e) {
      setError(e instanceof Error ? e.message : "We could not delete your account. Please try again.");
    } finally {
      setBusy(false);
    }
  }

  if (pending) {
    return (
      <Dialog open={open} onOpenChange={() => undefined}>
        <DialogContent className="max-w-md">
          <DialogHeader>
            <DialogTitle>Your account is closed</DialogTitle>
            <DialogDescription>
              {pending.unsettledCount} online payment{pending.unsettledCount === 1 ? "" : "s"} (₹{Math.round(pending.unsettledInr).toLocaleString("en-IN")}) still need to be
              settled to you. We keep those payment records until that is done, then everything else is deleted automatically. Auto Pay has been cancelled and no one can book
              with your facility.
            </DialogDescription>
          </DialogHeader>
          <DialogFooter>
            <Button onClick={() => void signOutAndLeave("/login")}>OK</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    );
  }

  return (
    <Dialog open={open} onOpenChange={(o) => !o && !busy && onClose()}>
      <DialogContent className="max-w-md">
        <DialogHeader>
          <div className="flex items-start gap-3">
            <span className="mt-0.5 flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-destructive/10 text-destructive">
              <AlertTriangle className="h-5 w-5" aria-hidden />
            </span>
            <div>
              <DialogTitle>Delete your account?</DialogTitle>
              <DialogDescription className="mt-1">This cannot be undone.</DialogDescription>
            </div>
          </div>
        </DialogHeader>
        <div className="space-y-3 text-sm">
          <p>Deleting your account removes:</p>
          <ul className="list-disc space-y-1 pl-5 text-muted-foreground">
            <li>Your sign-in and profile.</li>
            <li>Your facility and everything in it: courts, bookings, members, memberships, coaching and finance records.</li>
            <li>The staff accounts that only worked at your facility.</li>
            <li>Your plan and Auto Pay. Members paying through Auto Pay are no longer charged.</li>
          </ul>
          <p className="text-muted-foreground">
            If any online payment is still waiting to be settled to you, we keep those payment records and close your account right away; everything is deleted once they are
            settled.
          </p>
          <label className="block space-y-1.5">
            <span className="text-xs font-medium">
              Type <span className="font-mono font-semibold">{CONFIRM_WORD}</span> to confirm
            </span>
            <Input value={typed} onChange={(e) => setTyped(e.target.value)} autoComplete="off" disabled={busy} aria-label={`Type ${CONFIRM_WORD} to confirm`} />
          </label>
          {error && (
            <p role="alert" className="text-sm text-destructive">
              {error}
            </p>
          )}
        </div>
        <DialogFooter className="gap-2 sm:gap-2">
          <Button variant="outline" onClick={onClose} disabled={busy}>
            Cancel
          </Button>
          <Button variant="destructive" onClick={() => void confirm()} disabled={busy || typed.trim() !== CONFIRM_WORD}>
            {busy ? "Deleting…" : "Delete my account"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

/** Body of the public /delete-account page: a delete button when signed in, a sign-in prompt when not. */
export function DeleteAccountPanel() {
  const [open, setOpen] = useState(false);
  const { data: signedIn, isLoading } = useQuery({
    queryKey: ["account", "signed-in"],
    queryFn: async () => (await createClient().auth.getUser()).data.user !== null,
    retry: false,
  });

  if (isLoading) return null;
  return (
    <div className="rounded-xl border border-border bg-card p-5">
      {signedIn ? (
        <>
          <p className="text-sm">You are signed in. You can delete your account right here.</p>
          <Button variant="destructive" className="mt-3" onClick={() => setOpen(true)}>
            Delete my account
          </Button>
          <DeleteAccountDialog open={open} onClose={() => setOpen(false)} />
        </>
      ) : (
        <p className="text-sm">
          To delete your account here, <a className="font-medium text-primary hover:underline" href="/login">sign in</a> and open this page again, or use one of the other options below.
        </p>
      )}
    </div>
  );
}
