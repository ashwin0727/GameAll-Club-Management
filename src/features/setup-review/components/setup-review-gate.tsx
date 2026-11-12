"use client";

import * as React from "react";
import Image from "next/image";
import Link from "next/link";
import { useMutation, useQuery } from "@tanstack/react-query";
import { ArrowRight, BadgeCheck, Check, ChevronRight, CircleHelp, Clock, Headset, Info, Loader2, LogOut, Rocket, ShieldAlert, UserRoundCheck } from "lucide-react";
import { useLogout } from "@/features/auth/hooks/use-auth";
import { LEGAL_CONTACT_EMAIL } from "@/features/legal/legal-page";
import { setupFontClass } from "@/features/onboarding/components/onboarding-shell";
import { fetchMyReview, resubmitForReview, type ReviewStatus } from "@/features/setup-review/api";
import { cn } from "@/lib/utils";

const STEPS = ["Facility Information", "Sports & Courts", "Operating Hours", "Pricing", "Payout"] as const;

const NEXT = [
  { icon: UserRoundCheck, title: "Review by Our Team", text: "We'll verify your facility details, pricing, and payout information." },
  { icon: BadgeCheck, title: "Get Approved", text: "You'll receive a notification once your setup is approved." },
  { icon: Rocket, title: "Start Using GameAll", text: "After approval, you can access your facility dashboard and start managing your bookings, memberships, and more." },
] as const;

/** The clipboard-with-magnifier picture: the setup is being looked at. */
export function ReviewIllustration({ className }: { className?: string }) {
  return (
    <svg viewBox="0 0 360 250" className={cn("mx-auto h-[190px] w-auto sm:h-[230px]", className)} role="img" aria-label="A checklist being reviewed">
      <ellipse cx="120" cy="170" rx="72" ry="52" fill="#EFE7FF" />
      <ellipse cx="285" cy="110" rx="62" ry="58" fill="#F1EBFF" />
      <rect x="120" y="36" width="150" height="188" rx="14" fill="#F8F4FF" stroke="#6D3FE0" strokeWidth="6" />
      <rect x="168" y="22" width="54" height="26" rx="8" fill="#6D3FE0" />
      <circle cx="195" cy="30" r="5" fill="#F1EBFF" />
      {[78, 118, 158].map((y, i) => (
        <g key={y}>
          <rect x="142" y={y} width="24" height="24" rx="5" fill="#fff" stroke="#8C6AE8" strokeWidth="3" />
          {i < 2 && <path d={`M147 ${y + 12} l6 6 l11 -13`} fill="none" stroke="#4817C2" strokeWidth="4" strokeLinecap="round" strokeLinejoin="round" />}
          <rect x="178" y={y + 2} width="70" height="7" rx="3.5" fill="#C9B8F5" />
          <rect x="178" y={y + 15} width="48" height="7" rx="3.5" fill="#DDD1FA" />
        </g>
      ))}
      <circle cx="238" cy="150" r="38" fill="#F1EBFF" fillOpacity=".85" stroke="#5B2BD0" strokeWidth="9" />
      <path d="M266 180 L296 212" stroke="#5B2BD0" strokeWidth="12" strokeLinecap="round" />
      <path d="M72 58 l16 8 M96 38 l6 16 M76 84 l16 -2" stroke="#F5A33A" strokeWidth="4" strokeLinecap="round" />
    </svg>
  );
}

/**
 * The only thing a facility's people see until GameAll's admin has approved the setup: "Under Review" (it polls for the decision) or
 * "Changes needed" (the admin's note, with a way to fix things and send it back). Rendered by the dashboard layout, so no dashboard
 * page is reachable while the status is anything but APPROVED.
 */
