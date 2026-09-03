import { Phone } from "lucide-react";
import { BrandLogo } from "@/features/auth/components/brand-mark";
import { APP_NAME } from "@/lib/constants";

/**
 * The bar across the top of every public booking screen — the landing page
 * and each step of the flow.
 *
 * BrandLogo, not BrandMark: the mark carries "Club Management" beneath the
 * name, which is the admin lockup. A player gets the player-facing tagline.
 */
export function PublicBookingHeader({ helpPhone }: { helpPhone: string | null }) {
  return (
    <header className="flex flex-wrap items-center justify-between gap-3 border-b border-border px-4 py-4 sm:px-8">
      <div className="flex items-center gap-2.5">
        <BrandLogo className="h-8 w-8" />
        <span className="flex flex-col leading-tight">
          <span className="text-sm font-semibold">{APP_NAME}</span>
          <span className="text-[11px] text-muted-foreground">Book. Play. Enjoy.</span>
        </span>
      </div>

      {helpPhone && (
        <div className="text-right">
          <p className="text-[11px] text-muted-foreground">Need Help?</p>
          <a
            href={`tel:${helpPhone.replace(/\s/g, "")}`}
            className="flex items-center gap-1.5 text-sm font-medium text-foreground hover:text-primary"
          >
            <Phone className="h-3.5 w-3.5 text-primary" aria-hidden />
            {helpPhone}
          </a>
        </div>
      )}
    </header>
  );
}
