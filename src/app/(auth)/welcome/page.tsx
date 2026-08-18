import type { Metadata } from "next";
import Link from "next/link";
import { Button } from "@/components/ui/button";
import { BrandMark } from "@/features/auth/components/brand-mark";
import { PRODUCT_NAME, SUPPORTED_SPORTS } from "@/lib/constants";

export const metadata: Metadata = {
  title: `Get started — ${PRODUCT_NAME}`,
  description: "Run bookings, members, courts and payments for your sports facility.",
};

export default function WelcomePage() {
  return (
    <div className="auth-enter mx-auto w-full max-w-[460px]">
      <BrandMark className="mb-10 lg:hidden" />

      <h1 className="text-3xl font-semibold leading-[1.15] tracking-tight sm:text-[2.125rem]">
        Run your entire facility from one place.
      </h1>

      <p className="mt-4 text-base leading-relaxed text-muted-foreground">
        Manage bookings, members, payments, courts, tournaments, expenses and more — without Excel
        or manual tracking.
      </p>

      <div className="mt-9 flex flex-col gap-3">
        <Button asChild className="h-12 text-sm font-semibold">
          <Link href="/signup">Create Account</Link>
        </Button>
        <Button asChild variant="outline" className="h-12 text-sm font-semibold">
          <Link href="/login">Sign In</Link>
        </Button>
      </div>

      <div className="mt-10 border-t border-border pt-6">
        <p className="text-xs uppercase tracking-[0.18em] text-muted-foreground">Built for</p>
        <div className="mt-3 flex flex-wrap gap-2">
          {SUPPORTED_SPORTS.map((sport) => (
            <span
              key={sport}
              className="rounded-full border border-border bg-card px-3 py-1.5 text-xs font-medium text-foreground"
            >
              {sport}
            </span>
          ))}
          <span className="rounded-full border border-dashed border-border px-3 py-1.5 text-xs font-medium text-muted-foreground">
            + more
          </span>
        </div>
      </div>
    </div>
  );
}