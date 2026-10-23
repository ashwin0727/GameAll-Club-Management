"use client";

import * as React from "react";
import { BadgeCheck, Loader2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { sendMobileOtp, tenDigitMobile, verifyMobileOtp, type MobileOtpPurpose } from "../mobile-otp";

const RESEND_SECONDS = 30;

/**
 * "Send OTP → enter the 6-digit code" for a mobile number that is typed elsewhere. Renders under the phone input.
 * Calls [onVerified] with the signed proof (booking) once the code checks out; [onReset] if the number is edited.
 */
export function MobileOtpVerifier({
  phone,
  purpose,
  verified,
  onVerified,
  onReset,
}: {
  phone: string;
  purpose: MobileOtpPurpose;
  verified: boolean;
  onVerified: (proof: string | undefined, phone: string) => void;
  onReset: () => void;
}) {
  const number = tenDigitMobile(phone);
  const [sentTo, setSentTo] = React.useState<string | null>(null);
  const [code, setCode] = React.useState("");
  const [busy, setBusy] = React.useState<"send" | "verify" | null>(null);
  const [error, setError] = React.useState<string | null>(null);
  const [cooldown, setCooldown] = React.useState(0);

  React.useEffect(() => {
    if (cooldown <= 0) return;
    const t = window.setTimeout(() => setCooldown((c) => c - 1), 1000);
    return () => window.clearTimeout(t);
  }, [cooldown]);

  // Editing the number after sending/verifying invalidates everything.
  React.useEffect(() => {
    if (sentTo && number !== sentTo) {
      setSentTo(null);
      setCode("");
      setError(null);
      onReset();
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [number]);

  async function send() {
    if (!number || busy) return;
    setBusy("send");
    setError(null);
    try {
      await sendMobileOtp(number, purpose);
      setSentTo(number);
      setCode("");
      setCooldown(RESEND_SECONDS);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Could not send the code.");
    } finally {
      setBusy(null);
    }
  }

  async function verify() {
    if (!number || code.length !== 6 || busy) return;
    setBusy("verify");
    setError(null);
    try {
      const proof = await verifyMobileOtp(number, code, purpose);
      onVerified(proof, number);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Could not verify the code.");
    } finally {
      setBusy(null);
    }
  }

  if (verified) {
    return (
      <p className="mt-2 inline-flex items-center gap-1.5 text-sm font-medium text-success">
        <BadgeCheck className="h-4 w-4" aria-hidden /> Mobile number verified
      </p>
    );
  }

  return (
    <div className="mt-2 space-y-2">
      {!sentTo ? (
        <Button type="button" variant="outline" size="sm" className="h-9" disabled={!number || busy !== null} onClick={() => void send()}>
          {busy === "send" && <Loader2 className="h-4 w-4 animate-spin" aria-hidden />}
          Call Me With OTP
        </Button>
      ) : (
        <div className="space-y-2">
          <p className="text-xs text-muted-foreground">
            We're calling +91 {sentTo} with your 6-digit OTP. Please <strong>accept the incoming call</strong>, listen to the code and enter it below.
          </p>
          <div className="flex items-center gap-2">
            <Input
              aria-label="Verification code from the call"
              inputMode="numeric"
              autoComplete="one-time-code"
              placeholder="6-digit code"
              value={code}
              onChange={(e) => setCode(e.target.value.replace(/\D/g, "").slice(0, 6))}
              className="h-9 w-36 text-center tracking-[0.3em]"
            />
            <Button type="button" size="sm" className="h-9" disabled={code.length !== 6 || busy !== null} onClick={() => void verify()}>
              {busy === "verify" && <Loader2 className="h-4 w-4 animate-spin" aria-hidden />}
              Verify
            </Button>
            <Button type="button" variant="ghost" size="sm" className="h-9" disabled={cooldown > 0 || busy !== null} onClick={() => void send()}>
              {cooldown > 0 ? `Call again in ${cooldown}s` : "Call Again"}
            </Button>
          </div>
        </div>
      )}
      {error && (
        <p role="alert" className="text-xs text-destructive">
          {error}
        </p>
      )}
    </div>
  );
}
