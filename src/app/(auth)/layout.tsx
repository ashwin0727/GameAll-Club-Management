import { CalendarCheck, IndianRupee, LayoutGrid, Users } from "lucide-react";
import { BrandMark } from "@/features/auth/components/brand-mark";
import { PendingSignupProvider } from "@/features/auth/context/pending-signup";
import { PRODUCT_TAGLINE, SUPPORTED_SPORTS } from "@/lib/constants";

const HIGHLIGHTS = [
  { Icon: CalendarCheck, label: "Court bookings without double-booking" },
  { Icon: Users, label: "Members, packages and attendance" },
  { Icon: IndianRupee, label: "Payments, dues and daily collections" },
  { Icon: LayoutGrid, label: "Every sport and court in one view" },
];

/**
 * Shell for the whole signed-out flow.
 *
 * Mobile is a single full-height column. From `lg` a branded panel appears
 * alongside the form — the desktop layout earns its width instead of stretching
 * the phone one.
 */
export default function AuthLayout({ children }: { children: React.ReactNode }) {
  return (
    <PendingSignupProvider>
      <div className="flex min-h-[100dvh] bg-background">
        <aside className="relative hidden w-[46%] max-w-[620px] flex-col justify-between overflow-hidden border-r border-border bg-secondary p-12 lg:flex">
          {/* Single soft wash — enough depth to read as branded, no glass stack. */}
          <div
            aria-hidden="true"
            className="pointer-events-none absolute -right-24 -top-24 h-[420px] w-[420px] rounded-full bg-primary/10 blur-3xl"
          />

          <BrandMark size="lg" className="relative" />

          <div className="relative space-y-8">
            <h2 className="max-w-md text-3xl font-semibold leading-tight tracking-tight">
              Your facility. Your courts. Your business — all in one place.
            </h2>
            <ul className="space-y-4">
              {HIGHLIGHTS.map(({ Icon, label }) => (
                <li key={label} className="flex items-center gap-3 text-sm text-muted-foreground">
                  <span className="flex h-8 w-8 shrink-0 items-center justify-center rounded-lg border border-border bg-card">
                    <Icon className="h-4 w-4 text-primary" aria-hidden="true" />
                  </span>
                  {label}
                </li>
              ))}
            </ul>
          </div>

          <p className="relative text-xs uppercase tracking-[0.18em] text-muted-foreground">
            {SUPPORTED_SPORTS.join(" · ")}
          </p>
        </aside>

        <main className="flex flex-1 flex-col justify-center px-5 py-10 pb-safe sm:px-8 sm:py-14">
          {children}
          <p className="mt-10 text-center text-xs text-muted-foreground lg:hidden">
            {PRODUCT_TAGLINE}
          </p>
        </main>
      </div>
    </PendingSignupProvider>
  );
}