import type { Metadata } from "next";
import { AuthCard } from "@/features/auth/components/auth-card";
import { VerifyMobilePanel } from "@/features/mobile-otp/components/verify-mobile-panel";
import { PRODUCT_NAME } from "@/lib/constants";

export const metadata: Metadata = {
  title: `Verify your mobile — ${PRODUCT_NAME}`,
};

export default function VerifyMobilePage() {
  return (
    <AuthCard title="Verify Your Mobile" subtitle="We'll call you with a 6-digit OTP to confirm your number. Please accept the incoming call and enter the code you hear.">
      <VerifyMobilePanel />
    </AuthCard>
  );
}
