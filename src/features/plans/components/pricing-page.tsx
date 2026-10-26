"use client";

import { useState } from "react";
import Link from "next/link";
import { ArrowRight, Check, ChevronDown, Minus, ShieldCheck } from "lucide-react";
import { BrandMark } from "@/features/auth/components/brand-mark";
import { PLAN_BLURB, PRICES, PRICING_MODULES, type PricingLine } from "@/features/plans/pricing-content";
import { formatRupees } from "@/features/plans/plans";
import type { BillingInterval } from "@/features/plans/types";
import { APP_NAME } from "@/lib/constants";
import { cn } from "@/lib/utils";

type PlanKey = "basic" | "advanced";

const PLANS: { key: PlanKey; name: string; tagline: string; popular: boolean }[] = [
  { key: "basic", name: "Basic", tagline: "For clubs getting started", popular: false },
  { key: "advanced", name: "Advanced", tagline: "For clubs that want it all on autopilot", popular: true },
];

/** Comparison-table sections, in order. */
const GROUPS: { title: string; keys: string[] }[] = [
  { title: "Run the club", keys: ["home", "calendar", "guest-booking", "guest-players", "tournaments"] },
  { title: "Player App", keys: ["player-app"] },
  { title: "Members & coaching", keys: ["memberships", "coaching"] },
  { title: "Operations", keys: ["maintenance", "staff"] },
  { title: "Money & insight", keys: ["finance", "reports", "payouts"] },
];

/** Where a plain tick would hide a real difference, the table says it in words. */
const TABLE_TEXT: Record<string, Record<PlanKey, string>> = {
  "player-app": { basic: "Guest booking only", advanced: "Guest booking + memberships" },
  memberships: { basic: "Manual payments", advanced: "Automatic payments" },
  coaching: { basic: "Manual · no schedule", advanced: "Automatic · with schedule" },
  payouts: { basic: "Next working day", advanced: "Within 5 minutes" },
};

const FAQS: { q: string; a: string }[] = [
  {
    q: "What can players do in the Player App?",
    a: "On both plans your club is visible to players, who can book guest slots. On Advanced, players can also enrol in your memberships themselves, right from the app.",
  },
  {
    q: "How does the free trial work?",
    a: "Pick a plan and use every feature in it free for 90 days. If the trial ends and you have not paid, your club stays on Basic features and nothing is deleted.",
  },
  {
    q: "Can I switch between Basic and Advanced?",
    a: "Yes, any time from the Plans page. Moving up unlocks the extra pages straight away. Your data stays exactly where it is when you switch.",
  },
  {
    q: "Do you take a commission on my bookings?",
    a: "No. You pay one flat fee for the plan. Standard payment-gateway charges apply to online payments, as they do with any gateway.",
  },
  {
    q: "What is the difference between manual and automatic payment tracking?",
    a: "On Basic you record each membership or coaching payment yourself. On Advanced, members pay through Auto Pay, and every cycle is collected and marked paid for you.",
  },
  {
    q: "What if I have more than one court or a bigger team?",
    a: "Both plans work for multi-court clubs. Advanced adds Staff Management, so you can give each team member their own login and decide page by page what they can see.",
  },
];

function Toggle({ interval, onChange }: { interval: BillingInterval; onChange: (i: BillingInterval) => void }) {
  return (
    <div role="group" aria-label="Billing period" className="inline-flex items-center rounded-full border border-border bg-muted/60 p-1 text-sm">
      {(["month", "year"] as const).map((i) => (
        <button
          key={i}
          type="button"
          aria-pressed={interval === i}
          onClick={() => onChange(i)}
          className={cn(
            "flex items-center gap-2 rounded-full px-5 py-2 font-medium transition-all",
            interval === i ? "bg-background text-foreground shadow-sm" : "text-muted-foreground hover:text-foreground",
          )}
        >
          {i === "month" ? "Monthly" : "Yearly"}
          {i === "year" && (
            <span className="rounded-full bg-primary/10 px-2 py-0.5 text-[11px] font-semibold text-primary">Save 16%</span>
          )}
        </button>
      ))}
    </div>
  );
}

