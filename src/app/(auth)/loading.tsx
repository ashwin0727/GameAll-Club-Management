import { Skeleton } from "@/components/ui/skeleton";

/**
 * Generic fallback for auth routes without their own loading.tsx (forgot
 * password, reset password, verify email, welcome). Login and Signup get a
 * more precise skeleton in their own route folders; this one just needs to
 * roughly match AuthCard's proportions instead of showing a spinner.
 */
export default function AuthLoading() {
  return (
    <div className="mx-auto w-full max-w-[460px]">
      <Skeleton className="mb-8 h-8 w-32 sm:mb-10" />
      <div className="space-y-2">
        <Skeleton className="h-7 w-2/3" />
        <Skeleton className="h-4 w-full" />
      </div>
      <div className="mt-7 space-y-5">
        <Skeleton className="h-11 w-full rounded-lg" />
        <Skeleton className="h-11 w-full rounded-lg" />
      </div>
    </div>
  );
}
