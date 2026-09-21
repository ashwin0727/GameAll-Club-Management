"use client";

/**
 * The page header used by Calendar and Guest Bookings, 84px tall. The strip is bare — no
 * card, no background — so the title block sits directly on the page, top-aligned under
 * the top bar. The artwork panel on the right has no left edge of its own: it fades out
 * into the page colour, and its outline is masked so it only shows toward the right end
 * (where the shuttlecock is), softly, rather than boxing the whole thing. The tagline sits
 * in the panel's left ~60%, clear of the shuttlecock. One artwork per theme; the dark club
 * art keeps its athlete in the same free right-hand area.
 *
 * `actions` are buttons that straddle the panel's lower edge at the right, as in the
 * design; room is reserved below the header for them.
 */
export function PageHero({
  title,
  subtitle,
  tagline,
  taglineSub,
  actions,
}: {
  title: string;
  subtitle: string;
  tagline: string;
  taglineSub: string;
  actions?: React.ReactNode;
}) {
  return (
    <div className={actions ? "relative -mt-3 mb-5 h-[84px] w-full" : "relative -mt-3 h-[84px] w-full"}>
      <div className="relative z-10 flex h-full min-w-0 flex-col justify-start pt-1 lg:w-[52%]">
        <h1 className="truncate text-[28px] font-semibold leading-tight text-foreground">{title}</h1>
        <p className="mt-0.5 truncate text-sm text-muted-foreground">{subtitle}</p>
      </div>

      <div className="absolute inset-y-1 right-0 hidden w-[50%] overflow-hidden rounded-xl lg:block">
        <div
          aria-hidden
          className="absolute inset-0 bg-cover bg-[position:center_right] bg-no-repeat [mask-image:linear-gradient(to_right,transparent,black_38%)] dark:hidden"
          style={{ backgroundImage: "url(/assets/Booking_Hero.png)" }}
        />
        <div
          aria-hidden
          className="absolute inset-0 hidden bg-cover bg-[position:center_right] bg-no-repeat [mask-image:linear-gradient(to_right,transparent,black_38%)] dark:block"
          style={{ backgroundImage: "url(/assets/Dashboard-Hero.png)" }}
        />
        {/* The outline: strongest at the right end, gone by the left. */}
        <div
          aria-hidden
          className="pointer-events-none absolute inset-0 rounded-xl border border-border [mask-image:linear-gradient(to_left,black_20%,transparent_80%)] dark:border-white/15"
        />
        <div className="relative flex h-full w-[60%] flex-col justify-center pl-[9%]">
          <p className="text-[15px] font-semibold leading-snug text-foreground">{tagline}</p>
          <p className="mt-0.5 text-xs text-muted-foreground">{taglineSub}</p>
        </div>
      </div>

      {actions && (
        <div className="absolute bottom-0 right-2 z-20 flex translate-y-1/2 flex-wrap items-center justify-end gap-3">{actions}</div>
      )}
    </div>
  );
}