function Feature({ line, upgrade = false }: { line: PricingLine; upgrade?: boolean }) {
  return (
    <li className="flex gap-3">
      <Check className="mt-0.5 h-4 w-4 shrink-0 text-primary" aria-hidden />
      <div className="min-w-0">
        <p className="text-sm font-medium leading-snug text-foreground">{line.title}</p>
        {line.sub && <p className="mt-0.5 text-xs text-muted-foreground">{line.sub}</p>}
        {upgrade && <p className="mt-0.5 text-xs font-medium text-primary">Upgraded from Basic</p>}
      </div>
    </li>
  );
}

function PlanCard({ plan, interval }: { plan: (typeof PLANS)[number]; interval: BillingInterval }) {
  const price = PRICES[plan.key][interval];
  const yearly = PRICES[plan.key].year;
  const fullYear = PRICES[plan.key].month * 12;

  // Advanced lists only what Basic does not already have: new pages, and the pages that get upgraded.
  const rows = PRICING_MODULES.flatMap((m) => {
    const line = m[plan.key];
    if (!line) return [];
    if (plan.key === "basic") return [{ key: m.key, line, upgrade: false }];
    if (m.basic === m.advanced) return [];
    return [{ key: m.key, line, upgrade: m.basic !== null }];
  });

  return (
    <section
      className={cn(
        "relative flex flex-col overflow-hidden rounded-3xl border bg-card",
        plan.popular ? "border-primary shadow-[0_20px_60px_-20px_hsl(var(--primary)/0.35)] ring-4 ring-primary/10" : "border-border",
      )}
    >
      <div className={cn("px-7 pb-7 pt-8 sm:px-9", plan.popular ? "bg-primary/[0.08]" : "bg-muted/50")}>
        <div className="flex items-start justify-between gap-3">
          <div>
            <h2 className="text-2xl font-semibold tracking-tight">{plan.name}</h2>
            <p className="mt-0.5 text-sm font-medium text-primary">{plan.tagline}</p>
          </div>
          {interval === "year" && (
            <span className="shrink-0 rounded-full bg-primary px-3.5 py-1.5 text-sm text-primary-foreground">
              Save <strong className="font-semibold">16%</strong>
            </span>
          )}
        </div>
        <p className="mt-4 text-[15px] leading-relaxed text-foreground/80">{PLAN_BLURB[plan.key]}</p>

        <div className="mt-5 flex flex-wrap items-baseline gap-x-2 gap-y-1">
          {interval === "year" && (
            <span className="text-xl font-semibold text-destructive line-through">{formatRupees(fullYear * 100)}</span>
          )}
          <span className="text-4xl font-semibold tracking-tight">{formatRupees(price * 100)}</span>
          <span className="text-sm text-muted-foreground">/ {interval}</span>
        </div>
        <p className="mt-1.5 text-xs italic text-muted-foreground">
          {interval === "year"
            ? `Just ${formatRupees(Math.round(yearly / 12) * 100)} a month, billed yearly`
            : "Billed monthly. Switch to yearly and save 16%"}
        </p>

        <Link
          href="/signup"
          className={cn(
            "group mt-6 inline-flex h-12 w-full items-center justify-center gap-2 rounded-xl px-5 text-sm font-semibold transition-all",
            plan.popular
              ? "bg-primary text-primary-foreground shadow-sm hover:bg-primary/90"
              : "border border-border bg-background hover:border-primary/50 hover:bg-secondary",
          )}
        >
          Start 90-day free trial
          <ArrowRight className="h-4 w-4 transition-transform group-hover:translate-x-0.5" aria-hidden />
        </Link>
      </div>

      <div className="flex-1 px-7 pb-8 pt-6 sm:px-9">
        <p className="mb-4 text-[15px] font-semibold">{plan.popular ? "Everything in Basic, plus:" : "What you get:"}</p>
        <ul className="space-y-3.5">
          {rows.map((r) => (
            <Feature key={r.key} line={r.line} upgrade={r.upgrade} />
          ))}
        </ul>
      </div>
    </section>
  );
}

