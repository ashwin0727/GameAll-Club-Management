"use client";

import { ChevronRight, ClipboardList, Plus, UserPlus } from "lucide-react";
import { Card } from "@/components/ui/card";

function Action({
  icon: Icon,
  tone,
  title,
  sub,
  onClick,
}: {
  icon: React.ComponentType<{ className?: string }>;
  tone: string;
  title: string;
  sub: string;
  onClick?: () => void;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      className="flex w-full items-center gap-3 rounded-xl border border-transparent p-2.5 text-left transition-colors hover:border-border hover:bg-accent/50"
    >
      <span className={`flex h-9 w-9 shrink-0 items-center justify-center rounded-lg ${tone}`}>
        <Icon className="h-4.5 w-4.5" aria-hidden />
      </span>
      <span className="min-w-0 flex-1">
        <span className="block truncate text-sm font-medium text-foreground">{title}</span>
        <span className="block truncate text-xs text-muted-foreground">{sub}</span>
      </span>
      <ChevronRight className="h-4 w-4 shrink-0 text-muted-foreground" aria-hidden />
    </button>
  );
}

/**
 * Quick Actions: all three go straight to their existing flows.
 */
export function QuickActionsPanel({
  onAddMember,
  onCreatePlan,
  onManageSchedule,
}: {
  onAddMember: () => void;
  onCreatePlan: () => void;
  onManageSchedule: () => void;
}) {
  return (
    <Card className="stat-enter space-y-1 p-4 sm:p-5" style={{ "--stat-delay": "260ms" } as React.CSSProperties}>
      <h3 className="mb-2 text-sm font-semibold">Quick Actions</h3>
      <Action icon={UserPlus} tone="bg-success/15 text-success" title="Add New Member" sub="Register a new member" onClick={onAddMember} />
      <Action
        icon={Plus}
        tone="bg-blue-500/15 text-blue-600 dark:text-blue-400"
        title="Create Membership Plan"
        sub="Set up new membership plans"
        onClick={onCreatePlan}
      />
      <Action
        icon={ClipboardList}
        tone="bg-warning/15 text-warning"
        title="Manage Membership Schedule"
        sub="View and update playing slots"
        onClick={onManageSchedule}
      />
    </Card>
  );
}
