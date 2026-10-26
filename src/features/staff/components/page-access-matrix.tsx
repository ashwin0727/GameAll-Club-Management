"use client";

import { Check, Eye, Lock, Pencil } from "lucide-react";
import { cn } from "@/lib/utils";
import { usePermissionContext } from "@/features/auth/context/permission-provider";
import {
  ACCESS_GROUPS,
  COACHING_OWN_ONLY,
  MANAGED_KEYS,
  editorLevelFor,
  type AccessLevel,
  type AccessPage,
  type EditorLevel,
  type PageKey,
} from "@/features/access/access";

/**
 * The role editor's permission screen: every page of the app, grouped like the menu, each set to None / View / Edit.
 * [selected] is the role's permission-key set (the source of truth); choosing a level rewrites that page's keys.
 * [canGrant] says whether the signed-in editor may hand out a key (an administrator can only grant what they hold).
 */
export function PageAccessMatrix({
  selected,
  onChange,
  canGrant,
}: {
  selected: ReadonlySet<string>;
  onChange: (next: Set<string>) => void;
  canGrant: (key: string) => boolean;
}) {
  const planCtx = usePermissionContext();
  /** A page the club's plan does not include cannot be switched on for anyone — owner included. */
  const inPlan = (page: AccessPage) => (planCtx ? planCtx.pageInPlan(page.key as PageKey) : true);
  function setLevel(page: AccessPage, level: AccessLevel) {
    const next = new Set(selected);
    for (const k of [...page.viewKeys, ...page.editKeys]) next.delete(k);
    if (level === "none") {
      for (const k of page.extraKeys) next.delete(k);
    } else {
      page.viewKeys.forEach((k) => next.add(k));
      if (level === "edit") page.editKeys.forEach((k) => next.add(k));
    }
    onChange(next);
  }

  function setGroup(pages: AccessPage[], level: AccessLevel) {
    const next = new Set(selected);
    for (const page of pages) {
      const allowed = optionAllowed(page, level);
      if (!allowed) continue;
      for (const k of [...page.viewKeys, ...page.editKeys]) next.delete(k);
      if (level === "none") {
        for (const k of page.extraKeys) next.delete(k);
      } else {
        page.viewKeys.forEach((k) => next.add(k));
        // "Edit" on a view-only page just means View.
        if (level === "edit") page.editKeys.forEach((k) => next.add(k));
      }
    }
    onChange(next);
  }

  function toggleKey(key: string) {
    const next = new Set(selected);
    if (next.has(key)) next.delete(key);
    else next.add(key);
    onChange(next);
  }

  function optionAllowed(page: AccessPage, level: AccessLevel): boolean {
    if (level === "none") return true;
    if (!inPlan(page)) return false;
    const keys = level === "edit" ? [...page.viewKeys, ...page.editKeys] : page.viewKeys;
    return keys.every(canGrant);
  }

  const unmanaged = [...selected].filter((k) => !MANAGED_KEYS.has(k)).length;

  return (
    <div className="space-y-5">
      <div className="rounded-lg border border-border bg-muted/30 p-3 text-xs text-muted-foreground">
        <p>
          <span className="font-medium text-foreground">None</span> — the page is hidden completely.{" "}
          <span className="font-medium text-foreground">View</span> — can look, but not change or export anything.{" "}
          <span className="font-medium text-foreground">Edit</span> — can also create, change, cancel, record payments and export.
        </p>
      </div>

      {ACCESS_GROUPS.map((group) => (
        <section key={group.label} className="rounded-xl border border-border">
          <header className="flex flex-wrap items-center justify-between gap-2 border-b border-border bg-muted/30 px-4 py-2.5">
            <h3 className="text-sm font-semibold">{group.label}</h3>
            <div className="flex gap-1.5 text-xs">
              <button type="button" className="rounded-md border border-border px-2 py-1 hover:bg-accent" onClick={() => setGroup(group.pages, "none")}>
                All None
              </button>
              <button type="button" className="rounded-md border border-border px-2 py-1 hover:bg-accent" onClick={() => setGroup(group.pages, "view")}>
                All View
              </button>
              <button type="button" className="rounded-md border border-border px-2 py-1 hover:bg-accent" onClick={() => setGroup(group.pages, "edit")}>
                All Edit
              </button>
            </div>
          </header>

          <ul className="divide-y divide-border">
            {group.pages.map((page) => {
              const level: EditorLevel = editorLevelFor(page, selected);
              return (
                <li key={page.key} className="px-4 py-3">
                  <div className="flex flex-wrap items-center justify-between gap-3">
                    <div className="min-w-0 flex-1">
                      <p className="text-sm font-medium">
                        {page.key === "HOME" ? "Home (Today in the mobile app)" : page.label}
                        {!inPlan(page) && (
                          <a
                            href="/plans"
                            className="ml-2 rounded-full bg-primary/10 px-2 py-0.5 align-middle text-[10px] font-semibold uppercase tracking-wide text-primary"
                            title="This page is not part of your club's current plan"
                          >
                            Not in your plan
                          </a>
                        )}
                      </p>
                      <p className="text-xs text-muted-foreground">{page.description}</p>
                    </div>
                    <div role="radiogroup" aria-label={`${page.label} access`} className="inline-flex shrink-0 overflow-hidden rounded-lg border border-border text-xs">
                      <LevelButton icon={Lock} label="None" active={level === "none"} onClick={() => setLevel(page, "none")} />
                      <LevelButton
                        icon={Eye}
                        label="View"
                        active={level === "view"}
                        disabled={!optionAllowed(page, "view")}
                        onClick={() => setLevel(page, "view")}
                      />
                      {page.canEdit && (
                        <LevelButton
                          icon={Pencil}
                          label={page.editLabel ?? "Edit"}
                          active={level === "edit"}
                          disabled={!optionAllowed(page, "edit")}
                          onClick={() => setLevel(page, "edit")}
                        />
                      )}
                    </div>
                  </div>

                  {level === "custom" && (
                    <p className="mt-2 text-xs text-warning">
                      This role has some, but not all, Edit rights here (set before this screen existed). Pick Edit to grant all
                      of them, or View to remove them.
                    </p>
                  )}

                  {level !== "none" && page.extraKeys.length > 0 && (
                    <ul className="mt-2 space-y-1 border-l-2 border-border pl-3">
                      {page.extraKeys.map((key) => (
                        <li key={key}>
                          <label className={cn("flex items-center gap-2 text-xs", !canGrant(key) && "opacity-50")}>
                            <input
                              type="checkbox"
                              className="h-3.5 w-3.5"
                              checked={selected.has(key)}
                              disabled={!canGrant(key)}
                              onChange={() => toggleKey(key)}
                            />
                            {EXTRA_LABELS[key] ?? key}
                          </label>
                        </li>
                      ))}
                    </ul>
                  )}
                </li>
              );
            })}
          </ul>

          {group.label === "Coaching" && (
            <div className="flex items-start justify-between gap-3 border-t border-border bg-muted/20 px-4 py-3">
              <div>
                <p className="text-sm font-medium">Limit to their own coach profile</p>
                <p className="text-xs text-muted-foreground">
                  For coach roles: Coaching shows only this person&apos;s own coach profile, sessions, programs and students, and the
                  Sessions coach filter is locked to them. Leave Schedule and Reports at None.
                </p>
              </div>
              <ToggleSwitch
                checked={selected.has(COACHING_OWN_ONLY)}
                disabled={!canGrant(COACHING_OWN_ONLY)}
                onClick={() => toggleKey(COACHING_OWN_ONLY)}
                label="Limit coaching to their own coach profile"
              />
            </div>
          )}
        </section>
      ))}

      {unmanaged > 0 && (
        <p className="text-xs text-muted-foreground">
          {unmanaged} other permission{unmanaged === 1 ? "" : "s"} on this role (for features not shown here) are kept as they are.
        </p>
      )}
    </div>
  );
}

