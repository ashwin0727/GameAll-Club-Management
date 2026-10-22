"use client";

import { useState } from "react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { ChevronDown, LifeBuoy, Mail, MessageSquareText, Phone, Send } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Skeleton } from "@/components/ui/skeleton";
import { Textarea } from "@/components/ui/textarea";
import { useFacility } from "@/features/facility/hooks/use-facility";
import { profileKeys, useSupportTickets } from "@/features/profile/hooks";
import { PageMessage, SectionCard, SubPageHeader } from "@/features/profile/components/profile-shared";
import { SUPPORT_CATEGORIES, supportTicketSchema } from "@/features/profile/support-validation";
import type { SupportCategory, SupportStatus } from "@/features/profile/types";
import { getProfileService } from "@/services/profile";

/** Set these in the environment to show your real contact details; with neither set, the card simply isn't shown. */
const SUPPORT_EMAIL = process.env.NEXT_PUBLIC_SUPPORT_EMAIL ?? "";
const SUPPORT_PHONE = process.env.NEXT_PUBLIC_SUPPORT_PHONE ?? "";

const FAQS: { q: string; a: string }[] = [
  {
    q: "How do I add a booking for a walk-in guest?",
    a: "Open Guest Bookings and choose Create Booking. Pick the guest, the sport and court, the time, then record the payment. The slot is held the moment you confirm it.",
  },
  {
    q: "How do I create a membership for a member?",
    a: "Go to Memberships and choose Create Membership. Select the member, a plan and the court timings they will use, then record what they have paid. Anything unpaid shows up under Pending Payments.",
  },
  {
    q: "Where can I see what I'm owed?",
    a: "Finance → Pending Payments lists every membership and guest booking that still has a balance, with the due date. Collect a payment from there and it updates your Finance and Reports figures straight away.",
  },
  {
    q: "How do I change my courts, timings or pricing?",
    a: "Open Profile → Manage Facility Details and use the Edit button beside the section you want to change. Existing bookings keep the price they were made at.",
  },
  {
    q: "Where do my payouts go?",
    a: "To the primary bank account or UPI ID under Profile → Payment Methods. Only the facility owner can see or change these details.",
  },
  {
    q: "What does my GameAll plan cost, and when does it end?",
    a: "GameAll charges a flat membership fee, never a commission on your bookings. Your plan, its price and its valid-till date are shown on your Profile page.",
  },
  {
    q: "I forgot my password.",
    a: "Use Profile → Settings → Change password while you're signed in. If you're signed out, choose “Forgot password” on the sign-in screen and we'll email you a reset link.",
  },
];

const STATUS_LABEL: Record<SupportStatus, string> = {
  OPEN: "Open",
  IN_PROGRESS: "In progress",
  RESOLVED: "Resolved",
  CLOSED: "Closed",
};

function formatWhen(iso: string): string {
  return new Date(iso).toLocaleDateString("en-IN", { day: "numeric", month: "short", year: "numeric" });
}

