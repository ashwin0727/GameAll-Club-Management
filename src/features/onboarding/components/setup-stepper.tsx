
const STEPS = ["Facility Information", "Sports & Courts", "Operating Hours", "Pricing", "Payout"] as const;

/** The compact "Step n of 5" bar for phones. On large screens the progress is tracked in the sidebar (see OnboardingShell). */
export function SetupStepper({ current = 1 }: { current?: number }) {
  return (
    <div role="status" aria-label={`Step ${current} of ${STEPS.length}: ${STEPS[current - 1]}`} className="lg:hidden">
      <div>
        <p className="text-xs font-semibold text-[#4817C2]">
          Step {current} of {STEPS.length} · {STEPS[current - 1]}
        </p>
        <div className="mt-2 h-1.5 w-full overflow-hidden rounded-full bg-[#F1EBFF]">
          <div className="h-full rounded-full bg-[#4817C2]" style={{ width: `${(current / STEPS.length) * 100}%` }} />
        </div>
      </div>
    </div>
  );
}
