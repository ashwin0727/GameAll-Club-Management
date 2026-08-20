"use client";

import { useEffect } from "react";
import { useRouter } from "next/navigation";
import { BrandLogo } from "@/features/auth/components/brand-mark";
import { resolveEntryRoute } from "@/features/auth/entry-route";
import { PRODUCT_NAME, PRODUCT_TAGLINE } from "@/lib/constants";
import { hasDeviceOnboarded } from "@/lib/storage/onboarding";

const SPLASH_DURATION_MS = 1600;

/**
 * Entry screen. The session was already resolved on the server; the only work
 * left here is the device check that separates a first-ever visit (Welcome)
 * from a returning signed-out one (Login).
 *
 * It holds for ~1.6s so the brand registers without the app feeling slow, and
 * shows an indeterminate indicator — never a fake percentage.
 */
export function SplashScreen({
  signedIn,
  onboardingCompleted,
}: {
  signedIn: boolean;
  onboardingCompleted: boolean;
}) {
  const router = useRouter();

  useEffect(() => {
    const next = resolveEntryRoute({
      signedIn,
      deviceOnboarded: hasDeviceOnboarded(),
      onboardingCompleted,
    });
    // Prefetch during the hold so the transition lands instantly.
    router.prefetch(next);

    const timer = window.setTimeout(() => router.replace(next), SPLASH_DURATION_MS);
    return () => window.clearTimeout(timer);
  }, [router, signedIn, onboardingCompleted]);

  return (
    <main className="flex min-h-[100dvh] flex-col items-center justify-center bg-background px-6">
      <div className="flex flex-col items-center text-center">
        <div className="animate-in fade-in zoom-in-95 duration-500">
          <BrandLogo className="h-16 w-16" />
        </div>

        <h1 className="mt-6 animate-in fade-in text-2xl font-semibold tracking-tight duration-500 delay-100 fill-mode-backwards">
          {PRODUCT_NAME}
        </h1>

        <p className="mt-2 max-w-[18rem] animate-in fade-in text-sm leading-relaxed text-muted-foreground duration-500 delay-200 fill-mode-backwards">
          {PRODUCT_TAGLINE}
        </p>
      </div>

      <div
        className="absolute bottom-16 flex items-center gap-2"
        role="status"
        aria-label="Loading"
      >
        {[0, 1, 2].map((index) => (
          <span
            key={index}
            className="h-1.5 w-1.5 animate-pulse rounded-full bg-primary/60"
            style={{ animationDelay: `${index * 150}ms` }}
          />
        ))}
      </div>
    </main>
  );
}