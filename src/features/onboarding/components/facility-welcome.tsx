"use client";

import Image from "next/image";
import { useRouter } from "next/navigation";
import { ArrowRight, Check } from "lucide-react";
import { OnboardingShell } from "@/features/onboarding/components/onboarding-shell";
import { onboardingResumePath } from "@/features/onboarding/resume-path";
import { getFacilityService } from "@/services/facility";

const CHECKLIST = [
  "Add your facility details",
  "Configure sports and courts",
  "Set operating hours and pricing",
  "Add payout information",
  "Choose a plan and go live",
] as const;

export function FacilityWelcome() {
  const router = useRouter();

  // Someone who already started setup continues at the step they stopped on; a new owner starts at the first step.
  async function getStarted() {
    try {
      const facility = await getFacilityService().getFacility();
      router.push(onboardingResumePath(facility?.onboardingStep));
    } catch {
      router.push("/onboarding/facility");
    }
  }

  return (
    <OnboardingShell firstStepLabel="Basic Details" fit>
      <main className="w-full min-w-0 flex-1 px-4 py-8 sm:px-8 sm:py-14 lg:flex lg:flex-col lg:justify-center lg:px-8 lg:py-6">
        <h1 className="text-3xl font-bold tracking-tight sm:text-5xl lg:text-4xl">Set Up Your Facility</h1>
        <p className="mt-3 text-base font-normal text-[#666666] sm:text-xl">Get your venue live on GameAll in a few simple steps.</p>

        <section className="mt-8 grid items-center gap-6 rounded-2xl border border-[#E5E1EF] bg-white p-5 sm:mt-10 sm:p-8 md:grid-cols-[1.1fr_1fr] md:gap-0 lg:mt-6 lg:p-6">
          <div className="md:border-r md:border-[#E5E1EF] md:pr-8">
            <Image
              src="/facility-welcome.png"
              alt="A sports arena with badminton, football, basketball, tennis and cricket icons"
              width={1535}
              height={1024}
              sizes="(min-width: 768px) 440px, 90vw"
              priority
              className="mx-auto h-auto w-full max-w-[440px] lg:max-h-[36vh] lg:w-auto"
            />
          </div>
          <ul className="space-y-4 sm:space-y-5 md:pl-10">
            {CHECKLIST.map((item) => (
              <li key={item} className="flex items-center gap-4 text-base font-medium sm:text-lg">
                <span className="flex h-8 w-8 shrink-0 items-center justify-center rounded-lg bg-[#F1EBFF]">
                  <Check className="h-4 w-4 text-[#4817C2]" strokeWidth={3} aria-hidden="true" />
                </span>
                {item}
              </li>
            ))}
          </ul>
        </section>

        <div className="mt-8 flex sm:justify-end lg:mt-6">
          <button
            type="button"
            onClick={getStarted}
            className="flex h-14 w-full items-center justify-center gap-3 rounded-xl bg-[#4817C2] px-8 text-base font-semibold text-white transition-colors hover:bg-[#39109F] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#4817C2] focus-visible:ring-offset-2 sm:w-auto sm:min-w-[220px]"
          >
            Get Started
            <ArrowRight className="h-5 w-5" aria-hidden="true" />
          </button>
        </div>
      </main>
    </OnboardingShell>
  );
}
