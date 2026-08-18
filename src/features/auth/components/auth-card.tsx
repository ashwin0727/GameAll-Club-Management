import Link from "next/link";
import { cn } from "@/lib/utils";
import { BrandMark } from "@/features/auth/components/brand-mark";

/**
 * The one container every auth screen uses.
 *
 * Mobile: full-bleed, no card chrome, content pinned to a comfortable top
 * offset. Desktop (sm+): a bordered card capped at 460px so the flow never
 * reads as a stretched phone layout.
 */
export function AuthCard({
  title,
  subtitle,
  children,
  footer,
  className,
}: {
  title: string;
  subtitle?: string;
  children: React.ReactNode;
  footer?: React.ReactNode;
  className?: string;
}) {
  return (
    <div className={cn("mx-auto w-full max-w-[460px]", className)}>
      <Link
        href="/"
        className="mb-8 inline-flex rounded-md outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 focus-visible:ring-offset-background sm:mb-10"
        aria-label="Turf Management home"
      >
        <BrandMark />
      </Link>

      <div className="auth-enter sm:rounded-2xl sm:border sm:border-border sm:bg-card sm:p-8 sm:shadow-xl sm:shadow-black/20">
        <header className="space-y-2">
          <h1 className="text-2xl font-semibold tracking-tight sm:text-[1.75rem]">{title}</h1>
          {subtitle && <p className="text-sm leading-relaxed text-muted-foreground">{subtitle}</p>}
        </header>

        <div className="mt-7">{children}</div>

        {footer && (
          <div className="mt-7 border-t border-border pt-5 text-center text-sm text-muted-foreground">
            {footer}
          </div>
        )}
      </div>
    </div>
  );
}