function Cell({ moduleKey, plan }: { moduleKey: string; plan: PlanKey }) {
  const mod = PRICING_MODULES.find((m) => m.key === moduleKey)!;
  if (!mod[plan]) return <Minus className="mx-auto h-4 w-4 text-muted-foreground/50" aria-label="Not included" />;
  const text = TABLE_TEXT[moduleKey]?.[plan];
  return text ? (
    <span className="text-[13px] font-medium text-foreground">{text}</span>
  ) : (
    <Check className="mx-auto h-4 w-4 text-primary" aria-label="Included" />
  );
}

/** Public pricing page (/pricing): two plans, what each includes, a grouped comparison and the common questions. */
export function PricingPage() {
  const [interval, setInterval] = useState<BillingInterval>("year");

  return (
    <div className="min-h-[100dvh] bg-background">
      <header className="sticky top-0 z-20 border-b border-border/70 bg-background/85 backdrop-blur">
        <div className="mx-auto flex max-w-[1120px] items-center justify-between px-5 py-3.5 sm:px-8">
          <Link href="/" aria-label={APP_NAME}>
            <BrandMark />
          </Link>
          <nav className="flex items-center gap-5 text-sm">
            <Link href="/login" className="font-medium text-muted-foreground transition-colors hover:text-foreground">
              Log in
            </Link>
            <Link
              href="/signup"
              className="rounded-lg bg-primary px-3.5 py-1.5 font-medium text-primary-foreground transition-colors hover:bg-primary/90"
            >
              Get started
            </Link>
          </nav>
        </div>
      </header>

      <main>
        <section className="relative overflow-hidden">
          <div
            aria-hidden
            className="pointer-events-none absolute inset-x-0 top-0 h-[420px] bg-[radial-gradient(60%_80%_at_50%_0%,hsl(var(--primary)/0.10),transparent)]"
          />
          <div className="relative mx-auto max-w-[1120px] px-5 pb-2 pt-8 text-center sm:px-8 sm:pt-10">
            <p className="mx-auto inline-flex items-center gap-1.5 rounded-full border border-primary/20 bg-primary/5 px-3 py-1 text-xs font-medium text-primary">
              <ShieldCheck className="h-3.5 w-3.5" aria-hidden /> Flat fee · No commission on bookings
            </p>
            <h1 className="mx-auto mt-4 max-w-3xl text-balance text-4xl font-semibold tracking-tight sm:text-5xl">
              One simple plan to run your whole club
            </h1>
            <p className="mx-auto mt-4 max-w-xl text-base leading-relaxed text-muted-foreground sm:text-lg">
              Bookings, memberships, coaching, tournaments and finance in one place. Pick a plan, try it free for 90 days.
            </p>
            <div className="mt-6 flex justify-center">
              <Toggle interval={interval} onChange={setInterval} />
            </div>
          </div>
        </section>

        <section className="mx-auto max-w-[1120px] px-5 pb-6 pt-8 sm:px-8">
          <div className="grid gap-8 lg:grid-cols-2 lg:items-start">
            {PLANS.map((plan) => (
              <PlanCard key={plan.key} plan={plan} interval={interval} />
            ))}
          </div>
        </section>

        <section className="mx-auto max-w-[1120px] px-5 py-16 sm:px-8">
          <div className="mx-auto max-w-2xl text-center">
            <h2 className="text-2xl font-semibold tracking-tight sm:text-3xl">Compare the plans</h2>
            <p className="mt-2 text-muted-foreground">Every page in the app, and which plan it comes with.</p>
          </div>

          <div className="mt-8 overflow-hidden rounded-2xl border border-border bg-card">
            <div className="overflow-x-auto">
              <table className="w-full min-w-[560px] text-sm">
                <thead>
                  <tr className="border-b border-border bg-muted/40 text-left">
                    <th className="px-5 py-4 font-medium text-muted-foreground">Feature</th>
                    <th className="w-44 px-4 py-4 text-center">
                      <span className="block font-semibold">Basic</span>
                      <span className="text-xs font-normal text-muted-foreground">{formatRupees(PRICES.basic[interval] * 100)} / {interval}</span>
                    </th>
                    <th className="w-44 bg-primary/[0.06] px-4 py-4 text-center">
                      <span className="block font-semibold text-primary">Advanced</span>
                      <span className="text-xs font-normal text-muted-foreground">{formatRupees(PRICES.advanced[interval] * 100)} / {interval}</span>
                    </th>
                  </tr>
                </thead>
                <tbody>
                  {GROUPS.map((g) => (
                    <GroupRows key={g.title} title={g.title} keys={g.keys} />
                  ))}
                </tbody>
              </table>
            </div>
          </div>
        </section>

        <section className="mx-auto max-w-3xl px-5 pb-16 sm:px-8">
          <h2 className="text-center text-2xl font-semibold tracking-tight sm:text-3xl">Questions, answered</h2>
          <div className="mt-8 divide-y divide-border rounded-2xl border border-border bg-card">
            {FAQS.map((f) => (
              <details key={f.q} className="group px-6 py-5 [&_summary::-webkit-details-marker]:hidden">
                <summary className="flex cursor-pointer list-none items-center justify-between gap-4 text-sm font-semibold sm:text-base">
                  {f.q}
                  <ChevronDown className="h-4 w-4 shrink-0 text-muted-foreground transition-transform group-open:rotate-180" aria-hidden />
                </summary>
                <p className="mt-3 text-sm leading-relaxed text-muted-foreground">{f.a}</p>
              </details>
            ))}
          </div>
        </section>

        <section className="mx-auto max-w-[1120px] px-5 pb-20 sm:px-8">
          <div className="rounded-3xl border border-primary/20 bg-gradient-to-br from-primary/10 via-primary/[0.04] to-transparent px-6 py-12 text-center sm:px-12">
            <h2 className="text-2xl font-semibold tracking-tight sm:text-3xl">Ready to run your club the easy way?</h2>
            <p className="mx-auto mt-2 max-w-lg text-muted-foreground">Set up in minutes. Your first 90 days are free.</p>
            <Link
              href="/signup"
              className="group mt-6 inline-flex h-12 items-center gap-2 rounded-xl bg-primary px-6 text-sm font-semibold text-primary-foreground shadow-sm transition-colors hover:bg-primary/90"
            >
              Start free trial
              <ArrowRight className="h-4 w-4 transition-transform group-hover:translate-x-0.5" aria-hidden />
            </Link>
          </div>
        </section>
      </main>
    </div>
  );
}

function GroupRows({ title, keys }: { title: string; keys: string[] }) {
  return (
    <>
      <tr className="border-b border-border bg-muted/20">
        <th colSpan={3} className="px-5 py-2.5 text-left text-xs font-semibold uppercase tracking-wider text-muted-foreground">
          {title}
        </th>
      </tr>
      {keys.map((k) => {
        const m = PRICING_MODULES.find((x) => x.key === k)!;
        return (
          <tr key={k} className="border-b border-border last:border-b-0">
            <td className="px-5 py-3.5">
              <p className="font-medium">{m.label}</p>
              <p className="mt-0.5 max-w-md text-xs leading-relaxed text-muted-foreground">{(m.advanced ?? m.basic)!.description}</p>
            </td>
            <td className="px-4 py-3.5 text-center">
              <Cell moduleKey={k} plan="basic" />
            </td>
            <td className="bg-primary/[0.06] px-4 py-3.5 text-center">
              <Cell moduleKey={k} plan="advanced" />
            </td>
          </tr>
        );
      })}
    </>
  );
}
