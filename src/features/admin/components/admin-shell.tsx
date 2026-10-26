"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { Banknote, Building2, LogOut, ReceiptText } from "lucide-react";
import { Button } from "@/components/ui/button";
import { BrandMark } from "@/features/auth/components/brand-mark";
import { useLogout } from "@/features/auth/hooks/use-auth";
import { cn } from "@/lib/utils";

const NAV = [
  { href: "/admin", label: "Home", icon: Building2, match: (p: string) => p === "/admin" || p.startsWith("/admin/facilities") },
  { href: "/admin/payouts", label: "Payouts", icon: Banknote, match: (p: string) => p.startsWith("/admin/payouts") },
  { href: "/admin/transactions", label: "Transactions", icon: ReceiptText, match: (p: string) => p.startsWith("/admin/transactions") },
];

/** The platform admin's back office frame: brand, three sections, sign out. */
export function AdminShell({ email, children }: { email: string; children: React.ReactNode }) {
  const pathname = usePathname() ?? "";
  const logout = useLogout();

  return (
    <div className="min-h-[100dvh] bg-background">
      <header className="sticky top-0 z-20 border-b border-border bg-background/90 backdrop-blur">
        <div className="mx-auto flex max-w-[1200px] flex-wrap items-center justify-between gap-x-6 gap-y-2 px-4 py-3 sm:px-6">
          <div className="flex items-center gap-3">
            <BrandMark />
            <span className="rounded-full bg-primary/10 px-2.5 py-0.5 text-xs font-semibold text-primary">Admin</span>
          </div>
          <nav aria-label="Admin" className="order-3 flex w-full gap-1 sm:order-none sm:w-auto">
            {NAV.map((n) => {
              const active = n.match(pathname);
              return (
                <Link
                  key={n.href}
                  href={n.href}
                  aria-current={active ? "page" : undefined}
                  className={cn(
                    "flex flex-1 items-center justify-center gap-2 rounded-lg px-3.5 py-2 text-sm font-medium transition-colors sm:flex-none",
                    active ? "bg-primary text-primary-foreground" : "text-muted-foreground hover:bg-secondary hover:text-foreground",
                  )}
                >
                  <n.icon className="h-4 w-4" aria-hidden />
                  {n.label}
                </Link>
              );
            })}
          </nav>
          <div className="flex items-center gap-3">
            <span className="hidden text-sm text-muted-foreground md:inline">{email}</span>
            <Button variant="outline" size="sm" onClick={() => logout.mutate()} disabled={logout.isPending}>
              <LogOut className="mr-1.5 h-4 w-4" aria-hidden /> Sign out
            </Button>
          </div>
        </div>
      </header>
      <main className="mx-auto max-w-[1200px] px-4 py-8 sm:px-6">{children}</main>
    </div>
  );
}

export function PageTitle({ title, subtitle, back }: { title: string; subtitle?: string; back?: { href: string; label: string } }) {
  return (
    <div className="mb-6">
      {back && (
        <Link href={back.href} className="mb-2 inline-block text-sm text-muted-foreground hover:text-foreground">
          ← {back.label}
        </Link>
      )}
      <h1 className="text-2xl font-semibold tracking-tight">{title}</h1>
      {subtitle && <p className="mt-1 text-sm text-muted-foreground">{subtitle}</p>}
    </div>
  );
}

export function Stat({ label, value, hint }: { label: string; value: React.ReactNode; hint?: string }) {
  return (
    <div className="rounded-xl border border-border bg-card p-4">
      <p className="text-xs font-medium uppercase tracking-wide text-muted-foreground">{label}</p>
      <p className="mt-1.5 text-2xl font-semibold tracking-tight">{value}</p>
      {hint && <p className="mt-0.5 text-xs text-muted-foreground">{hint}</p>}
    </div>
  );
}

export function ErrorNote({ error }: { error: unknown }) {
  return (
    <div role="alert" className="rounded-lg border border-destructive/30 bg-destructive/5 px-4 py-3 text-sm text-destructive">
      {error instanceof Error ? error.message : "Something went wrong. Please try again."}
    </div>
  );
}
