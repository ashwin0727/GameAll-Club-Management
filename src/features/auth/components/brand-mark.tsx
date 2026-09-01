import Image from "next/image";
import { cn } from "@/lib/utils";
import { APP_LOGO_SRC, APP_NAME, APP_SUBTITLE } from "@/lib/constants";

/**
 * The GameAll logo. A transparent PNG, so it sits correctly on both the light
 * and dark surfaces without a per-theme variant.
 */
export function BrandLogo({ className }: { className?: string }) {
  return (
    <Image
      src={APP_LOGO_SRC}
      alt=""
      aria-hidden="true"
      width={512}
      height={512}
      priority
      className={cn("h-10 w-10 object-contain", className)}
    />
  );
}

/** Logo + "GameAll" over "Club Management" — the full brand lockup. */
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
      <span className="flex flex-col leading-tight">
        <span
          className={cn(
            "font-semibold tracking-tight text-foreground",
            size === "lg" ? "text-2xl" : "text-lg",
          )}
        >
          {APP_NAME}
        </span>
        <span className={cn("text-muted-foreground", size === "lg" ? "text-sm" : "text-xs")}>
          {APP_SUBTITLE}
        </span>
      </span>
    </div>
  );
}
