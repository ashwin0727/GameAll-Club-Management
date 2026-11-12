import Image from "next/image";
import { cn } from "@/lib/utils";

/** The updated GameAll wordmark (light mode), used on the signed-out screens. */
export function BrandWordmark({ className }: { className?: string }) {
  return (
    <Image
      src="/brand/gameall-logo-light-mode.svg"
      alt="GameAll"
      width={960}
      height={218}
      unoptimized
      priority
      className={cn("h-9 w-auto sm:h-10", className)}
    />
  );
}

/** The full brand lockup. Kept as its own name so every screen that shows the brand follows the one wordmark. */
export function BrandMark({ className, size = "default" }: { className?: string; size?: "default" | "lg" }) {
  return <BrandWordmark className={cn(size === "lg" ? "h-11 sm:h-11" : "", className)} />;
}