const EXTRA_LABELS: Record<string, string> = {
  BOOKINGS_VIEW_CUSTOMER: "Can see customer / member contact details on bookings",
  FINANCE_REOPEN_CLOSING: "Can reopen a closed day",
  USERS_MANAGE_FACILITY_ACCESS: "Can grant access to other facilities",
};

function LevelButton({
  icon: Icon,
  label,
  active,
  disabled,
  onClick,
}: {
  icon: React.ComponentType<{ className?: string }>;
  label: string;
  active: boolean;
  disabled?: boolean;
  onClick: () => void;
}) {
  return (
    <button
      type="button"
      role="radio"
      aria-checked={active}
      disabled={disabled}
      onClick={onClick}
      className={cn(
        "inline-flex items-center gap-1.5 border-r border-border px-3 py-1.5 font-medium transition-colors last:border-r-0 disabled:cursor-not-allowed disabled:opacity-40",
        active ? "bg-primary text-primary-foreground" : "bg-background text-muted-foreground hover:bg-accent",
      )}
    >
      {active ? <Check className="h-3.5 w-3.5" aria-hidden /> : <Icon className="h-3.5 w-3.5" aria-hidden />}
      {label}
    </button>
  );
}

function ToggleSwitch({ checked, disabled, onClick, label }: { checked: boolean; disabled?: boolean; onClick: () => void; label: string }) {
  return (
    <button
      type="button"
      role="switch"
      aria-checked={checked}
      aria-label={label}
      disabled={disabled}
      onClick={onClick}
      className={cn(
        "relative mt-0.5 inline-flex h-6 w-11 shrink-0 items-center rounded-full transition-colors disabled:cursor-not-allowed disabled:opacity-40",
        checked ? "bg-primary" : "bg-muted-foreground/30",
      )}
    >
      <span className={cn("inline-block h-5 w-5 rounded-full bg-white shadow transition-transform", checked ? "translate-x-5" : "translate-x-0.5")} />
    </button>
  );
}
