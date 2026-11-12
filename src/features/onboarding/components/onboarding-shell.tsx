"use client";

import Image from "next/image";
import { Inter } from "next/font/google";
import { Building2, Check, CircleHelp, Clock, Tag, Trophy, Wallet } from "lucide-react";
import { LEGAL_CONTACT_EMAIL } from "@/features/legal/legal-page";
import { cn } from "@/lib/utils";

// Facility Setup is light-mode only and uses Inter (400/500/600/700).
const inter = Inter({ subsets: ["latin"], weight: ["400", "500", "600", "700"], display: "swap" });

/** The setup font's class, for menus that render in a portal outside the shell (they would otherwise fall back to the app font). */
export const setupFontClass = inter.className;

const SIDEBAR_ICONS = [Building2, Trophy, Clock, Tag, Wallet] as const;
const OTHER_STEPS = ["Sports & Courts", "Operating Hours", "Pricing", "Payout"] as const;

/** The five setup steps; the first one's label differs between the welcome page ("Basic Details") and the form ("Facility Information"). */
export function setupStepLabels(firstLabel: string): string[] {
  return [firstLabel, ...OTHER_STEPS];
}

/**
 * The light-mode shell shared by the facility-setup screens: GameAll logo + help link on top and the step list on the left
 * (large screens). `fit` pins the page to the window height so a short screen never scrolls.
 */
export function OnboardingShell({
  firstStepLabel,
  activeStep = 0,
  fit = false,
  children,
}: {
  firstStepLabel: string;
  activeStep?: number;
  fit?: boolean;
  children: React.ReactNode;
}) {
  const labels = setupStepLabels(firstStepLabel);

  return (
    <div
      className={cn(inter.className, "flex min-h-[100dvh] flex-col bg-white text-[#171717]", fit && "lg:h-[100dvh] lg:overflow-hidden")}
      style={{ colorScheme: "light" }}
    >
      <header className="flex h-16 shrink-0 items-center justify-between border-b border-[#E5E1EF] px-4 sm:h-[72px] sm:px-8">
        <Image src="/brand/gameall-logo-light-mode.svg" alt="GameAll" width={960} height={218} unoptimized priority className="h-10 w-auto" />
        <a
          href={`mailto:${LEGAL_CONTACT_EMAIL}?subject=Facility%20setup%20help`}
          className="flex items-center gap-2 text-sm font-medium text-[#171717] hover:text-[#4817C2]"
        >
          <CircleHelp className="h-5 w-5" aria-hidden="true" />
          Need Help?
        </a>
      </header>

      <div className={cn("flex flex-1", fit && "lg:min-h-0")}>
        <aside className="hidden w-[300px] shrink-0 border-r border-[#E5E1EF] px-5 py-8 lg:block">
          {/* the progress tracker: a vertical line down the steps, a tick on each finished one */}
          <ol className="space-y-3" aria-label="Setup progress">
            {labels.map((label, index) => {
              const Icon = SIDEBAR_ICONS[index] ?? Building2;
              const state = index < activeStep ? "done" : index === activeStep ? "current" : "upcoming";
              const last = index === labels.length - 1;
              return (
                <li key={label} aria-current={state === "current" ? "step" : undefined} className="relative flex items-center gap-3">
                  {!last && (
                    <span
                      aria-hidden="true"
                      className={cn("absolute left-[15px] top-[calc(50%+16px)] h-[calc(100%-20px)] w-0.5 rounded-full", state === "done" ? "bg-[#4817C2]" : "bg-[#E5E1EF]")}
                    />
                  )}
                  <span
                    className={cn(
                      "relative z-10 flex h-8 w-8 shrink-0 items-center justify-center rounded-full border text-sm font-semibold",
                      (state === "done" || state === "current") && "border-[#4817C2] bg-[#4817C2] text-white",
                      state === "upcoming" && "border-[#E5E1EF] bg-white text-[#171717]",
                    )}
                  >
                    {state === "done" ? <Check className="h-4 w-4" strokeWidth={3} aria-label="Completed" /> : index + 1}
                  </span>
                  <span
                    className={cn(
                      "flex min-h-[56px] flex-1 items-center gap-3 rounded-xl border px-4 py-3 text-[15px] font-semibold",
                      state === "current" && "border-[#4817C2] bg-[#F1EBFF]",
                      // a finished step keeps a lighter tint of the same purple, so progress reads at a glance
                      state === "done" && "border-[#CDBDF2] bg-[#F8F4FF]",
                      state === "upcoming" && "border-[#E5E1EF] bg-[#FBFAFE]",
                    )}
                  >
                    <Icon className={cn("h-5 w-5 shrink-0", state === "upcoming" ? "text-[#666666]" : "text-[#4817C2]")} aria-hidden="true" />
                    {label}
                  </span>
                </li>
              );
            })}
          </ol>
        </aside>
        {children}
      </div>
    </div>
  );
}