export function SetupReviewGate({
  facilityId,
  facilityName,
  initialStatus,
  initialNote,
  isOwner,
}: {
  facilityId: string;
  facilityName: string;
  initialStatus: ReviewStatus;
  initialNote: string | null;
  isOwner: boolean;
}) {
  const logout = useLogout();
  const review = useQuery({
    queryKey: ["setup-review", facilityId],
    queryFn: () => fetchMyReview(facilityId),
    refetchInterval: 30_000,
    refetchOnWindowFocus: true,
  });
  const status = review.data?.status ?? initialStatus;
  const note = review.data ? review.data.note : initialNote;

  const resubmit = useMutation({
    mutationFn: () => resubmitForReview(facilityId),
    onSuccess: () => review.refetch(),
  });

  const rejected = status === "REJECTED";
  const approved = status === "APPROVED";
  const support = `mailto:${LEGAL_CONTACT_EMAIL}?subject=${encodeURIComponent(`Facility setup review - ${facilityName}`)}`;

  return (
    <div
      className={cn(setupFontClass, "relative flex min-h-[100dvh] flex-col overflow-hidden bg-gradient-to-b from-white via-[#FBF9FF] to-[#F3ECFF] text-[#171717]")}
      style={{ colorScheme: "light" }}
    >
      {/* soft corner shapes */}
      <div aria-hidden="true" className="pointer-events-none absolute -left-24 top-10 h-72 w-72 rounded-full bg-[#E9DFFF]/60 blur-3xl" />
      <div aria-hidden="true" className="pointer-events-none absolute -bottom-24 -right-16 h-80 w-80 rounded-full bg-[#E3D5FF]/70 blur-3xl" />

      <header className="relative z-10 flex h-16 shrink-0 items-center justify-between border-b border-[#E5E1EF] bg-white/90 px-4 backdrop-blur sm:h-[72px] sm:px-8">
        <div className="flex items-center gap-4">
          <Image src="/brand/gameall-logo-light-mode.svg" alt="GameAll" width={960} height={218} unoptimized priority className="h-9 w-auto sm:h-10" />
          <span aria-hidden="true" className="hidden h-8 w-px bg-[#E5E1EF] sm:block" />
          <span className="hidden text-lg font-semibold text-[#2A1070] sm:block">Facility Setup</span>
        </div>
        <div className="flex items-center gap-5">
          <a href={support} className="flex items-center gap-2 text-sm font-medium hover:text-[#4817C2]">
            <CircleHelp className="h-5 w-5" aria-hidden="true" />
            Need Help?
          </a>
          <button
            type="button"
            onClick={() => logout.mutate()}
            disabled={logout.isPending}
            className="flex items-center gap-1.5 text-sm font-medium text-[#666666] hover:text-[#171717] disabled:opacity-60"
          >
            <LogOut className="h-4 w-4" aria-hidden="true" />
            <span className="hidden sm:inline">Sign out</span>
          </button>
        </div>
      </header>

      <main className="relative z-10 mx-auto flex w-full max-w-[1180px] flex-1 flex-col items-center px-4 pb-10 pt-6 text-center sm:px-6 sm:pt-8">
        {rejected ? (
          <span className="flex h-24 w-24 items-center justify-center rounded-full bg-[#FDECEC] text-[#C62828]">
            <ShieldAlert className="h-11 w-11" aria-hidden="true" />
          </span>
        ) : (
          <ReviewIllustration />
        )}

        <h1 className="mt-4 text-3xl font-bold tracking-tight text-[#1B0B4B] sm:text-[40px] sm:leading-tight">
          {approved ? (
            <>
              You&apos;re <span className="text-[#5B1FE8]">Approved</span>
            </>
          ) : rejected ? (
            <>
              Your Facility Setup <span className="text-[#C62828]">Needs Changes</span>
            </>
          ) : (
            <>
              Your Facility Setup is <span className="text-[#5B1FE8]">Under Review</span>
            </>
          )}
        </h1>
        <p className="mt-3 max-w-[760px] text-base font-normal text-[#2B2B2B] sm:text-xl sm:leading-snug">
          {approved
            ? "Opening your dashboard…"
            : rejected
              ? `Our team reviewed ${facilityName} and needs something fixed before it can go live.`
              : "Thank you for completing your facility setup. Our team is currently reviewing your details and documents."}
        </p>

        {approved && (
          <Link href="/dashboard" className="mt-6 inline-flex h-12 items-center gap-2 rounded-lg bg-[#4817C2] px-7 text-sm font-semibold text-white hover:bg-[#39109F]">
            Go to Dashboard <ArrowRight className="h-4 w-4" aria-hidden="true" />
          </Link>
        )}

        {rejected ? (
          <div role="alert" className="mt-6 w-full max-w-[760px] rounded-2xl border border-[#F3C9C9] bg-[#FDF3F3] p-5 text-left">
            <p className="text-sm font-semibold text-[#C62828]">What to fix</p>
            <p className="mt-1.5 whitespace-pre-line text-[15px]">{note || "Please review your setup and send it again."}</p>
            {isOwner && (
              <div className="mt-4 flex flex-wrap gap-3">
                <Link href="/dashboard" className="flex h-11 items-center rounded-lg border border-[#E5E1EF] bg-white px-5 text-sm font-semibold hover:bg-[#FBFAFE]">
                  Go to Dashboard
                </Link>
                <Link href="/onboarding/facility" className="flex h-11 items-center rounded-lg border border-[#E5E1EF] bg-white px-5 text-sm font-semibold hover:bg-[#FBFAFE]">
                  Edit my setup
                </Link>
                <button
                  type="button"
                  onClick={() => resubmit.mutate()}
                  disabled={resubmit.isPending}
                  className="flex h-11 items-center gap-2 rounded-lg bg-[#4817C2] px-5 text-sm font-semibold text-white hover:bg-[#39109F] disabled:opacity-70"
                >
                  {resubmit.isPending && <Loader2 className="h-4 w-4 animate-spin" aria-hidden="true" />}
                  Send for review again
                </button>
              </div>
            )}
            {resubmit.error && <p className="mt-3 text-sm text-[#C62828]">{resubmit.error instanceof Error ? resubmit.error.message : "Something went wrong."}</p>}
          </div>
        ) : (
          !approved && (
            <>
            <p className="mt-5 inline-flex items-center gap-3 rounded-full bg-[#EFE8FF] px-6 py-3 text-base font-medium text-[#2A1070] sm:text-lg">
              <Clock className="h-6 w-6 shrink-0 text-[#5B1FE8]" aria-hidden="true" />
              <span>
                Approval usually takes up to <strong className="font-bold text-[#5B1FE8]">24 hours.</strong>
              </span>
            </p>
            <Link href="/dashboard" className="mt-4 inline-flex h-12 items-center gap-2 rounded-lg bg-[#4817C2] px-7 text-sm font-semibold text-white hover:bg-[#39109F]">
              Go to Dashboard <ArrowRight className="h-4 w-4" aria-hidden="true" />
            </Link>
            </>
          )
        )}

        {/* the five finished steps, edge to edge */}
        <ol aria-label="Completed setup steps" className="mt-7 flex w-full flex-wrap items-center justify-between gap-x-4 gap-y-3 rounded-2xl border border-[#BFE5C6] bg-[#F1FAF3] px-5 py-4 text-left sm:px-8">
          {STEPS.map((s, i) => (
            <li key={s} className="flex flex-1 items-center gap-3 sm:min-w-0">
              <span className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-[#2E9D4F] text-white">
                <Check className="h-4 w-4" strokeWidth={3} aria-hidden="true" />
              </span>
              <span className="text-sm font-medium leading-tight sm:text-[15px]">{s}</span>
              {i < STEPS.length - 1 && <span aria-hidden="true" className="ml-auto hidden h-px min-w-6 flex-1 bg-[#BFE5C6] lg:block" />}
            </li>
          ))}
        </ol>

        <section className="mt-8 w-full text-left" aria-labelledby="whats-next">
          <h2 id="whats-next" className="text-2xl font-bold tracking-tight">
            What&apos;s Next?
          </h2>
          <ul className="mt-4 grid items-stretch gap-3 md:grid-cols-[1fr_auto_1fr_auto_1.15fr]">
            {NEXT.map((n, i) => (
              <React.Fragment key={n.title}>
                <li className="flex items-start gap-4 rounded-xl bg-[#F1EBFF]/80 px-5 py-5">
                  <n.icon className="mt-0.5 h-10 w-10 shrink-0 text-[#4817C2]" strokeWidth={1.5} aria-hidden="true" />
                  <div>
                    <h3 className="text-lg font-semibold leading-tight">{n.title}</h3>
                    <p className="mt-1.5 text-[15px] font-normal leading-snug text-[#444]">{n.text}</p>
                  </div>
                </li>
                {i < NEXT.length - 1 && (
                  <li aria-hidden="true" className="hidden items-center md:flex">
                    <span className="flex h-9 w-9 items-center justify-center rounded-full bg-[#EFE8FF] text-[#171717]">
                      <ChevronRight className="h-5 w-5" />
                    </span>
                  </li>
                )}
              </React.Fragment>
            ))}
          </ul>
        </section>

        <p className="mt-7 flex w-full max-w-[730px] items-center justify-center gap-3 rounded-full bg-[#EFE8FF] px-5 py-3 text-sm font-medium text-[#2A1070] sm:text-base">
          <Info className="h-5 w-5 shrink-0" aria-hidden="true" />
          You&apos;ll receive an email and in-app notification once your facility is approved.
        </p>

        <a
          href={support}
          className="mt-6 inline-flex h-12 items-center gap-2.5 rounded-full border border-[#5B1FE8] bg-white/80 px-8 text-base font-semibold text-[#4817C2] hover:bg-[#F1EBFF] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#4817C2]"
        >
          <Headset className="h-5 w-5" aria-hidden="true" />
          Need Help? Contact Support
        </a>
      </main>
    </div>
  );
}
