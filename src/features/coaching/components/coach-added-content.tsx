"use client";

import { useMemo } from "react";
import { Check, PartyPopper } from "lucide-react";
import { Avatar, AvatarFallback } from "@/components/ui/avatar";
import { Badge } from "@/components/ui/badge";
import { initials } from "@/features/coaching/components/shared";
import { cn } from "@/lib/utils";

/**
 * The "Coach Added Successfully" body — checkmark, coach summary, the four next-action cards.
 * No outer wrapper or footer buttons: the full-page route wraps this in a centered Card, the
 * Add Coach sheet renders it straight inside its own SheetBody with a SheetFooter alongside.
 */
export function CoachAddedContent({ coachId, name, onNavigate }: { coachId: string; name: string; onNavigate: (href: string) => void }) {
  const actions = useMemo(
    () => [
      {
        title: "Schedule a Session",
        desc: `Create a new coaching session for ${name}.`,
        href: `/coaching/sessions/new?coachId=${coachId}`,
        tone: "bg-success/10 hover:bg-success/15",
      },
      {
        title: "Manage Availability",
        desc: "Set working days, time slots and session duration.",
        href: `/coaching/coaches/${coachId}?tab=Availability`,
        tone: "bg-blue-500/10 hover:bg-blue-500/15",
      },
      {
        title: "Assign to Program",
        desc: `Add ${name} to an existing or new coaching program.`,
        href: `/coaching/programs`,
        tone: "bg-purple-500/10 hover:bg-purple-500/15",
      },
      {
        title: "View Coach Profile",
        desc: "Go to coach profile to manage details and settings.",
        href: `/coaching/coaches/${coachId}`,
        tone: "bg-warning/10 hover:bg-warning/15",
      },
    ],
    [coachId, name],
  );

  return (
    <div className="space-y-6 text-center">
      <div className="mx-auto flex h-16 w-16 items-center justify-center rounded-full bg-success/15 text-success">
        <PartyPopper className="h-8 w-8" aria-hidden />
      </div>
      <div>
        <h2 className="text-lg font-semibold">Coach Added Successfully!</h2>
        <p className="mt-1 text-sm text-muted-foreground">
          {name} has been added to your coaching team and can now take sessions and manage their schedule.
        </p>
      </div>

      <div className="flex items-center gap-3 rounded-xl border border-border p-4 text-left">
        <Avatar className="h-12 w-12">
          <AvatarFallback>{initials(name)}</AvatarFallback>
        </Avatar>
        <div className="min-w-0">
          <p className="truncate font-medium">{name}</p>
          <Badge variant="success" className="mt-1">
            <Check className="mr-1 h-3 w-3" aria-hidden /> Active
          </Badge>
        </div>
      </div>

      <div className="space-y-2 text-left">
        <h3 className="text-sm font-semibold">What would you like to do next?</h3>
        {actions.map((a) => (
          <button
            key={a.title}
            type="button"
            onClick={() => onNavigate(a.href)}
            className={cn("flex w-full items-center justify-between rounded-lg p-3 text-left transition-colors", a.tone)}
          >
            <span>
              <span className="block text-sm font-medium">{a.title}</span>
              <span className="block text-xs text-muted-foreground">{a.desc}</span>
            </span>
          </button>
        ))}
      </div>
    </div>
  );
}
