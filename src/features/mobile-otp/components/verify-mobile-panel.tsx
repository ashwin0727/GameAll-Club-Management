"use client";

import * as React from "react";
import { useRouter } from "next/navigation";
import { useQueryClient } from "@tanstack/react-query";
import { Phone } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Label } from "@/components/ui/label";
import { tenDigitMobile } from "../mobile-otp";
import { MobileOtpVerifier } from "./mobile-otp-verifier";

/** Signup step 2 (after the email code): the new owner proves their mobile number, then continues to onboarding. */
export function VerifyMobilePanel() {
  const router = useRouter();
  const queryClient = useQueryClient();
  const [phone, setPhone] = React.useState("");
  const [verified, setVerified] = React.useState(false);

  function proceed() {
    void queryClient.invalidateQueries({ queryKey: ["auth", "current-user"] });
    router.replace("/onboarding/facility");
    router.refresh();
  }

  return (
    <div className="space-y-6">
      <div className="space-y-2">
        <Label htmlFor="owner-mobile">Mobile Number</Label>
        <div className="flex h-11 items-center overflow-hidden rounded-xl border border-input bg-secondary/60 focus-within:ring-2 focus-within:ring-ring/40">
          <span className="flex h-full shrink-0 items-center gap-1.5 border-r border-input px-3 text-sm text-muted-foreground">
            <Phone className="h-4 w-4" aria-hidden /> +91
          </span>
          <input
            id="owner-mobile"
            type="tel"
            inputMode="numeric"
            autoComplete="tel-national"
            placeholder="Enter 10-digit mobile number"
            value={phone}
            disabled={verified}
            onChange={(e) => setPhone(e.target.value.replace(/\D/g, "").slice(0, 10))}
            className="h-full min-w-0 flex-1 bg-transparent px-3 text-base outline-none placeholder:text-muted-foreground sm:text-sm"
          />
        </div>
        <MobileOtpVerifier
          phone={phone}
          purpose="signup"
          verified={verified}
          onVerified={() => setVerified(true)}
          onReset={() => setVerified(false)}
        />
      </div>

      <Button type="button" className="h-11 w-full text-sm font-semibold" disabled={!verified || !tenDigitMobile(phone)} onClick={proceed}>
        Continue
      </Button>
    </div>
  );
}
