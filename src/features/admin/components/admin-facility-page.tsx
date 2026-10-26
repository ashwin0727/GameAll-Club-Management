"use client";

import Link from "next/link";
import { Skeleton } from "@/components/ui/skeleton";
import { ErrorNote, PageTitle, Stat } from "@/features/admin/components/admin-shell";
import { VerificationBadge } from "@/features/admin/components/verification-badge";
import { formatDate, humanize, inr } from "@/features/admin/format";
import { useAdminFacility } from "@/features/admin/hooks";

function Section({ title, action, children }: { title: string; action?: React.ReactNode; children: React.ReactNode }) {
  return (
    <section className="rounded-xl border border-border bg-card">
      <div className="flex items-center justify-between gap-3 border-b border-border px-5 py-3.5">
        <h2 className="text-sm font-semibold">{title}</h2>
        {action}
      </div>
      <div className="p-5">{children}</div>
    </section>
  );
}

function Row({ label, value }: { label: string; value: React.ReactNode }) {
  return (
    <div className="flex justify-between gap-4 py-1.5 text-sm">
      <dt className="text-muted-foreground">{label}</dt>
      <dd className="text-right font-medium">{value}</dd>
    </div>
  );
}

/** One facility, everything: setup, sports and courts, memberships, coaching, payments, plan and payout details. */
export function AdminFacilityPage({ facilityId }: { facilityId: string }) {
  const { data, isLoading, error } = useAdminFacility(facilityId);

  if (error) return <ErrorNote error={error} />;
  if (isLoading || !data) return <Skeleton className="h-96 w-full rounded-xl" />;

  const { facility: f, owner, sports, courts, memberships: m, coaching: c, payments: p, plan, payoutMethods } = data;

  return (
    <div className="space-y-6">
      <PageTitle
        back={{ href: "/admin", label: "All facilities" }}
        title={f.name}
        subtitle={`${f.type ? humanize(f.type) + " · " : ""}Registered ${formatDate(f.createdAt)} · ${
          f.onboardingStep === "COMPLETED" ? "Setup complete" : `Setup in progress (${humanize(f.onboardingStep)})`
        }`}
      />

      <div className="grid grid-cols-2 gap-3 md:grid-cols-4">
        <Stat label="Sports" value={sports.filter((s) => s.active).length} />
        <Stat label="Courts" value={courts.length} />
        <Stat label="Active memberships" value={m.active} hint={`${m.members} members`} />
        <Stat label="Coaching students" value={c.activeStudents} hint={`${c.programs} programs`} />
      </div>

      <div className="grid gap-6 lg:grid-cols-2">
        <Section title="Owner and contact">
          <dl className="divide-y divide-border">
            <Row label="Owner" value={owner.name ?? "—"} />
            <Row label="Owner email" value={owner.email ?? "—"} />
            <Row label="Owner phone" value={owner.phone ?? "—"} />
            <Row label="Business email" value={f.businessEmail ?? "—"} />
            <Row label="Business phone" value={f.businessPhone ?? "—"} />
            <Row label="Address" value={f.address || "—"} />
          </dl>
        </Section>

        <Section title="GameAll plan">
          {plan ? (
            <dl className="divide-y divide-border">
              <Row label="Plan" value={plan.name} />
              <Row label="Status" value={humanize(plan.status)} />
              <Row label="Billing" value={`${inr(plan.priceMinor / 100)} / ${plan.interval}`} />
              <Row label="Valid till" value={formatDate(plan.validTill)} />
            </dl>
          ) : (
            <p className="text-sm text-muted-foreground">No plan chosen yet.</p>
          )}
        </Section>
      </div>

      <div className="grid gap-6 lg:grid-cols-2">
        <Section title={`Sports (${sports.length})`}>
          {sports.length === 0 ? (
            <p className="text-sm text-muted-foreground">No sports added.</p>
          ) : (
            <ul className="divide-y divide-border">
              {sports.map((s) => (
                <li key={s.name} className="flex items-center justify-between py-2 text-sm">
                  <span className="font-medium">{s.name}</span>
                  <span className="text-muted-foreground">
                    {s.courts} court{s.courts === 1 ? "" : "s"}
                    {s.active ? "" : " · inactive"}
                  </span>
                </li>
              ))}
            </ul>
          )}
        </Section>

        <Section title={`Courts (${courts.length})`}>
          {courts.length === 0 ? (
            <p className="text-sm text-muted-foreground">No courts added.</p>
          ) : (
            <ul className="divide-y divide-border">
              {courts.map((court, i) => (
                <li key={`${court.name}-${i}`} className="flex items-center justify-between gap-3 py-2 text-sm">
                  <span>
                    <span className="font-medium">{court.name}</span>
                    <span className="text-muted-foreground"> · {court.sport ?? "—"}</span>
                  </span>
                  <span className="text-muted-foreground">
                    {inr(court.hourlyRateInr)}/hr{court.status !== "ACTIVE" || !court.bookingEnabled ? " · not bookable" : ""}
                  </span>
                </li>
              ))}
            </ul>
          )}
        </Section>
      </div>

      <div className="grid gap-6 lg:grid-cols-2">
        <Section title="Memberships">
          <dl className="divide-y divide-border">
            <Row label="Plans on offer" value={m.plans} />
            <Row label="Active memberships" value={m.active} />
            <Row label="Pending memberships" value={m.pending} />
            <Row label="Members" value={m.members} />
            <Row label="Collected" value={inr(m.collectedInr)} />
          </dl>
        </Section>

        <Section title="Coaching">
          <dl className="divide-y divide-border">
            <Row label="Coaches" value={c.coaches} />
            <Row label="Programs" value={c.programs} />
            <Row label="Active students" value={c.activeStudents} />
            <Row label="Collected" value={inr(c.collectedInr)} />
          </dl>
        </Section>
      </div>

      <Section
        title="Payments"
        action={
          <Link href={`/admin/transactions/${f.id}`} className="text-sm font-medium text-primary hover:underline">
            View transactions
          </Link>
        }
      >
        <div className="grid gap-x-10 gap-y-1 md:grid-cols-2">
          <dl className="divide-y divide-border">
            <Row label="Online (Razorpay)" value={`${inr(p.onlineInr)} · ${p.onlineCount} payments`} />
            <Row label="Cash and other offline" value={`${inr(p.offlineInr)} · ${p.offlineCount} payments`} />
            <Row label="Refunded" value={inr(p.refundedInr)} />
          </dl>
          <dl className="divide-y divide-border">
            <Row label="Settled to the facility" value={inr(p.settledInr)} />
            <Row label="Waiting to be settled" value={<span className={p.unsettledInr > 0 ? "text-warning" : undefined}>{inr(p.unsettledInr)}</span>} />
          </dl>
        </div>
      </Section>

      <Section
        title="Payout details"
        action={
          <Link href={`/admin/payouts/${f.id}`} className="text-sm font-medium text-primary hover:underline">
            Review
          </Link>
        }
      >
        {payoutMethods.length === 0 ? (
          <p className="text-sm text-muted-foreground">No bank account or UPI ID added yet.</p>
        ) : (
          <ul className="divide-y divide-border">
            {payoutMethods.map((pm) => (
              <li key={pm.id} className="flex items-center justify-between py-2 text-sm">
                <span className="font-medium">
                  {pm.type === "BANK" ? "Bank account" : "UPI ID"}
                  {pm.primary && <span className="ml-2 text-xs font-normal text-muted-foreground">Primary</span>}
                </span>
                <VerificationBadge status={pm.verification} />
              </li>
            ))}
          </ul>
        )}
      </Section>
    </div>
  );
}
