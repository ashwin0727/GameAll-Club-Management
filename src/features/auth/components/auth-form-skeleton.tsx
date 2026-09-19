import { Skeleton } from "@/components/ui/skeleton";

/** One label+input pair, sized to match TextField/PasswordInput's h-11 control. */
function AuthFieldSkeleton() {
  return (
    <div className="space-y-2">
      <Skeleton className="h-3.5 w-24" />
      <Skeleton className="h-11 w-full rounded-lg" />
    </div>
  );
}

/**
 * Placeholder for an auth form's fields + submit button — used inside
 * per-route loading.tsx files (login/signup) so the AuthCard chrome (brand
 * mark, real heading, footer link) renders immediately and only the dynamic
 * form area shows a skeleton, avoiding layout shift once the real form mounts.
 */
export function AuthFormSkeleton({ fields }: { fields: number }) {
  return (
    <div className="space-y-5">
      {Array.from({ length: fields }).map((_, i) => (
        <AuthFieldSkeleton key={i} />
      ))}
      <Skeleton className="h-11 w-full rounded-lg" />
    </div>
  );
}

export function AuthFooterLinkSkeleton() {
  return <Skeleton className="mx-auto h-4 w-48" />;
}
