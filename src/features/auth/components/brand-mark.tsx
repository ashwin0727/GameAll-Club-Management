import { cn } from "@/lib/utils";
import { PRODUCT_NAME } from "@/lib/constants";

/**
 * The product logo: a court outline with a centre line and serve dot. Drawn as
 * inline SVG so it inherits `currentColor` and needs no asset request on the
 * splash screen's critical path.
 */
export function BrandLogo({ className }: { className?: string }) {
  return (
    <svg
      viewBox="0 0 40 40"
      role="img"
      aria-hidden="true"
      className={cn("h-10 w-10", className)}
      fill="none"
      strokeLinecap="round"
      strokeLinejoin="round"
    >
      <rect
        x="3.5"
        y="3.5"
        width="33"
        height="33"
        rx="9"
        className="fill-primary/10 stroke-primary"
        strokeWidth="2"
      />
      <path d="M20 8v24" className="stroke-primary" strokeWidth="2" />
      <path d="M9 20h22" className="stroke-primary/50" strokeWidth="2" />
      <circle cx="20" cy="20" r="3.5" className="fill-primary" />
    </svg>
  );
}

export function BrandMark({
  className,
  size = "default",
}: {
  className?: string;
  size?: "default" | "lg";
}) {
  return (
    <div className={cn("flex items-center gap-3", className)}>
      <BrandLogo className={size === "lg" ? "h-12 w-12" : "h-9 w-9"} />
      <span
        className={cn(
          "font-semibold tracking-tight text-foreground",
          size === "lg" ? "text-2xl" : "text-lg",
        )}
      >
        {PRODUCT_NAME}
      </span>
    </div>
  );
}