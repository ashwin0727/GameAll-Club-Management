import { MapPin, Phone } from "lucide-react";
import { BrandLogo } from "@/features/auth/components/brand-mark";
import { APP_NAME } from "@/lib/constants";

/**
 * The bar across the top of every public booking screen — the landing page
 * and each step of the flow.
 *
 * BrandLogo, not BrandMark: the mark carries "Club Management" beneath the
 * name, which is the admin lockup. A player gets the player-facing tagline.
 */
export function PublicBookingHeader({
  helpPhone,
  facilityName,
  city,
}: {
  helpPhone: string | null;
  /**
   * Shown centred, for screens where the venue isn't already the headline.
   * The landing page omits it — its hero is the venue name, and repeating
   * it a few pixels above would just read as a mistake.
   */
  facilityName?: string;
  city?: string;
}) {
  return (
    <header className="grid grid-cols-[auto_1fr_auto] items-center gap-3 border-b border-border px-4 py-4 sm:px-8">
      <div className="flex items-center gap-2.5">
        <BrandLogo className="h-8 w-8" />
        <span className="flex flex-col leading-tight">
          <span className="text-sm font-semibold">{APP_NAME}</span>
          <span className="hidden text-[11px] text-muted-foreground sm:block">Book. Play. Enjoy.</span>
        </span>
      </div>

      {/* Hidden on phones, where the logo and the help number already fill
          the row — the flow names the venue in its Facility field anyway. */}
      {facilityName ? (
        <div className="hidden min-w-0 text-center md:block">
          <p className="truncate text-sm font-semibold">{facilityName}</p>
          {city && (
            <p className="flex items-center justify-center gap-1 truncate text-[11px] text-muted-foreground">
              <MapPin className="h-3 w-3 shrink-0" aria-hidden />
              {city}
            </p>
          )}
        </div>
      ) : (
        <span aria-hidden />
      )}

      {helpPhone ? (
        <div className="text-right">
          <p className="text-[11px] text-muted-foreground">Need Help?</p>
          <a
            href={`tel:${helpPhone.replace(/\s/g, "")}`}
            className="flex items-center justify-end gap-1.5 text-sm font-medium text-foreground hover:text-primary"
          >
            <Phone className="h-3.5 w-3.5 text-primary" aria-hidden />
            {helpPhone}
          </a>
        </div>
      ) : (
        <span aria-hidden />
      )}
    </header>
  );
}
