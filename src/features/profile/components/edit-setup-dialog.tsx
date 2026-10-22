"use client";

import { useRouter } from "next/navigation";
import { useQueryClient } from "@tanstack/react-query";
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { CourtsSetupForm } from "@/features/courts-setup/components/courts-setup-form";
import { OperatingHoursForm } from "@/features/operating-hours/components/operating-hours-form";
import { PricingForm } from "@/features/pricing/components/pricing-form";
import { SportsSetupForm } from "@/features/sports-setup/components/sports-setup-form";

export type SetupSection = "sports" | "courts" | "hours" | "pricing";

const COPY: Record<SetupSection, { title: string; description: string }> = {
  sports: { title: "Edit sports", description: "Choose the sports your facility offers." },
  courts: { title: "Edit courts & turfs", description: "Add, rename, switch on or off, or remove the courts and turfs under each sport." },
  hours: { title: "Edit court timings", description: "Set when your facility — and individual courts — are open." },
  pricing: { title: "Edit pricing", description: "Set a default rate for a sport, or a rate for each court." },
};

/** Where a "Fix …" link from the setup checklist points to, as a section. */
export function sectionForHref(href: string): SetupSection | null {
  if (href.includes("/onboarding/sports")) return "sports";
  if (href.includes("/onboarding/courts")) return "courts";
  if (href.includes("/onboarding/operating-hours")) return "hours";
  if (href.includes("/onboarding/pricing")) return "pricing";
  return null;
}

/**
 * Edits one part of the facility's setup in a popup. It reuses the setup forms themselves — the same fields and rules —
 * but saving closes the popup and refreshes the page instead of moving on to the next onboarding step.
 */
export function EditSetupDialog({ section, onClose }: { section: SetupSection; onClose: () => void }) {
  const router = useRouter();
  const qc = useQueryClient();
  const { title, description } = COPY[section];

  async function saved() {
    // Courts, sports, timings and pricing feed the calendar, bookings, memberships, coaching, reports and the top bar's
    // sport picker, so every cached query is stale now — not just the profile ones.
    await qc.invalidateQueries();
    router.refresh();
    onClose();
  }

  return (
    <Dialog open onOpenChange={(open) => !open && onClose()}>
      <DialogContent className="max-h-[92vh] max-w-4xl overflow-y-auto">
        <DialogHeader>
          <DialogTitle>{title}</DialogTitle>
          <DialogDescription>{description}</DialogDescription>
        </DialogHeader>
        {section === "sports" && <SportsSetupForm onDone={saved} />}
        {section === "courts" && <CourtsSetupForm onDone={saved} />}
        {section === "hours" && <OperatingHoursForm onDone={saved} />}
        {section === "pricing" && <PricingForm onDone={saved} />}
      </DialogContent>
    </Dialog>
  );
}
