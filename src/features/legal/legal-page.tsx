import Link from "next/link";
import { BrandMark } from "@/features/auth/components/brand-mark";
import { APP_NAME } from "@/lib/constants";

/** How people reach us about their data. NEXT_PUBLIC_SUPPORT_EMAIL can override the email. */
export const LEGAL_CONTACT_EMAIL = process.env.NEXT_PUBLIC_SUPPORT_EMAIL || "admin@gameall.co";
export const LEGAL_CONTACT_PHONE = "9360428761";
export const LEGAL_WEBSITE = "gameall.co";
export const LEGAL_UPDATED = "28 October 2026";

export interface LegalSection {
  title: string;
  body: React.ReactNode;
}

/** Shared frame for the public Privacy Policy, Terms of Service and account-deletion pages. */
export function LegalPage({ title, intro, sections }: { title: string; intro: React.ReactNode; sections: LegalSection[] }) {
  return (
    <div className="min-h-[100dvh] bg-background">
      <header className="border-b border-border">
        <div className="mx-auto flex max-w-3xl items-center justify-between px-5 py-4 sm:px-8">
          <Link href="/" aria-label={APP_NAME}>
            <BrandMark />
          </Link>
          <nav className="flex gap-4 text-sm text-muted-foreground">
            <Link href="/privacy" className="hover:text-foreground">
              Privacy
            </Link>
            <Link href="/terms" className="hover:text-foreground">
              Terms
            </Link>
          </nav>
        </div>
      </header>
      <main className="mx-auto max-w-3xl px-5 py-10 sm:px-8">
        <h1 className="text-3xl font-semibold tracking-tight">{title}</h1>
        <p className="mt-2 text-sm text-muted-foreground">Last updated {LEGAL_UPDATED}</p>
        <div className="mt-6 space-y-3 text-[15px] leading-relaxed text-foreground/90">{intro}</div>
        <div className="mt-8 space-y-8">
          {sections.map((s, i) => (
            <section key={s.title}>
              <h2 className="text-lg font-semibold">
                {i + 1}. {s.title}
              </h2>
              <div className="mt-2 space-y-3 text-[15px] leading-relaxed text-foreground/90">{s.body}</div>
            </section>
          ))}
        </div>
      </main>
    </div>
  );
}