function RaiseTicketForm({ facilityId }: { facilityId: string }) {
  const qc = useQueryClient();
  const [category, setCategory] = useState<SupportCategory>("GENERAL");
  const [subject, setSubject] = useState("");
  const [message, setMessage] = useState("");
  const [errors, setErrors] = useState<Record<string, string>>({});
  const [sent, setSent] = useState(false);

  const create = useMutation({
    mutationFn: () => getProfileService().createSupportTicket(facilityId, { category, subject, message }),
    onSuccess: async () => {
      setSubject("");
      setMessage("");
      setSent(true);
      await qc.invalidateQueries({ queryKey: profileKeys.tickets(facilityId) });
    },
    onError: (e) => setErrors({ form: e instanceof Error ? e.message : "Could not send your request." }),
  });

  function submit(e: React.FormEvent) {
    e.preventDefault();
    setSent(false);
    const parsed = supportTicketSchema.safeParse({ category, subject, message });
    if (!parsed.success) {
      const next: Record<string, string> = {};
      for (const issue of parsed.error.issues) next[String(issue.path[0])] ??= issue.message;
      return setErrors(next);
    }
    setErrors({});
    create.mutate();
  }

  return (
    <form onSubmit={submit} className="space-y-4" noValidate>
      <div className="grid gap-4 sm:grid-cols-2">
        <div className="space-y-1.5">
          <Label htmlFor="ticket-category">What is it about?</Label>
          <Select value={category} onValueChange={(v) => setCategory(v as SupportCategory)}>
            <SelectTrigger id="ticket-category">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              {SUPPORT_CATEGORIES.map((c) => (
                <SelectItem key={c.value} value={c.value}>
                  {c.label}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        </div>
        <div className="space-y-1.5">
          <Label htmlFor="ticket-subject">Subject</Label>
          <Input id="ticket-subject" value={subject} onChange={(e) => setSubject(e.target.value)} placeholder="A short summary" maxLength={140} />
          {errors.subject && <p className="text-xs text-destructive">{errors.subject}</p>}
        </div>
      </div>
      <div className="space-y-1.5">
        <Label htmlFor="ticket-message">Tell us what happened</Label>
        <Textarea id="ticket-message" value={message} onChange={(e) => setMessage(e.target.value)} rows={5} maxLength={4000} placeholder="Include the page you were on and what you expected to see." />
        {errors.message && <p className="text-xs text-destructive">{errors.message}</p>}
      </div>
      {errors.form && (
        <p role="alert" className="text-sm text-destructive">
          {errors.form}
        </p>
      )}
      {sent && (
        <p role="status" className="rounded-lg bg-success/10 px-3 py-2 text-sm text-success">
          Thanks — your request is with our team. We&apos;ll get back to you by email.
        </p>
      )}
      <Button type="submit" disabled={create.isPending}>
        <Send className="mr-1.5 h-4 w-4" aria-hidden /> {create.isPending ? "Sending…" : "Send request"}
      </Button>
    </form>
  );
}

/** Help & Support: contact details, answers to common questions, and a way to raise a request. */
export function SupportPage() {
  const { data: facility, isLoading } = useFacility();
  const tickets = useSupportTickets(facility?.id);
  const hasContact = SUPPORT_EMAIL !== "" || SUPPORT_PHONE !== "";

  return (
    <div className="space-y-4">
      <SubPageHeader title="Help & Support" description="Find an answer, or tell us what's wrong and we'll sort it out." />

      {hasContact && (
        <div className="grid gap-3 sm:grid-cols-2">
          {SUPPORT_EMAIL && (
            <a
              href={`mailto:${SUPPORT_EMAIL}`}
              className="flex items-center gap-3 rounded-xl border border-border bg-card p-4 transition-shadow hover:shadow-md"
            >
              <span className="flex h-10 w-10 items-center justify-center rounded-xl bg-primary/10 text-primary">
                <Mail className="h-5 w-5" aria-hidden />
              </span>
              <span>
                <span className="block text-sm font-semibold">Email us</span>
                <span className="block text-xs text-muted-foreground">{SUPPORT_EMAIL}</span>
              </span>
            </a>
          )}
          {SUPPORT_PHONE && (
            <a
              href={`tel:${SUPPORT_PHONE.replace(/\s/g, "")}`}
              className="flex items-center gap-3 rounded-xl border border-border bg-card p-4 transition-shadow hover:shadow-md"
            >
              <span className="flex h-10 w-10 items-center justify-center rounded-xl bg-primary/10 text-primary">
                <Phone className="h-5 w-5" aria-hidden />
              </span>
              <span>
                <span className="block text-sm font-semibold">Call us</span>
                <span className="block text-xs text-muted-foreground">{SUPPORT_PHONE}</span>
              </span>
            </a>
          )}
        </div>
      )}

      <SectionCard title="Frequently asked questions" description="Quick answers to what owners ask most.">
        <div className="divide-y divide-border">
          {FAQS.map((f) => (
            <details key={f.q} className="group py-3 first:pt-0 last:pb-0">
              <summary className="flex cursor-pointer list-none items-center justify-between gap-3 text-sm font-medium outline-none focus-visible:ring-2 focus-visible:ring-ring [&::-webkit-details-marker]:hidden">
                {f.q}
                <ChevronDown className="h-4 w-4 shrink-0 text-muted-foreground transition-transform group-open:rotate-180" aria-hidden />
              </summary>
              <p className="mt-2 text-sm leading-relaxed text-muted-foreground">{f.a}</p>
            </details>
          ))}
        </div>
      </SectionCard>

      <SectionCard title="Raise a support request" description="Our team replies by email.">
        {isLoading ? (
          <Skeleton className="h-56 w-full rounded-lg" />
        ) : facility ? (
          <RaiseTicketForm facilityId={facility.id} />
        ) : (
          <PageMessage>No facility is set up for this account yet.</PageMessage>
        )}
      </SectionCard>

      <SectionCard title="Your recent requests">
        {tickets.isLoading ? (
          <Skeleton className="h-16 w-full rounded-lg" />
        ) : tickets.isError ? (
          <PageMessage tone="error">Unable to load your requests.</PageMessage>
        ) : (tickets.data ?? []).length === 0 ? (
          <p className="flex items-center gap-2 text-sm text-muted-foreground">
            <LifeBuoy className="h-4 w-4" aria-hidden /> You haven&apos;t raised any requests yet.
          </p>
        ) : (
          <ul className="divide-y divide-border">
            {tickets.data!.map((t) => (
              <li key={t.id} className="flex items-start gap-3 py-3 first:pt-0 last:pb-0">
                <MessageSquareText className="mt-0.5 h-4 w-4 shrink-0 text-muted-foreground" aria-hidden />
                <div className="min-w-0 flex-1">
                  <p className="truncate text-sm font-medium">{t.subject}</p>
                  <p className="text-xs text-muted-foreground">
                    {SUPPORT_CATEGORIES.find((c) => c.value === t.category)?.label} · {formatWhen(t.createdAt)}
                  </p>
                </div>
                <Badge variant={t.status === "RESOLVED" || t.status === "CLOSED" ? "secondary" : "success"} className={t.status === "OPEN" || t.status === "IN_PROGRESS" ? "bg-success/15 text-success" : ""}>
                  {STATUS_LABEL[t.status]}
                </Badge>
              </li>
            ))}
          </ul>
        )}
      </SectionCard>
    </div>
  );
}
